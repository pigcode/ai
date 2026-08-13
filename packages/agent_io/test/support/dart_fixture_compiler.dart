import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _compileDeadline = Duration(seconds: 30);
const _terminationDeadline = Duration(seconds: 2);

Future<File> compileDartFixture({
  required String sourcePath,
  required Directory outputDirectory,
  required String outputName,
}) async {
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(outputName)) {
    throw ArgumentError.value(outputName, 'outputName', 'unsafe output name');
  }
  outputDirectory.createSync(recursive: true);
  final executable = File.fromUri(outputDirectory.uri.resolve(outputName));
  final process = await Process.start(
    Platform.resolvedExecutable,
    <String>[
      'compile',
      'exe',
      sourcePath,
      '-o',
      executable.path,
    ],
    runInShell: false,
  );
  final output = utf8.decoder.bind(process.stdout).join();
  final errors = utf8.decoder.bind(process.stderr).join();

  late int exitCode;
  try {
    exitCode = await process.exitCode.timeout(_compileDeadline);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(_terminationDeadline);
    } on TimeoutException {
      // The compile deadline remains authoritative even if reap is delayed.
    }
    throw TimeoutException(
      'Dart fixture compile exceeded $_compileDeadline for $sourcePath\n'
      'stdout:\n${await _boundedOutput(output)}\n'
      'stderr:\n${await _boundedOutput(errors)}',
      _compileDeadline,
    );
  }

  final stdoutText = await output;
  final stderrText = await errors;
  if (exitCode != 0) {
    throw StateError(
      'Dart fixture compile failed for $sourcePath with exit $exitCode\n'
      'stdout:\n$stdoutText\n'
      'stderr:\n$stderrText',
    );
  }
  if (!executable.existsSync()) {
    throw StateError(
      'Dart fixture compile produced no executable for $sourcePath\n'
      'stdout:\n$stdoutText\n'
      'stderr:\n$stderrText',
    );
  }
  return executable;
}

Future<String> _boundedOutput(Future<String> output) => output.timeout(
      _terminationDeadline,
      onTimeout: () => '<output unavailable after compiler termination>',
    );
