import 'dart:convert';
import 'dart:io';

import 'src/agent_store_crash_harness.dart';

Future<void> main(List<String> arguments) async {
  final scenarios = _selectScenarios(arguments);
  if (scenarios == null) {
    exitCode = 64;
    return;
  }
  final reports = await runAgentStoreCrashMatrix(scenarios);
  for (final report in reports) {
    stdout.writeln(jsonEncode(report.toJson()));
  }
  stdout.writeln(
    'PASS Agent Store SIGKILL matrix (${reports.length} scenarios)',
  );
}

List<String>? _selectScenarios(List<String> arguments) {
  if (arguments.length == 2 &&
      arguments[0] == '--suite' &&
      arguments[1] == 'all') {
    return agentStoreCrashScenarios;
  }
  if (arguments.length == 2 &&
      arguments[0] == '--scenario' &&
      agentStoreCrashScenarios.contains(arguments[1])) {
    return <String>[arguments[1]];
  }
  stderr.writeln(
    'usage: dart run tool/run_agent_store_crash_matrix.dart '
    '--suite all | --scenario <name>',
  );
  return null;
}
