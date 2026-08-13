import 'dart:convert';
import 'dart:io';

import 'src/agent_sandbox_crash_harness.dart';

Future<void> main(List<String> arguments) async {
  final scenarios = _select(arguments);
  if (scenarios == null) {
    exitCode = 64;
    return;
  }
  final reports = await runAgentSandboxCrashMatrix(scenarios);
  for (final report in reports) {
    stdout.writeln(jsonEncode(report.toJson()));
  }
  stdout.writeln(
    'PASS Agent sandbox SIGKILL matrix (${reports.length} scenarios)',
  );
}

List<String>? _select(List<String> arguments) {
  if (arguments.length == 2 &&
      arguments[0] == '--suite' &&
      arguments[1] == 'all') {
    return agentSandboxCrashScenarios;
  }
  if (arguments.length == 2 &&
      arguments[0] == '--scenario' &&
      agentSandboxCrashScenarios.contains(arguments[1])) {
    return <String>[arguments[1]];
  }
  stderr.writeln(
    'usage: dart run tool/run_agent_sandbox_crash_matrix.dart '
    '--suite all | --scenario <name>',
  );
  return null;
}
