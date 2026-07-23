import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _harnessVersion = '0.1.16';
const _specVersion = '2025-11-25';
const _inventoryPath =
    'tool/upstream/protocols/mcp-conformance/v0.1.16/scenarios.json';
const _harnessPath = 'tool/conformance/mcp/node_modules/.bin/conformance';

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final root = Directory.current.absolute;
    final inventory = jsonDecode(
      File('${root.path}/$_inventoryPath').readAsStringSync(),
    ) as Map<String, Object?>;
    final available =
        (inventory[options.role]! as List<Object?>).cast<String>();
    final scenarios =
        options.scenario == null ? available : <String>[options.scenario!];
    if (!scenarios.every(available.contains)) {
      throw FormatException(
        'Unknown ${options.role} scenario: ${options.scenario}.',
      );
    }
    final harness = File('${root.path}/$_harnessPath');
    if (!harness.existsSync()) {
      throw StateError(
        'Pinned MCP conformance harness is not installed. Run '
        '`npm ci --prefix tool/conformance/mcp --ignore-scripts`.',
      );
    }
    final output = Directory(
      options.outputDirectory ??
          '${root.path}/.dart_tool/mcp_conformance/${options.role}',
    )..createSync(recursive: true);
    Process? server;
    String? serverUrl;
    try {
      if (options.role == 'server') {
        final started = await _startServer(root.path);
        server = started.process;
        serverUrl = started.url;
      }
      final passed = <String>[];
      final failed = <String>[];
      for (final scenario in scenarios) {
        stdout.writeln(
          'MCP conformance ${options.role} scenario: $scenario',
        );
        final scenarioOutput = Directory(
          '${output.path}/${scenario.replaceAll('/', '__')}',
        )..createSync(recursive: true);
        final harnessArguments = <String>[
          options.role,
          if (options.role == 'client') ...<String>[
            '--command',
            '${Platform.resolvedExecutable} run '
                'tool/fixtures/mcp_conformance_client.dart',
          ] else ...<String>[
            '--url',
            serverUrl!,
          ],
          '--scenario',
          scenario,
          '--spec-version',
          _specVersion,
          '--output-dir',
          scenarioOutput.path,
        ];
        final result = await _runProcess(
          harness.path,
          harnessArguments,
          workingDirectory: root.path,
          timeout: const Duration(seconds: 60),
        );
        File('${scenarioOutput.path}/harness.stdout.txt')
            .writeAsStringSync(result.stdout);
        File('${scenarioOutput.path}/harness.stderr.txt')
            .writeAsStringSync(result.stderr);
        stdout.write(result.stdout);
        stderr.write(result.stderr);
        if (result.exitCode == 0) {
          passed.add(scenario);
        } else {
          failed.add(scenario);
        }
      }
      final reportWithoutDigest = <String, Object?>{
        'formatVersion': 1,
        'harness': <String, Object?>{
          'package': '@modelcontextprotocol/conformance',
          'version': _harnessVersion,
        },
        'role': options.role,
        'specVersion': _specVersion,
        'selection': options.scenario == null
            ? <String, Object?>{'suite': 'all'}
            : <String, Object?>{'scenario': options.scenario},
        'applicable': List<String>.unmodifiable(scenarios),
        'passed': passed,
        'failed': failed,
        'skipped': const <String>[],
        'expectedFailures': const <String>[],
        'counts': <String, Object?>{
          'applicable': scenarios.length,
          'passed': passed.length,
          'failed': failed.length,
          'skipped': 0,
        },
      };
      final canonical = jsonEncode(reportWithoutDigest);
      final report = <String, Object?>{
        ...reportWithoutDigest,
        'digest': 'sha256:${sha256.convert(utf8.encode(canonical))}',
      };
      File('${output.path}/report.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      if (failed.isNotEmpty) {
        stderr.writeln(
          'FAIL MCP ${options.role}: ${passed.length}/${scenarios.length} '
          'passed; report ${output.path}/report.json',
        );
        exitCode = 1;
      } else {
        stdout.writeln(
          'PASS MCP ${options.role}: ${passed.length}/${scenarios.length} '
          'passed; report ${output.path}/report.json',
        );
      }
    } finally {
      server?.kill(ProcessSignal.sigterm);
      if (server != null) {
        await server.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            server!.kill(ProcessSignal.sigkill);
            return server.exitCode;
          },
        );
      }
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_Options.usage);
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('MCP conformance runner failed: $error');
    exitCode = 1;
  }
}

