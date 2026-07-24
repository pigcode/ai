import 'dart:io';

import 'src/agent_kernel_schema.dart';

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/check_agent_kernel_schema.dart');
    exitCode = 64;
    return;
  }

  final violations = validateAgentKernelSchemaAssets(Directory.current)
    ..sort((left, right) {
      final codeOrder = left.code.compareTo(right.code);
      return codeOrder != 0 ? codeOrder : left.message.compareTo(right.message);
    });
  if (violations.isEmpty) {
    stdout.writeln('Agent Kernel persisted schemas are valid.');
    return;
  }
  for (final violation in violations) {
    stderr.writeln(violation);
  }
  exitCode = 1;
}
