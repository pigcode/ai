import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import 'package:pigcode_ai_agent_io/src/sandbox/sandbox_startup_handshake.dart';
import '../support/workspace_path.dart';

void main() {
  for (final mode in const <String>['pre-handshake-exit', 'sigkill', 'flood']) {
    test('P4-TM-PROC-04 $mode has a bounded restart budget', () async {
      final root = await Directory.systemTemp.createTemp('restart-seatbelt-');
      var attempts = 0;
      final budget = RestartBudget(
        maxAttempts: 3,
        initialBackoff: Duration.zero,
      );
      try {
        await expectLater(
          budget.run<void>((attempt) async {
            attempts += 1;
            final backend = SeatbeltSandboxBackend(
              startupObserver: mode == 'pre-handshake-exit'
                  ? (phase, _) async {
                      if (phase ==
                          SandboxStartupPhase.processGroupPersistedBeforeAck) {
                        throw const HostCapabilityException(
                          HostCapabilityError.sandboxUnavailable,
                          'fixture-pre-handshake-exit',
                        );
                      }
                    }
                  : null,
            );
            expect(backend.probe().productionReady, isTrue);
            final launcher = SandboxedProcessLauncher.unsafeDev(
              backend,
              cleanupLedgerPath: '${root.path}/ledger-$attempt.json',
              sessionIdentity: 'restart-$mode-$attempt',
            );
            SandboxedProcess? process;
            try {
              process = await launcher.launch(
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
                      packageRelative:
                          'test/fixtures/restart_failure_fixture.dart',
                      workspaceRelative: 'packages/agent_io/test/fixtures/'
                          'restart_failure_fixture.dart',
                    ),
                    mode,
                  ],
                ),
              );
              final outputDone = process.stdout.drain<void>();
              final errorsDone = process.stderr.drain<void>();
              final code = await process.exitCode.timeout(
                const Duration(seconds: 4),
              );
              await Future.wait<void>(<Future<void>>[outputDone, errorsDone]);
              throw RestartableProcessException(code);
            } on HostCapabilityException {
              throw const RestartableProcessException(70);
            } finally {
              if (process != null) {
                await launcher.cleanup(process).timeout(
                      const Duration(seconds: 3),
                    );
              }
            }
          }),
          throwsA(isA<RestartableProcessException>()),
        );
        expect(attempts, 3);
      } finally {
        await root.delete(recursive: true);
      }
    }, skip: _seatbeltSkip);
  }
}

final Object _seatbeltSkip = Platform.isMacOS
    ? false
    : 'SKIP-MANIFEST PROC-04 platform=${Platform.operatingSystem} '
        'backend=seatbelt-required';
