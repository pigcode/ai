import 'dart:io';

import '../src/kernel_store_compatibility_manifest.dart';

void main() {
  final root = Directory.current.absolute;
  final manifest = loadKernelStoreCompatibilityManifest(root);
  final violations = validateKernelStoreFixtureCoverage(
    root: root,
    manifest: manifest,
  );
  if (violations.isNotEmpty) {
    for (final violation in violations) {
      stderr.writeln(violation);
    }
    exitCode = 1;
    return;
  }

  final claims =
      (manifest['claims']! as List<Object?>).cast<Map<String, Object?>>();
  final evidence =
      (manifest['evidence']! as List<Object?>).cast<Map<String, Object?>>();
  _expect(claims.length == 28, 'Expected exactly 28 claims.');
  _expect(evidence.length == 28, 'Expected exactly 28 evidence records.');
  _expect(
    evidence.where((item) => item['claimLevel'] == 'verified').length == 2,
    'Only the two real-process Store tuples may be verified.',
  );

  stdout.writeln('Phase 3 Kernel/Store fixture coverage is complete.');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
