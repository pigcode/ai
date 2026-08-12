import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_io/src/exec/process_cleanup_ledger.dart';
import 'package:test/test.dart';

void main() {
  test('production launcher fails closed without stable Host identity',
      () async {
    final launcher = SandboxedProcessLauncher(
      UnsafeDevSandboxBackend(),
    );
    await expectLater(
      launcher.launch(
        SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: Directory.current.absolute.path,
              access: SandboxPathAccess.readOnly,
            ),
          ],
        ),
        HostCommand(executable: '/usr/bin/true'),
      ),
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.rule,
          'rule',
          'stable-host-data-and-session-required',
        ),
      ),
    );
  });

  test(
    'production coordinator discovers and cleans a pending real process group',
    () async {
      final dataRoot = await Directory.systemTemp.createTemp('recovery-data-');
      final workspace =
          await Directory.systemTemp.createTemp('recovery-workspace-');
      const session = 'stable-recovery-session';
      final launcher = SandboxedProcessLauncher(
        SeatbeltSandboxBackend(),
        hostDataDirectory: dataRoot.path,
        sessionIdentity: session,
      );
      SandboxedProcess? process;
      try {
        process = await launcher.launch(
          SandboxPolicy(
            roots: <SandboxPathRule>[
              SandboxPathRule(
                path: workspace.path,
                access: SandboxPathAccess.readWrite,
              ),
            ],
          ),
          HostCommand(
              executable: '/bin/sleep', arguments: const <String>['30']),
        );
        final identity = ProcessGroup.captureIdentity(process.processGroupId);
        expect(identity, isNotNull);

        final coordinator = ProcessRecoveryCoordinator(dataRoot.path);
        final report = await coordinator
            .recoverPending()
            .timeout(const Duration(seconds: 10));

        expect(report.confirmed, isTrue);
        expect(report.results, hasLength(1));
        expect(report.results.single.status, ProcessRecoveryStatus.cleaned);
        expect(
          ProcessGroup.captureIdentity(process.processGroupId),
          isNull,
        );
        final ledger = ProcessCleanupLedger(
          coordinator.ledgerPathFor(session),
        );
        expect(await ledger.all(), isEmpty);
      } finally {
        if (process != null) process.kill(ProcessSignal.sigkill);
        await workspace.delete(recursive: true);
        await dataRoot.delete(recursive: true);
      }
    },
    skip: Platform.isMacOS
        ? false
        : 'SKIP-MANIFEST production recovery Seatbelt requires macOS',
  );

  test('coordinator retains identity mismatches without signaling', () async {
    final dataRoot =
        await Directory.systemTemp.createTemp('recovery-identity-');
    final process = await Process.start('/bin/sleep', const <String>['30']);
    final coordinator = ProcessRecoveryCoordinator(dataRoot.path);
    const session = 'identity-mismatch-session';
    final ledger = ProcessCleanupLedger(coordinator.ledgerPathFor(session));
    final record = ProcessCleanupRecord(
      sessionIdentity: session,
      processGroupId: process.pid,
      processIdentity: 'forged-identity',
    );
    try {
      await ledger.record(record);
      final report = await coordinator.recoverPending();
      expect(report.confirmed, isFalse);
      expect(
        report.results.single.status,
        ProcessRecoveryStatus.identityMismatch,
      );
      expect(ProcessGroup.captureIdentity(process.pid), isNotNull);
      expect(await ledger.all(), hasLength(1));
    } finally {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 5));
      await dataRoot.delete(recursive: true);
    }
  });
}
