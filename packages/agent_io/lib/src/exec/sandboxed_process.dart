import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../package_asset.dart';
import '../sandbox/sandbox_backend.dart';
import '../sandbox/sandbox_capability.dart';
import '../sandbox/sandbox_errors.dart';
import '../sandbox/sandbox_policy.dart';
import '../sandbox/sandbox_prepared_backend.dart';
import '../sandbox/sandbox_startup_handshake.dart';
import 'process_group.dart';
import 'process_cleanup_ledger.dart';
import 'process_recovery_coordinator.dart';

final class SandboxedProcessLauncher {
  factory SandboxedProcessLauncher(
    SandboxBackend backend, {
    String? runnerPath,
    String? hostDataDirectory,
    String? cleanupLedgerPath,
    String? sessionIdentity,
    SandboxStartupObserver? startupObserver,
  }) {
    final stable = hostDataDirectory != null &&
        sessionIdentity != null &&
        cleanupLedgerPath == null;
    final ledgerPath = stable
        ? ProcessRecoveryCoordinator(hostDataDirectory)
            .ledgerPathFor(sessionIdentity)
        : cleanupLedgerPath ?? _ephemeralLedgerPath();
    return SandboxedProcessLauncher._(
      backend,
      runnerPath: runnerPath,
      sessionIdentity: sessionIdentity ?? 'unconfigured',
      ledgerPath: ledgerPath,
      productionConfigured: stable,
      startupObserver: startupObserver,
    );
  }

  factory SandboxedProcessLauncher.unsafeDev(
    SandboxBackend backend, {
    String? runnerPath,
    String? cleanupLedgerPath,
    String? sessionIdentity,
    SandboxStartupObserver? startupObserver,
  }) =>
      SandboxedProcessLauncher._(
        backend,
        runnerPath: runnerPath,
        sessionIdentity:
            sessionIdentity ?? _ephemeralIdentity('unsafe-dev-session'),
        ledgerPath: cleanupLedgerPath ?? _ephemeralLedgerPath(),
        productionConfigured: true,
        startupObserver: startupObserver,
      );

  SandboxedProcessLauncher._(
    this.backend, {
    required String? runnerPath,
    required String sessionIdentity,
    required String ledgerPath,
    required bool productionConfigured,
    required SandboxStartupObserver? startupObserver,
  })  : _runnerPath = runnerPath,
        _sessionIdentity = sessionIdentity,
        _ledger = ProcessCleanupLedger(ledgerPath),
        _productionConfigured = productionConfigured,
        _startupObserver = startupObserver;

