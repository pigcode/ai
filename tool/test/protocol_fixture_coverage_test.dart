import 'dart:io';

import '../src/protocol_compatibility_manifest.dart';

void main() {
  final root = Directory.current.absolute;
  final manifest = loadProtocolCompatibilityManifest(root);
  final violations = validateProtocolFixtureCoverage(
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
  final clientReport =
      evidence.singleWhere((item) => item['claimId'] == 'P2A-MCP-14')['result']!
          as Map<String, Object?>;
  final serverReport =
      evidence.singleWhere((item) => item['claimId'] == 'P2A-MCP-15')['result']!
          as Map<String, Object?>;

  _expect(claims.length == 34, 'Expected 34 approved fixture claims.');
  _expect(evidence.length == 34, 'Expected one evidence record per claim.');
  _expect(
    _sameList(
      (clientReport['scenarios']! as List<Object?>).cast<String>(),
      phase2aMcpClientScenarios,
    ),
    'Client conformance scenario inventory differs.',
  );
  _expect(
    _sameList(
      (serverReport['scenarios']! as List<Object?>).cast<String>(),
      phase2aMcpServerScenarios,
    ),
    'Server conformance scenario inventory differs.',
  );

  stdout.writeln('Phase 2a protocol fixture coverage is complete.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

bool _sameList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
