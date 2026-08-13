import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import 'package:pigcode_ai_agent_io/src/exec/process_cleanup_ledger.dart';
import '../support/workspace_path.dart';

void main() {
  group('production Seatbelt process boundaries', () {
    test('invalid target is rejected before launch returns and group is clean',
        () async {
      final root = await Directory.systemTemp.createTemp('exec-failure-');
      final ledgerPath = '${root.path}/ledger.json';
      final launcher = SandboxedProcessLauncher.unsafeDev(
        SeatbeltSandboxBackend(),
        cleanupLedgerPath: ledgerPath,
        sessionIdentity: 'exec-failure-session',
      );
      try {
        await expectLater(
          launcher.launch(
            SandboxPolicy(
              roots: <SandboxPathRule>[
                SandboxPathRule(
                  path: root.path,
                  access: SandboxPathAccess.readWrite,
                ),
              ],
            ),
            HostCommand(executable: '${root.path}/missing-executable'),
          ),
          throwsA(
            isA<HostCapabilityException>().having(
              (error) => error.rule,
              'rule',
              'sandbox-target-exec-failed',
            ),
          ),
        );
        expect(
          await ProcessCleanupLedger(ledgerPath)
              .pending('exec-failure-session'),
          isEmpty,
        );
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('P4-TM-PROC-01 cleanup terminates the full background process group',
        () async {
      final launcher =
          SandboxedProcessLauncher.unsafeDev(SeatbeltSandboxBackend());
      final process = await launcher.launch(
        SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: Directory.current.path,
              access: SandboxPathAccess.readOnly,
            ),
          ],
        ),
        HostCommand(
          executable: Platform.resolvedExecutable,
          arguments: <String>[
            resolveTestWorkspacePath(
              packageRelative: 'test/fixtures/process_tree_fixture.dart',
              workspaceRelative:
                  'packages/agent_io/test/fixtures/process_tree_fixture.dart',
            ),
          ],
        ),
      );
      final lines = StreamIterator<String>(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      try {
        expect(
            await lines.moveNext().timeout(const Duration(seconds: 5)), isTrue);
        expect(lines.current, startsWith('READY '));
        process.stdin.writeln('spawn');
        expect(
            await lines.moveNext().timeout(const Duration(seconds: 5)), isTrue);
        final childPid = int.parse(lines.current.split(' ').last);
        expect(ProcessGroup.captureIdentity(childPid), isNotNull);

        final report =
            await launcher.cleanup(process).timeout(const Duration(seconds: 5));

        expect(report.confirmed, isTrue);
        expect(
          await _waitUntilGone(childPid, const Duration(seconds: 2)),
          isTrue,
        );
        expect(ProcessGroup.captureIdentity(childPid), isNull);
        expect((await launcher.cleanup(process)).confirmed, isTrue);
      } finally {
        await lines.cancel();
        if (await _stillRunning(process.pid)) {
          process.kill(ProcessSignal.sigkill);
        }
      }
    });

    test('P4-TM-PROC-01 cleanup kills group survivors after the leader exits',
        () async {
      final launcher =
          SandboxedProcessLauncher.unsafeDev(SeatbeltSandboxBackend());
      final process = await launcher.launch(
        SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: Directory.current.path,
              access: SandboxPathAccess.readOnly,
            ),
          ],
        ),
        HostCommand(
          executable: Platform.resolvedExecutable,
          arguments: <String>[
            resolveTestWorkspacePath(
              packageRelative: 'test/fixtures/process_tree_fixture.dart',
              workspaceRelative:
                  'packages/agent_io/test/fixtures/process_tree_fixture.dart',
            ),
          ],
        ),
      );
      final lines = StreamIterator<String>(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      var childPid = -1;
      try {
        expect(
            await lines.moveNext().timeout(const Duration(seconds: 5)), isTrue);
        expect(lines.current, startsWith('READY '));
        process.stdin.writeln('spawn-exit');
        expect(
            await lines.moveNext().timeout(const Duration(seconds: 5)), isTrue);
        childPid = int.parse(lines.current.split(' ').last);
        expect(ProcessGroup.captureIdentity(childPid), isNotNull);

        // The target and its wrapper exit while the lingering child stays
        // alive inside the original process group.
        await process.exitCode.timeout(const Duration(seconds: 5));
        expect(
          await _waitUntilGone(process.pid, const Duration(seconds: 2)),
          isTrue,
        );
        expect(ProcessGroup.captureIdentity(childPid), isNotNull);

        final report =
            await launcher.cleanup(process).timeout(const Duration(seconds: 5));

        expect(report.confirmed, isTrue);
        // Confirming cleanup requires the surviving group member to be gone,
        // not merely the exited group leader.
        expect(
          await _waitUntilGone(childPid, const Duration(seconds: 2)),
          isTrue,
        );
        expect(ProcessGroup.captureIdentity(childPid), isNull);
      } finally {
        await lines.cancel();
        if (childPid > 0 && await _stillRunning(childPid)) {
          Process.killPid(childPid, ProcessSignal.sigkill);
        }
        if (await _stillRunning(process.pid)) {
          process.kill(ProcessSignal.sigkill);
        }
      }
    });

    test('durable cleanup ledger blocks restarted launchers and PTY brokers',
        () async {
      final root = await Directory.systemTemp.createTemp('cleanup-ledger-');
      final ledgerPath = '${root.path}/ledger.json';
      final first = SandboxedProcessLauncher.unsafeDev(
        SeatbeltSandboxBackend(),
        cleanupLedgerPath: ledgerPath,
        sessionIdentity: 'ses-cleanup-test',
      );
      final policy = SandboxPolicy(
        roots: <SandboxPathRule>[
          SandboxPathRule(
            path: Directory.current.path,
            access: SandboxPathAccess.readOnly,
          ),
        ],
      );
      final process = await first.launch(
        policy,
        HostCommand(
          executable: Platform.resolvedExecutable,
          arguments: <String>[
            resolveTestWorkspacePath(
              packageRelative: 'test/fixtures/process_tree_fixture.dart',
              workspaceRelative:
                  'packages/agent_io/test/fixtures/process_tree_fixture.dart',
            ),
            '--linger',
          ],
        ),
      );
      final restarted = SandboxedProcessLauncher.unsafeDev(
        SeatbeltSandboxBackend(),
        cleanupLedgerPath: ledgerPath,
        sessionIdentity: 'ses-cleanup-test',
      );
      try {
        await expectLater(
          restarted.launchBroker(
            HostCommand(executable: '/usr/bin/false'),
            SeatbeltSandboxBackend().probe(),
          ),
          throwsA(
            isA<HostCapabilityException>().having(
              (error) => error.code,
              'code',
              HostCapabilityError.processCleanupFailed,
            ),
          ),
        );
      } finally {
        await first.cleanup(process);
        await root.delete(recursive: true);
      }
    });

    test('P4-TM-PROC-01 cleanup terminates a true setsid descendant', () async {
      final root = await Directory.systemTemp.createTemp('detached-cleanup-');
      final launcher = SandboxedProcessLauncher.unsafeDev(
        SeatbeltSandboxBackend(),
        cleanupLedgerPath: '${root.path}/ledger.json',
        sessionIdentity: 'ses-detached-test',
      );
      final process = await launcher.launch(
        SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: Directory.current.path,
              access: SandboxPathAccess.readOnly,
            ),
          ],
        ),
        HostCommand(
          executable: Platform.resolvedExecutable,
          arguments: <String>[
            resolveTestWorkspacePath(
              packageRelative: 'test/fixtures/process_tree_fixture.dart',
              workspaceRelative:
                  'packages/agent_io/test/fixtures/process_tree_fixture.dart',
            ),
          ],
        ),
      );
      final lines = StreamIterator<String>(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      var detachedPid = -1;
      try {
        expect(
            await lines.moveNext().timeout(const Duration(seconds: 5)), isTrue);
        process.stdin.writeln('spawn-detached');
        expect(
            await lines.moveNext().timeout(const Duration(seconds: 5)), isTrue);
        detachedPid = int.parse(lines.current.split(' ').last);
        expect(ProcessGroup.captureIdentity(detachedPid), isNotNull);

        expect((await launcher.cleanup(process)).confirmed, isTrue);
        expect(
          await _waitUntilGone(detachedPid, const Duration(seconds: 2)),
          isTrue,
        );
        expect(ProcessGroup.captureIdentity(detachedPid), isNull);
      } finally {
        await lines.cancel();
        if (detachedPid > 0 && await _stillRunning(detachedPid)) {
          Process.killPid(detachedPid, ProcessSignal.sigkill);
        }
        await root.delete(recursive: true);
      }
    });

    test('recovery refuses a reused PGID with the wrong process identity',
        () async {
      final root = await Directory.systemTemp.createTemp('identity-guard-');
      final ledgerPath = '${root.path}/ledger.json';
      final launcher = SandboxedProcessLauncher.unsafeDev(
        SeatbeltSandboxBackend(),
        cleanupLedgerPath: ledgerPath,
        sessionIdentity: 'ses-identity-test',
      );
      final process = await launcher.launch(
        SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: Directory.current.path,
              access: SandboxPathAccess.readOnly,
            ),
          ],
        ),
        HostCommand(
          executable: Platform.resolvedExecutable,
          arguments: <String>[
            resolveTestWorkspacePath(
              packageRelative: 'test/fixtures/process_tree_fixture.dart',
              workspaceRelative:
                  'packages/agent_io/test/fixtures/process_tree_fixture.dart',
            ),
            '--linger',
          ],
        ),
      );
      final ledger = ProcessCleanupLedger(ledgerPath);
      final forged = ProcessCleanupRecord(
        sessionIdentity: 'ses-identity-test',
        processGroupId: process.pid,
        processIdentity: 'reused-pgid',
      );
      await ledger.record(forged);
      final restarted = SandboxedProcessLauncher.unsafeDev(
        SeatbeltSandboxBackend(),
        cleanupLedgerPath: ledgerPath,
        sessionIdentity: 'ses-identity-test',
      );
      try {
        await expectLater(
          restarted.cleanupRecorded(process.pid),
          throwsA(
            isA<HostCapabilityException>().having(
              (error) => error.rule,
              'rule',
              'recorded-process-identity-mismatch',
            ),
          ),
        );
        expect(await _stillRunning(process.pid), isTrue);
      } finally {
        await launcher.cleanup(process);
        await ledger.confirm(forged);
        await root.delete(recursive: true);
      }
    });
  }, skip: _seatbeltSkip);
}

final Object _seatbeltSkip = Platform.isMacOS
    ? false
    : 'SKIP-MANIFEST PROC-01 platform=${Platform.operatingSystem} '
        'backend=seatbelt-required';

Future<bool> _stillRunning(int pid) async =>
    Process.killPid(pid, ProcessSignal.sigcont);

Future<bool> _waitUntilGone(int pid, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (await _stillRunning(pid)) {
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return true;
}
