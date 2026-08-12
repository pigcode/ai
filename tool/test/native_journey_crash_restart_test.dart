import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import '../src/agent_sandbox_crash_harness.dart';

Future<void> main() async {
  final report = await runAgentSandboxCrashScenario('effect-mid-execution');
  _expect(report.cleanupConfirmed, 'restart cleanup was not confirmed');
  _expect(!report.residualProcess, 'SIGKILL journey leaked a process');
  _expect(!report.outcomeReplayed, 'unknown outcome was replayed');
  _expect(!report.falseRestrictedClaim, 'containment was overclaimed');
  _expect(
    report.storeArtifactState['outcome'] == 'unknown',
    'crash artifact did not preserve unknown outcome',
  );
  final recovery = ReconciliationPlan.failClosed(
    ReconciliationTrigger.lostResponse,
  );
  _expect(!recovery.retryExternalEffect, 'recovery retried an external effect');
  _expect(!recovery.replayPrompt, 'recovery replayed the model prompt');

  final capability = Platform.isMacOS
      ? SeatbeltSandboxBackend().probe()
      : LandlockSeccompSandboxBackend().probe();
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'evidence': <String, Object?>{
        'os': Platform.operatingSystem,
        'kernel': Platform.operatingSystemVersion,
        'arch': capability.platform.name,
        'landlockAbi': capability.landlockAbi,
      },
      'recovery': 'reconciling/interrupted',
      'scenario': report.toJson(),
    }),
  );
  stdout.writeln('PASS Native journey crash/restart');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
