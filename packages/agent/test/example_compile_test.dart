import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('native agent example requires and reports an explicit Session',
      () async {
    final result = await _runNativeAgentExample();

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.sessionMarker, isNotNull, reason: result.stdout);
  }, timeout: Timeout(_exampleTestBudget));
}

const _exampleRunBudget = Duration(minutes: 1);
const _exampleCleanupBudget = Duration(seconds: 10);
const _exampleTestBudget = Duration(seconds: 90);
const _diagnosticLimit = 64 * 1024;

final class _NativeAgentExampleResult {
  const _NativeAgentExampleResult({
    required this.exitCode,
    required this.sessionMarker,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String? sessionMarker;
  final String stdout;
  final String stderr;
}

final class _NativeAgentExampleTimeout implements Exception {
  const _NativeAgentExampleTimeout({
    required this.stage,
    required this.processId,
    required this.stdout,
    required this.stderr,
  });

  final String stage;
  final int processId;
  final String stdout;
  final String stderr;

  @override
  String toString() => 'NativeAgentExampleTimeout('
      'stage=$stage, pid=$processId, runBudget=$_exampleRunBudget, '
      'stdout=${jsonEncode(stdout)}, stderr=${jsonEncode(stderr)})';
}

Future<_NativeAgentExampleResult> _runNativeAgentExample() async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    <String>[
      File('example/native_agent.dart').existsSync()
          ? 'example/native_agent.dart'
          : 'packages/agent/example/native_agent.dart',
    ],
    workingDirectory: Directory.current.absolute.path,
    runInShell: false,
  );
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  String? sessionMarker;
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
    _appendBounded(stdout, '$line\n');
    if (line.contains('session=ses_')) sessionMarker ??= line;
  });
  final stderrDone = process.stderr.transform(utf8.decoder).forEach(
        (chunk) => _appendBounded(stderr, chunk),
      );
  final exit = process.exitCode;
  final completed = Future.wait<void>(<Future<void>>[
    stdoutDone,
    stderrDone,
    exit.then<void>((_) {}),
  ]);

  try {
    await completed.timeout(
      _exampleRunBudget,
      onTimeout: () => throw _NativeAgentExampleTimeout(
        stage: sessionMarker == null
            ? 'await-session-marker'
            : 'await-normal-process-exit',
        processId: process.pid,
        stdout: stdout.toString(),
        stderr: stderr.toString(),
      ),
    );
  } on _NativeAgentExampleTimeout {
    process.kill(ProcessSignal.sigkill);
    await exit.timeout(
      _exampleCleanupBudget,
      onTimeout: () => throw _NativeAgentExampleTimeout(
        stage: 'await-sigkill-process-exit',
        processId: process.pid,
        stdout: stdout.toString(),
        stderr: stderr.toString(),
      ),
    );
    rethrow;
  }

  return _NativeAgentExampleResult(
    exitCode: await exit,
    sessionMarker: sessionMarker,
    stdout: stdout.toString(),
    stderr: stderr.toString(),
  );
}

void _appendBounded(StringBuffer buffer, String value) {
  final remaining = _diagnosticLimit - buffer.length;
  if (remaining <= 0) return;
  buffer
      .write(value.length <= remaining ? value : value.substring(0, remaining));
}
