import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('native agent example requires and reports an explicit Session',
      () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        File('example/native_agent.dart').existsSync()
            ? 'example/native_agent.dart'
            : 'packages/agent/example/native_agent.dart',
      ],
      workingDirectory: Directory.current.absolute.path,
    ).timeout(const Duration(seconds: 15));

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('session=ses_'));
  });
}