final class _Options {
  const _Options({
    required this.role,
    required this.scenario,
    required this.outputDirectory,
  });

  static const usage = 'Usage: dart run tool/run_mcp_conformance.dart '
      '--role client|server (--scenario <name>|--suite all) '
      '[--spec-version 2025-11-25] [--output-dir <path>]';

  final String role;
  final String? scenario;
  final String? outputDirectory;

  static _Options parse(List<String> arguments) {
    if (arguments.any(
      (argument) =>
          argument == '--expected-failures' ||
          argument.startsWith('--expected-failures='),
    )) {
      throw const FormatException(
        'Expected-failure baselines are forbidden by this runner.',
      );
    }
    String? role;
    String? scenario;
    String? suite;
    String? specVersion;
    String? outputDirectory;
    for (var index = 0; index < arguments.length; index += 1) {
      final option = arguments[index];
      if (!const <String>{
        '--role',
        '--scenario',
        '--suite',
        '--spec-version',
        '--output-dir',
      }.contains(option)) {
        throw FormatException('Unknown option: $option.');
      }
      if (index + 1 >= arguments.length) {
        throw FormatException('Missing value for $option.');
      }
      final value = arguments[++index];
      switch (option) {
        case '--role':
          role = value;
        case '--scenario':
          scenario = value;
        case '--suite':
          suite = value;
        case '--spec-version':
          specVersion = value;
        case '--output-dir':
          outputDirectory = value;
      }
    }
    if (!const <String>{'client', 'server'}.contains(role)) {
      throw const FormatException('--role must be client or server.');
    }
    if ((scenario == null) == (suite == null)) {
      throw const FormatException(
        'Select exactly one of --scenario or --suite.',
      );
    }
    if (suite != null && suite != 'all') {
      throw const FormatException('Only --suite all is supported.');
    }
    if (specVersion != null && specVersion != _specVersion) {
      throw const FormatException(
        'Only MCP spec version 2025-11-25 is supported.',
      );
    }
    return _Options(
      role: role!,
      scenario: scenario,
      outputDirectory: outputDirectory,
    );
  }
}

final class _StartedServer {
  const _StartedServer(this.process, this.url);

  final Process process;
  final String url;
}

Future<_StartedServer> _startServer(String root) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    const <String>['run', 'tool/fixtures/mcp_conformance_server.dart'],
    workingDirectory: root,
  );
  final firstLine = Completer<String>();
  final stderrBuffer = StringBuffer();
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    if (!firstLine.isCompleted) {
      firstLine.complete(line);
    } else {
      stdout.writeln(line);
    }
  });
  process.stderr.transform(utf8.decoder).listen((chunk) {
    stderrBuffer.write(chunk);
    stderr.write(chunk);
  });
  final line = await Future.any<String>(<Future<String>>[
    firstLine.future,
    process.exitCode.then(
      (code) => throw StateError(
        'MCP server fixture exited with $code before readiness: '
        '$stderrBuffer',
      ),
    ),
  ]).timeout(const Duration(seconds: 15));
  final url = Uri.tryParse(line);
  if (url == null || !url.hasScheme) {
    process.kill();
    throw StateError('MCP server fixture emitted an invalid URL: $line');
  }
  return _StartedServer(process, line);
}

final class _ProcessResult {
  const _ProcessResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<_ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Duration timeout,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  int code;
  try {
    code = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    code = 124;
  }
  return _ProcessResult(
    code,
    await stdoutFuture,
    await stderrFuture,
  );
}
