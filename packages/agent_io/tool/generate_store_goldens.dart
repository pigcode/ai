import 'dart:io';

import '../test/store/store_test_support.dart';

void main() {
  final output = File(
    'test/fixtures/store/segment-v1.bin',
  );
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(testSealedSegment(), flush: true);
  stdout.writeln(
    'Wrote ${output.path} (${output.lengthSync()} bytes).',
  );
}
