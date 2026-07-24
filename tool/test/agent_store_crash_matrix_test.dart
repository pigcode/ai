import 'dart:io';

import '../src/agent_store_crash_harness.dart';

Future<void> main() async {
  _expect(
    agentStoreCrashScenarios.length == 12,
    'Crash inventory must remain an explicit 12-scenario matrix.',
  );
  final reports = await runAgentStoreCrashMatrix(const <String>[
    'append-after-flush-before-receipt',
    'snapshot-after-flush',
    'compact-after-manifest',
  ]);
  _expect(reports.length == 3, 'Crash smoke matrix did not complete.');
  for (final report in reports) {
    _expect(
      report.artifactDigests.isNotEmpty,
      '${report.scenario} did not report artifact digests.',
    );
    _expect(
      report.rootDigest.length == 64 && report.sessionDigest.length == 64,
      '${report.scenario} did not recover stable heads.',
    );
  }
  stdout.writeln('PASS Agent Store SIGKILL smoke matrix');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
