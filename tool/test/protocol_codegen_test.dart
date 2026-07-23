import 'dart:io';

import '../src/protocol_codegen.dart';

void main() {
  final result = checkProtocolGeneratedOutputs(Directory.current);
  if (!result.isClean) {
    throw StateError(
      'Expected generated protocol outputs to be clean: '
      '${result.differences.join('; ')}',
    );
  }
  stdout.writeln('Protocol generated outputs are deterministic.');
}
