import 'dart:io';

import 'src/protocol_codegen.dart';

void main(List<String> arguments) {
  final root = Directory.current;
  if (arguments.isEmpty) {
    writeProtocolGeneratedOutputs(root);
    stdout.writeln('Generated protocol source and tooling inventories.');
    return;
  }
  if (arguments.length == 1 && arguments.single == '--check') {
    final result = checkProtocolGeneratedOutputs(root);
    if (!result.isClean) {
      for (final difference in result.differences) {
        stderr.writeln(difference);
      }
      exitCode = 1;
      return;
    }
    stdout.writeln('Protocol generated outputs are clean.');
    return;
  }
  stderr.writeln('Usage: dart run tool/protocol_codegen.dart [--check]');
  exitCode = 64;
}
