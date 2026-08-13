import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Dart tooling example probes, executes, and confirms cleanup', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        File('example/dart_tooling_agent.dart').existsSync()
            ? 'example/dart_tooling_agent.dart'
            : 'packages/agent_dart/example/dart_tooling_agent.dart',
      ],
      workingDirectory: Directory.current.absolute.path,
    ).timeout(const Duration(seconds: 20));

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('cleanup=confirmed'));
  });
}
