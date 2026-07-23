import 'dart:io';

import 'src/protocol_compatibility_manifest.dart';

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln(
      'Usage: dart run tool/check_protocol_compatibility.dart',
    );
    exitCode = 64;
    return;
  }
  final root = Directory.current.absolute;
  final violations = <ProtocolCompatibilityViolation>[
    ...validateProtocolCompatibilityManifest(root: root),
    ...validateProtocolFixtureCoverage(root: root),
  ]..sort((left, right) {
      final codeComparison = left.code.compareTo(right.code);
      return codeComparison != 0
          ? codeComparison
          : left.message.compareTo(right.message);
    });
  if (violations.isEmpty) {
    stdout.writeln('Phase 2a protocol compatibility manifest is valid.');
    return;
  }
  for (final violation in violations) {
    stderr.writeln(violation);
  }
  exitCode = 1;
}
