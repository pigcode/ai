import 'dart:convert';
import 'dart:io';

import 'src/dart_tooling_compatibility_manifest.dart';

void main(List<String> arguments) {
  final root = Directory.current.absolute;
  if (arguments.length == 1 && arguments.single == '--write') {
    final output = File.fromUri(
      root.uri.resolve(dartToolingCompatibilityManifestPath),
    );
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(
        buildDartToolingCompatibilityManifest(),
      )}\n',
    );
  } else if (arguments.isNotEmpty) {
    throw ArgumentError('Use no arguments or --write.');
  }

  final violations = validateDartToolingCompatibilityManifest(root: root);
  if (violations.isNotEmpty) {
    for (final violation in violations) {
      stderr.writeln(violation);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Phase 2b Dart tooling compatibility evidence is valid.');
}
