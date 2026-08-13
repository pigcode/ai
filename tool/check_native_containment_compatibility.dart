import 'dart:io';

import 'src/native_containment_compatibility_manifest.dart';

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln(
      'Usage: dart run tool/check_native_containment_compatibility.dart',
    );
    exitCode = 64;
    return;
  }
  final violations = validateNativeContainmentCompatibilityManifest(
    root: Directory.current.absolute,
  )..sort((left, right) {
      final code = left.code.compareTo(right.code);
      return code != 0 ? code : left.message.compareTo(right.message);
    });
  if (violations.isEmpty) {
    stdout.writeln('Phase 4 native containment manifest is valid.');
    return;
  }
  for (final violation in violations) {
    stderr.writeln(violation);
  }
  exitCode = 1;
}
