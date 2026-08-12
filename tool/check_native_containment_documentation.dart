import 'dart:io';

import 'src/native_containment_compatibility_manifest.dart';
import 'src/native_containment_documentation.dart';

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln(
      'Usage: dart run tool/check_native_containment_documentation.dart',
    );
    exitCode = 64;
    return;
  }
  final root = Directory.current.absolute;
  final violations = validateNativeContainmentPublicDocumentation(
    root: root,
    manifest: loadNativeContainmentCompatibilityManifest(root),
  );
  if (violations.isEmpty) {
    stdout.writeln('Phase 4 public documentation is manifest-consistent.');
    return;
  }
  for (final violation in violations) {
    stderr.writeln(violation);
  }
  exitCode = 1;
}