  static Future<SandboxedProcessLauncher> recoverProduction(
    SandboxBackend backend, {
    required String hostDataDirectory,
    required String sessionIdentity,
    String? runnerPath,
  }) async {
    final recovery =
        await ProcessRecoveryCoordinator(hostDataDirectory).recoverPending();
    if (!recovery.confirmed) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'production-recovery-unconfirmed',
      );
    }
    return SandboxedProcessLauncher(
      backend,
      runnerPath: runnerPath,
      hostDataDirectory: hostDataDirectory,
      sessionIdentity: sessionIdentity,
    );
  }

  final SandboxBackend backend;
  final String? _runnerPath;
  final String _sessionIdentity;
  final ProcessCleanupLedger _ledger;
  final bool _productionConfigured;
  final SandboxStartupObserver? _startupObserver;
  final Map<int, ProcessGroup> _groups = <int, ProcessGroup>{};
  final Map<int, ProcessCleanupRecord> _records = <int, ProcessCleanupRecord>{};
  Future<void> _operation = Future<void>.value();

  Future<SandboxedProcess> launch(
    SandboxPolicy policy,
    HostCommand command,
  ) =>
      _serialized(() async {
        await _guardLaunch();
        _rejectShellSyntax(command);
        final encoded = base64Url.encode(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'arguments': command.arguments,
              'executable': command.executable,
            }),
          ),
        );
        final runnerPath = await resolveAgentIoPackageAsset(
          'src/exec/process_group_runner.dart',
          overridePath: _runnerPath,
        );
        final groupedCommand = backend.establishesProcessGroup
            ? command
            : HostCommand(
                executable: Platform.resolvedExecutable,
                arguments: <String>[runnerPath, encoded],
                workingDirectory: command.workingDirectory,
                environment: command.environment,
              );
        ProcessCleanupRecord? startupRecord;
        SandboxedProcess process;
        try {
          final currentBackend = backend;
          process = currentBackend is PreparedSandboxBackend
              ? await currentBackend.startPrepared(
                  policy,
                  command,
                  persistProcessGroup: (processGroupId) async {
                    final identity =
                        ProcessGroup.captureIdentity(processGroupId);
                    if (identity == null) {
                      throw const HostCapabilityException(
                        HostCapabilityError.processCleanupFailed,
                        'process-identity-unavailable',
                      );
                    }
                    final record = ProcessCleanupRecord(
                      sessionIdentity: _sessionIdentity,
                      processGroupId: processGroupId,
                      processIdentity: identity,
                    );
                    await _ledger.record(record);
                    startupRecord = record;
                    return record;
                  },
                )
              : await currentBackend.start(policy, groupedCommand);
        } on Object {
          final record = startupRecord;
          if (record != null) {
            try {
              await _cleanupRecord(record);
            } on Object {
              // Keep the write-ahead record pending when cleanup is unconfirmed.
            }
          }
          rethrow;
        }
        final group = ProcessGroup(process.pid);
        await group.waitUntilEstablished();
        final record = startupRecord ??
            ProcessCleanupRecord(
              sessionIdentity: _sessionIdentity,
              processGroupId: process.pid,
              processIdentity: _requireProcessIdentity(process.pid),
            );
        if (startupRecord == null) await _ledger.record(record);
        _groups[process.pid] = group;
        _records[process.pid] = record;
        return process;
      });

  Future<SandboxedProcess> launchBroker(
    HostCommand command,
    SandboxCapabilityReport capability,
  ) =>
      _serialized(() async {
        await _guardLaunch();
        _rejectShellSyntax(command);
        ProcessCleanupRecord? startupRecord;
        final process = await Process.start(
          command.executable,
          command.arguments,
          workingDirectory: command.workingDirectory,
          environment: command.environment,
          runInShell: false,
        );
        try {
          final output = await awaitSandboxStartup(
            process,
            observer: _startupObserver,
            persistProcessGroup: (processGroupId) async {
              final record = ProcessCleanupRecord(
                sessionIdentity: _sessionIdentity,
                processGroupId: processGroupId,
                processIdentity: _requireProcessIdentity(processGroupId),
              );
              await _ledger.record(record);
              startupRecord = record;
              return record;
            },
          );
          final record = startupRecord;
          if (record == null) {
            throw const HostCapabilityException(
              HostCapabilityError.processCleanupFailed,
              'pty-process-group-not-persisted',
            );
          }
          _groups[process.pid] = ProcessGroup(record.processGroupId);
          _records[process.pid] = record;
          return SandboxedProcess(
            process,
            capability,
            stdout: output,
            processGroupId: record.processGroupId,
          );
        } on Object {
          final record = startupRecord;
          if (record != null) {
            try {
              await _cleanupRecord(record);
            } on Object {
              // Preserve the ledger when crash-window cleanup is unconfirmed.
            }
          }
          process.kill(ProcessSignal.sigkill);
          rethrow;
        }
      });

  Future<ProcessTreeCleanupReport> cleanup(SandboxedProcess process) =>
      _serialized(() async {
        final group = _groups[process.pid] ?? ProcessGroup(process.pid);
        final record = _records[process.pid] ??
            (await _ledger.pending(_sessionIdentity))
                .where((entry) => entry.processGroupId == process.pid)
                .firstOrNull;
        if (record == null) {
          throw const HostCapabilityException(
            HostCapabilityError.processCleanupFailed,
            'recorded-process-identity-missing',
          );
        }
        final report = await _cleanupRecord(record, group: group);
        if (report.confirmed) {
          _groups.remove(process.pid);
          _records.remove(process.pid);
        }
        return report;
      });

  Future<ProcessTreeCleanupReport> cleanupRecorded(int processGroupId) =>
      _serialized(() async {
        final matches = (await _ledger.pending(_sessionIdentity))
            .where((record) => record.processGroupId == processGroupId)
            .toList();
        if (matches.length != 1) {
          throw const HostCapabilityException(
            HostCapabilityError.processCleanupFailed,
            'recorded-process-identity-missing',
          );
        }
        final record = matches.single;
        return _cleanupRecord(record);
      });

  Future<ProcessTreeCleanupReport> _cleanupRecord(
    ProcessCleanupRecord record, {
    ProcessGroup? group,
  }) async {
    final currentIdentity = ProcessGroup.captureIdentity(record.processGroupId);
    if (currentIdentity == null) {
      await _ledger.confirm(record);
      return ProcessTreeCleanupReport(
        processGroupId: record.processGroupId,
        confirmed: true,
        forced: false,
      );
    }
    if (currentIdentity != record.processIdentity) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'recorded-process-identity-mismatch',
      );
    }
    final report =
        await (group ?? ProcessGroup(record.processGroupId)).cleanup();
    if (report.confirmed) await _ledger.confirm(record);
    return report;
  }

  Future<void> _guardLaunch() async {
    if (!_productionConfigured) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'stable-host-data-and-session-required',
      );
    }
    if ((await _ledger.pending(_sessionIdentity)).isNotEmpty) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'previous-cleanup-unconfirmed',
      );
    }
  }

  String _requireProcessIdentity(int processId) {
    final identity = ProcessGroup.captureIdentity(processId);
    if (identity == null) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'process-identity-unavailable',
      );
    }
    return identity;
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _operation;
    final done = Completer<void>();
    _operation = done.future;
    return previous.then((_) => action()).whenComplete(done.complete);
  }

  void _rejectShellSyntax(HostCommand command) {
    final shellSyntax = RegExp(r'''[;&|`$<>]''');
    if (shellSyntax.hasMatch(command.executable) ||
        command.arguments.any(shellSyntax.hasMatch)) {
      throw const HostCapabilityException(
        HostCapabilityError.shellInjectionRejected,
        'shell-metacharacter',
      );
    }
  }
}

String _ephemeralIdentity(String prefix) =>
    '$prefix-$pid-${DateTime.now().microsecondsSinceEpoch}-'
    '${Random.secure().nextInt(1 << 32)}';

String _ephemeralLedgerPath() =>
    '${Directory.systemTemp.path}/pigcode-agent-io-cleanup-'
    '${_ephemeralIdentity('launcher')}.json';
