import 'package:test/test.dart';

import '../example/session_run.dart' as example;

void main() {
  test('Kernel in-memory lifecycle example executes terminal replay', () async {
    await example.main();
  });
}
