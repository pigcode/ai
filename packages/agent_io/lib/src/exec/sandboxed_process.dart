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
    final coordinator =
        stable ? ProcessRecoveryCoordinator(hostDataDirectory) : null;
    final ledgerPath = stable
        ? coordinator!.ledgerPathFor(sessionIdentity)
        : cleanupLedgerPath ?? _ephemeralLedgerPath();
    return SandboxedProcessLauncher._(
      backend,
      runnerPath: runnerPath,
      sessionIdentity: sessionIdentity ?? 'unconfigured',
      ledgerPath: ledgerPath,
      productionConfigured: stable,
      startupObserver: startupObserver,
      recoveryCoordinator: coordinator,
      allowShellSyntaxForTests: false,
    );
  }

  factory SandboxedProcessLauncher.unsafeDev(
    SandboxBackend backend, {
    String? runnerPath,
    String? cleanupLedgerPath,
    String? sessionIdentity,
    SandboxStartupObserver? startupObserver,
    bool allowShellSyntaxForTests = false,
  }) =>
      SandboxedProcessLauncher._(
        backend,
        runnerPath: runnerPath,
        sessionIdentity:
            sessionIdentity ?? _ephemeralIdentity('unsafe-dev-session'),
        ledgerPath: cleanupLedgerPath ?? _ephemeralLedgerPath(),
        productionConfigured: true,
        startupObserver: startupObserver,
        recoveryCoordinator: null,
        allowShellSyntaxForTests: allowShellSyntaxForTests,
      );

  SandboxedProcessLauncher._(
    this.backend, {
    required String? runnerPath,
    required String sessionIdentity,
    required String ledgerPath,
    required bool productionConfigured,
    required SandboxStartupObserver? startupObserver,
    required ProcessRecoveryCoordinator? recoveryCoordinator,
    required bool allowShellSyntaxForTests,
  })  : _runnerPath = runnerPath,
        _sessionIdentity = sessionIdentity,
        _ledger = ProcessCleanupLedger(ledgerPath),
        _productionConfigured = productionConfigured,
        _startupObserver = startupObserver,
        _recoveryCoordinator = recoveryCoordinator,
        _allowShellSyntaxForTests = allowShellSyntaxForTests;

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
  final ProcessRecoveryCoordinator? _recoveryCoordinator;
  final bool _allowShellSyntaxForTests;
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
                    await _recordCleanup(record);
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
        if (startupRecord == null) await _recordCleanup(record);
        _groups[process.pid] = group;
        _records[process.pid] = record;
        return process;
      });

  Future<SandboxedProcess> launchBroker(
    HostCommand command,
    SandboxCapabilityReport capability, {
    Duration startupBudget = const Duration(seconds: 5),
  }) =>
      _serialized(() async {
        await _guardLaunch();
        _rejectShellSyntax(command);
        ProcessCleanupRecord? startupRecord;
        final writeAhead = base64Url.encode(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'ledgerPath': _ledger.path,
              'sessionIdentity': _sessionIdentity,
            }),
          ),
        );
        final process = await Process.start(
          command.executable,
          <String>[...command.arguments, writeAhead],
          workingDirectory: command.workingDirectory,
          environment: command.environment,
          runInShell: false,
        );
        try {
          final output = await awaitSandboxStartup(
            process,
            observer: _startupObserver,
            requireParentWriteAhead: true,
            timeout: startupBudget,
            persistProcessGroup: (processGroupId) async {
              final records = (await _ledger.pending(_sessionIdentity))
                  .where(
                    (record) => record.processGroupId == processGroupId,
                  )
                  .toList(growable: false);
              if (records.isEmpty) {
                final emergency = ProcessCleanupRecord(
                  sessionIdentity: _sessionIdentity,
                  processGroupId: processGroupId,
                  processIdentity: _requireProcessIdentity(processGroupId),
                );
                await _recordCleanup(emergency);
                startupRecord = emergency;
                throw const HostCapabilityException(
                  HostCapabilityError.processCleanupFailed,
                  'pty-parent-write-ahead-missing',
                );
              }
              if (records.length != 1) {
                throw const HostCapabilityException(
                  HostCapabilityError.processCleanupFailed,
                  'pty-parent-write-ahead-ambiguous',
                );
              }
              final record = records.single;
              if (record.processIdentity !=
                  _requireProcessIdentity(processGroupId)) {
                throw const HostCapabilityException(
                  HostCapabilityError.processCleanupFailed,
                  'pty-parent-write-ahead-identity-mismatch',
                );
              }
              await _recoveryCoordinator?.markPending(record);
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
        final group =
            _groups[process.pid] ?? ProcessGroup(process.processGroupId);
        final record = _records[process.pid] ??
            (await _ledger.pending(_sessionIdentity))
                .where((entry) => entry.processGroupId == process.pid)
                .firstOrNull;
        if (record == null) {
          if (ProcessGroup.captureIdentity(process.processGroupId) == null) {
            return ProcessTreeCleanupReport(
              processGroupId: process.processGroupId,
              confirmed: true,
              forced: false,
            );
          }
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
      await _confirmCleanup(record);
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
    if (report.confirmed) await _confirmCleanup(record);
    return report;
  }

  Future<void> _recordCleanup(ProcessCleanupRecord record) async {
    await _ledger.record(record);
    await _recoveryCoordinator?.markPending(record);
  }

  Future<void> _confirmCleanup(ProcessCleanupRecord record) async {
    await _recoveryCoordinator?.markRecovered(record);
    await _ledger.confirm(record);
  }

  Future<void> _guardLaunch() async {
    if (!_productionConfigured) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'stable-host-data-and-session-required',
      );
    }
    await _recoveryCoordinator?.registerSession(_sessionIdentity);
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
    if (_allowShellSyntaxForTests) return;
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
