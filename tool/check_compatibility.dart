import 'dart:io';

import 'src/compatibility_manifest.dart';

void main(List<String> arguments) {
  final root = Directory.current.absolute;
  if (arguments.length == 1 && arguments.single == '--fixture-coverage-only') {
    _finish(
      validateFixtureCoverage(root),
      successMessage: 'AI Core fixture coverage is complete.',
    );
    return;
  }

  var manifestPath = 'compatibility/vercel-ai-7.0.35.json';
  var schemaPath = 'compatibility/schema/ai-core-compatibility.schema.json';
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (argument != '--manifest' && argument != '--schema') {
      _usage('Unknown argument: $argument');
    }
    if (index + 1 >= arguments.length) {
      _usage('Missing value for $argument');
    }
    final value = arguments[index + 1];
    if (argument == '--manifest') {
      manifestPath = value;
    } else {
      schemaPath = value;
    }
    index += 1;
  }

  _finish(
    validateCompatibilityManifest(
      root: root,
      manifestFile: File.fromUri(root.uri.resolve(manifestPath)),
      schemaFile: File.fromUri(root.uri.resolve(schemaPath)),
    ),
    successMessage: 'AI Core compatibility manifest is valid.',
  );
}

void _finish(
  List<CompatibilityViolation> violations, {
  required String successMessage,
}) {
  violations.sort((left, right) {
    final codeComparison = left.code.compareTo(right.code);
    return codeComparison != 0
        ? codeComparison
        : left.message.compareTo(right.message);
  });
  if (violations.isEmpty) {
    stdout.writeln(successMessage);
    return;
  }
  for (final violation in violations) {
    stderr.writeln(violation);
  }
  exitCode = 1;
}

Never _usage(String message) {
  stderr
    ..writeln(message)
    ..writeln(
      'Usage: dart run tool/check_compatibility.dart '
      '[--manifest PATH] [--schema PATH]',
    )
    ..writeln(
      '   or: dart run tool/check_compatibility.dart '
      '--fixture-coverage-only',
    );
  exit(64);
}
