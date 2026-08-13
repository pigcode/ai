import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _packageDirectories = <String>[
  'provider',
  'ai',
  'provider_utils',
  'openai',
  'openai_compatible',
  'anthropic',
  'protocol_utils',
  'acp',
  'mcp',
  'agent',
  'agent_kernel',
  'agent_io',
  'agent_dart',
  'lsp',
  'dap',
  'dart',
];

const _packageInactivityBudget = Duration(minutes: 2);
const _watchdogInterval = Duration(seconds: 1);

final class WorkspaceTestActivity {
  WorkspaceTestActivity({DateTime Function()? now})
      : _now = now ?? DateTime.now,
        _lastProgressAt = (now ?? DateTime.now)();

  final DateTime Function() _now;
  DateTime _lastProgressAt;

  void recordProgress() {
    _lastProgressAt = _now();
  }

  bool hasExpired(Duration budget) {
    return _now().difference(_lastProgressAt) >= budget;
  }
}

Map<String, Object?>? decodeWorkspaceTestEvent(
  String line,
  List<String> diagnostics,
) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
  } on FormatException {
    // `dart test` emits a plain-text status while handling termination.
  }
  diagnostics.add(line);
  return null;
}

Future<void> main() async {
  final root = Directory.current.absolute;
  final packageResults = <Map<String, Object?>>[];
  for (final package in _packageDirectories) {
    final directory = Directory.fromUri(
      root.uri.resolve('packages/$package/'),
    );
    if (!File.fromUri(directory.uri.resolve('pubspec.yaml')).existsSync() ||
        !Directory.fromUri(directory.uri.resolve('test/')).existsSync()) {
      stderr.writeln(
        'Workspace test package is incomplete: packages/$package.',
      );
      exitCode = 1;
      return;
    }

    stdout.writeln('==> packages/$package');
    final process = await Process.start(
      Platform.resolvedExecutable,
      const <String>['test', '--reporter=json', '--concurrency=1'],
      workingDirectory: directory.path,
    );
    final stderrOutput = process.stderr.transform(utf8.decoder).join();
    final activity = WorkspaceTestActivity();
    final diagnostics = <String>[];
    final testNames = <int, String>{};
    final activeTests = <int>{};
    final testErrors = <String>[];
    var passed = 0;
    var skipped = 0;
    var failed = 0;
    final skipReasons = <String>[];
    final skipReasonByTest = <int, String>{};
    final outputDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
      final event = decodeWorkspaceTestEvent(line, diagnostics);
      if (event == null) {
        return;
      }
      activity.recordProgress();
      if (event['type'] == 'testStart') {
        final test = event['test']! as Map<String, Object?>;
        final testId = test['id']! as int;
        testNames[testId] = test['name']! as String;
        activeTests.add(testId);
        final metadata = test['metadata']! as Map<String, Object?>;
        final reason = metadata['skipReason'];
        if (reason is String) {
          skipReasonByTest[testId] = reason;
        }
      }
      if (event['type'] == 'error' && event['testID'] is int) {
        final testId = event['testID']! as int;
        testErrors.add(
          '${testNames[testId] ?? 'test $testId'}: ${event['error']}',
        );
      }
      if (event['type'] == 'print' &&
          event['messageType'] == 'skip' &&
          event['testID'] is int &&
          event['message'] is String) {
        skipReasonByTest[event['testID']! as int] =
            (event['message']! as String).replaceFirst('Skip: ', '');
      }
      if (event['type'] == 'testDone') {
        activeTests.remove(event['testID']);
      }
      if (event['type'] == 'testDone' && event['hidden'] != true) {
        if (event['skipped'] == true) {
          skipped += 1;
          skipReasons.add(
            skipReasonByTest[event['testID']! as int] ??
                'missing skip reason for test ${event['testID']}',
          );
        } else if (event['result'] == 'success') {
          passed += 1;
        } else {
          failed += 1;
        }
      }
    });
    final inactivityTimeout = Completer<void>();
    final watchdog = Timer.periodic(_watchdogInterval, (_) {
      if (!inactivityTimeout.isCompleted &&
          activity.hasExpired(_packageInactivityBudget)) {
        inactivityTimeout.completeError(
          TimeoutException(
            'no structured test progress for $_packageInactivityBudget',
          ),
        );
      }
    });
    int result;
    try {
      result = await Future.any<int>(<Future<int>>[
        process.exitCode,
        inactivityTimeout.future.then<int>(
          (_) =>
              throw StateError('inactivity watchdog completed without error'),
        ),
      ]);
    } on TimeoutException {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      await outputDone;
      final errors = await stderrOutput;
      if (errors.isNotEmpty) {
        stderr.write(errors);
      }
      for (final error in testErrors) {
        stderr.writeln(error);
      }
      for (final line in diagnostics) {
        stderr.writeln(line);
      }
      final active = activeTests
          .map((testId) => testNames[testId] ?? 'test $testId')
          .join(', ');
      stderr.writeln(
        'Workspace test made no structured progress for '
        '$_packageInactivityBudget: packages/$package'
        '${active.isEmpty ? '.' : ' (active: $active).'}',
      );
      exitCode = 1;
      return;
    } finally {
      watchdog.cancel();
    }
    await outputDone;
    final errors = await stderrOutput;
    if (result != 0) {
      stderr.write(errors);
      for (final error in testErrors) {
        stderr.writeln(error);
      }
      for (final line in diagnostics) {
        stderr.writeln(line);
      }
      stderr.writeln(
        'Workspace test failed: packages/$package (exit $result).',
      );
      exitCode = result;
      return;
    }
    if (skipReasons.any((reason) => !reason.contains('SKIP-MANIFEST'))) {
      stderr.writeln(
        'Workspace test has an unclassified skip: packages/$package.',
      );
      exitCode = 1;
      return;
    }
    final status = skipped == 0 ? 'passed' : 'unsupported';
    packageResults.add(<String, Object?>{
      'package': package,
      'status': status,
      'passed': passed,
      'skipped': skipped,
      'failed': failed,
      'skipReasons': skipReasons,
    });
    stdout.writeln(
      '<== packages/$package status=$status '
      'passed=$passed skipped=$skipped failed=$failed',
    );
  }

  final artifact = File.fromUri(
    root.uri.resolve('.dart_tool/workspace-test-results.json'),
  );
  await artifact.parent.create(recursive: true);
  await artifact.writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'packages': packageResults,
      'passedPackages':
          packageResults.where((item) => item['status'] == 'passed').length,
      'unsupportedPackages': packageResults
          .where((item) => item['status'] == 'unsupported')
          .length,
      'skippedTests': packageResults.fold<int>(
        0,
        (sum, item) => sum + (item['skipped']! as int),
      ),
    }),
    flush: true,
  );
  final unsupported =
      packageResults.where((item) => item['status'] == 'unsupported').length;
  final skipped = packageResults.fold<int>(
    0,
    (sum, item) => sum + (item['skipped']! as int),
  );
  stdout.writeln(
    'Workspace tests complete: '
    '${_packageDirectories.length - unsupported} passed packages, '
    '$unsupported explicitly unsupported packages, $skipped skipped tests. '
    'Artifact: ${artifact.path}',
  );
}
