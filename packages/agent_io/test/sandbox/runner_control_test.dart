import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/src/sandbox/sandbox_startup_handshake.dart';
import 'package:test/test.dart';

import '../support/workspace_path.dart';

void main() {
  test('target exec replaces the runner without changing PID', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        resolveTestWorkspacePath(
          packageRelative: 'test/fixtures/exec_replacement_fixture.dart',
          workspaceRelative:
              'packages/agent_io/test/fixtures/exec_replacement_fixture.dart',
        ),
      ],
    ).timeout(const Duration(seconds: 15));

    expect(result.exitCode, 23);
    final lines = const LineSplitter().convert(result.stdout as String);
    final control = lines.singleWhere(
      (line) => line.startsWith(sandboxControlPrefix),
    );
    final message = jsonDecode(
      control.substring(sandboxControlPrefix.length),
    ) as Map<String, Object?>;
    final target = lines.singleWhere((line) => line.startsWith('TARGET_PID='));

    expect(message['type'], 'exec-ready');
    expect(int.parse(target.substring('TARGET_PID='.length)), message['pid']);
  });
}
