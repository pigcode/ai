import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('fixed Dart ACP peer passes over a real stdio process', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      const <String>['run', 'tool/test/acp_cross_process_test.dart'],
      workingDirectory: '../..',
    ).timeout(const Duration(seconds: 30));

    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(result.stdout, contains('PASS ACP Dart real process'));
  });
}
