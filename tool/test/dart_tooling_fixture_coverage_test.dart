import 'dart:io';

import '../src/dart_tooling_compatibility_manifest.dart';

void main() {
  final root = Directory.current.absolute;
  final manifest = loadDartToolingCompatibilityManifest(root);
  final violations = validateDartToolingFixtureCoverage(
    root: root,
    manifest: manifest,
  );
  if (violations.isNotEmpty) {
    throw StateError(violations.join('\n'));
  }
  final claims =
      (manifest['claims']! as List<Object?>).cast<Map<String, Object?>>();
  final verified = claims.where((claim) => claim['level'] == 'verified');
  _expect(verified.isNotEmpty, 'Expected real-process verified claims.');
  _expect(
    File('packages/lsp/example/portable_client.dart').existsSync() &&
        File('packages/dap/example/portable_client.dart').existsSync() &&
        File('packages/dart/example/tooling_clients.dart').existsSync(),
    'All three packages require public API examples.',
  );
  stdout.writeln('Phase 2b Dart tooling fixture coverage is complete.');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
