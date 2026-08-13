import 'dart:io';

import 'package:pigcode_ai_agent_io/src/sandbox/runner_control.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty && arguments.first == '--target') {
    stdout.writeln('TARGET_PID=$pid');
    exit(23);
  }
  exitCode = await RunnerControl.replaceWithTarget(
    Platform.resolvedExecutable,
    <String>[Platform.script.toFilePath(), '--target'],
  );
}
