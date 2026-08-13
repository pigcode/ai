import 'dart:async';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import 'package:pigcode_ai_agent_io/src/exec/process_cleanup_ledger.dart';
import 'package:pigcode_ai_agent_io/src/sandbox/sandbox_startup_handshake.dart';
import '../support/workspace_path.dart';

void main() {
  test('start remains pending until sandbox-ready ACK completes', () async {
    final root = await Directory.systemTemp.createTemp('handshake-ready-');
    final ledger = ProcessCleanupLedger('${root.path}/ledger.json');
    final process = await _startFixture('ready');
    final sandboxReadyBeforeAck = Completer<void>();
    final releaseSandboxReadyAck = Completer<void>();
    var completed = false;
    final startup = awaitSandboxStartup(
      process,
      observer: (phase, evidence) async {
        if (phase != SandboxStartupPhase.sandboxAppliedBeforeExecAck) return;
        expect(evidence['type'], 'sandbox-ready');
        sandboxReadyBeforeAck.complete();
        await releaseSandboxReadyAck.future;
      },
      persistProcessGroup: (processGroupId) async {
        final record = _record(processGroupId, 'ses-ready');
        await ledger.record(record);
        return record;
      },
    ).whenComplete(() => completed = true);
    unawaited(
      startup.then<void>(
        (_) {
          if (!sandboxReadyBeforeAck.isCompleted) {
            sandboxReadyBeforeAck.completeError(
              StateError('startup completed before sandbox-ready barrier'),
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!sandboxReadyBeforeAck.isCompleted) {
            sandboxReadyBeforeAck.completeError(error, stackTrace);
          }
        },
      ),
    );
    try {
      await sandboxReadyBeforeAck.future;
      expect(completed, isFalse);
      releaseSandboxReadyAck.complete();
      await startup.timeout(const Duration(seconds: 3));
      expect(completed, isTrue);
      expect(await process.exitCode.timeout(const Duration(seconds: 3)), 0);
    } finally {
      if (!releaseSandboxReadyAck.isCompleted) {
        releaseSandboxReadyAck.complete();
      }
      if (await _running(process.pid)) process.kill(ProcessSignal.sigkill);
      await root.delete(recursive: true);
    }
  });

  test('ACK-before-ready crash leaves a recoverable durable record', () async {
    final root = await Directory.systemTemp.createTemp('handshake-crash-');
    final ledgerPath = '${root.path}/ledger.json';
    final ledger = ProcessCleanupLedger(ledgerPath);
    final process = await _startFixture('crash-before-ready');
    try {
      await expectLater(
        awaitSandboxStartup(
          process,
          persistProcessGroup: (processGroupId) async {
            final record = _record(processGroupId, 'ses-crash');
            await ledger.record(record);
            return record;
          },
        ),
        throwsA(
          isA<HostCapabilityException>().having(
            (error) => error.code,
            'code',
            HostCapabilityError.sandboxUnavailable,
          ),
        ),
      );
      expect((await ledger.pending('ses-crash')).single.processGroupId,
          process.pid);

      final launcher = SandboxedProcessLauncher.unsafeDev(
        UnsafeDevSandboxBackend(),
        cleanupLedgerPath: ledgerPath,
        sessionIdentity: 'ses-crash',
      );
      expect((await launcher.cleanupRecorded(process.pid)).confirmed, isTrue);
      expect(await ledger.pending('ses-crash'), isEmpty);
    } finally {
      if (await _running(process.pid)) process.kill(ProcessSignal.sigkill);
      await root.delete(recursive: true);
    }
  });

  test('group identity mismatch fails before write-ahead ACK', () async {
    final root = await Directory.systemTemp.createTemp('handshake-identity-');
    final ledger = ProcessCleanupLedger('${root.path}/ledger.json');
    final process = await _startFixture('identity-mismatch');
    try {
      await expectLater(
        awaitSandboxStartup(
          process,
          persistProcessGroup: (processGroupId) async {
            final record = _record(processGroupId, 'ses-identity');
            await ledger.record(record);
            return record;
          },
        ),
        throwsA(
          isA<HostCapabilityException>()
              .having(
                (error) => error.code,
                'code',
                HostCapabilityError.processCleanupFailed,
              )
              .having(
                (error) => error.rule,
                'rule',
                'sandbox-group-handshake-invalid',
              ),
        ),
      );
      expect(await ledger.pending('ses-identity'), isEmpty);
    } finally {
      if (await _running(process.pid)) process.kill(ProcessSignal.sigkill);
      await root.delete(recursive: true);
    }
  });

  test('sandbox establishment error is surfaced as typed start failure',
      () async {
    final root = await Directory.systemTemp.createTemp('handshake-error-');
    final ledger = ProcessCleanupLedger('${root.path}/ledger.json');
    final process = await _startFixture('setup-error');
    try {
      await expectLater(
        awaitSandboxStartup(
          process,
          persistProcessGroup: (processGroupId) async {
            final record = _record(processGroupId, 'ses-error');
            await ledger.record(record);
            return record;
          },
        ),
        throwsA(
          isA<HostCapabilityException>()
              .having(
                (error) => error.code,
                'code',
                HostCapabilityError.capabilityBelowMinimum,
              )
              .having(
                (error) => error.rule,
                'rule',
                'fixture-sandbox-apply-failed',
              ),
        ),
      );
    } finally {
      if (await _running(process.pid)) process.kill(ProcessSignal.sigkill);
      await root.delete(recursive: true);
    }
  });

  test('sandbox ACK consumption without exec confirmation is typed', () async {
    final root = await Directory.systemTemp.createTemp('handshake-exec-');
    final ledger = ProcessCleanupLedger('${root.path}/ledger.json');
    final process = await _startFixture('ack-consumed-no-exec');
    try {
      await expectLater(
        awaitSandboxStartup(
          process,
          persistProcessGroup: (processGroupId) async {
            final record = _record(processGroupId, 'ses-no-exec');
            await ledger.record(record);
            return record;
          },
        ),
        throwsA(
          isA<HostCapabilityException>().having(
            (error) => error.rule,
            'rule',
            'sandbox-exited-before-exec-ready',
          ),
        ),
      );
      expect(await ledger.pending('ses-no-exec'), hasLength(1));
    } finally {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 3));
      await root.delete(recursive: true);
    }
  });
}

Future<Process> _startFixture(String mode) => Process.start(
      Platform.resolvedExecutable,
      <String>[
        resolveTestWorkspacePath(
          packageRelative: 'test/fixtures/sandbox_handshake_fixture.dart',
          workspaceRelative:
              'packages/agent_io/test/fixtures/sandbox_handshake_fixture.dart',
        ),
        mode,
      ],
      runInShell: false,
    );

ProcessCleanupRecord _record(int processGroupId, String sessionIdentity) {
  final identity = ProcessGroup.captureIdentity(processGroupId);
  if (identity == null) throw StateError('missing process identity');
  return ProcessCleanupRecord(
    sessionIdentity: sessionIdentity,
    processGroupId: processGroupId,
    processIdentity: identity,
  );
}

Future<bool> _running(int processId) async =>
    Process.killPid(processId, ProcessSignal.sigcont);
