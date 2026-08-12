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
      const <String>['test', '--reporter=json'],
      workingDirectory: directory.path,
    );
    final stderrOutput = process.stderr.transform(utf8.decoder).join();
    var passed = 0;
    var skipped = 0;
    var failed = 0;
    final skipReasons = <String>[];
    final skipReasonByTest = <int, String>{};
    final outputDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
      final event = jsonDecode(line) as Map<String, Object?>;
      if (event['type'] == 'testStart') {
        final test = event['test']! as Map<String, Object?>;
        final metadata = test['metadata']! as Map<String, Object?>;
        final reason = metadata['skipReason'];
        if (reason is String) {
          skipReasonByTest[test['id']! as int] = reason;
        }
      }
      if (event['type'] == 'print' &&
          event['messageType'] == 'skip' &&
          event['testID'] is int &&
          event['message'] is String) {
        skipReasonByTest[event['testID']! as int] =
            (event['message']! as String).replaceFirst('Skip: ', '');
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
    int result;
    try {
      result = await process.exitCode.timeout(const Duration(minutes: 2));
    } on TimeoutException {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      stderr.writeln('Workspace test timed out: packages/$package.');
      exitCode = 1;
      return;
    }
    await outputDone;
    final errors = await stderrOutput;
    if (result != 0) {
      stderr.write(errors);
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
