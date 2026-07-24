import 'dart:convert';
import 'dart:io';

import '../src/dart_tooling_compatibility_manifest.dart';

void main() {
  final root = Directory.current.absolute;
  final manifest = loadDartToolingCompatibilityManifest(root);
  final schema = jsonDecode(
    File(dartToolingCompatibilitySchemaPath).readAsStringSync(),
  ) as Map<String, Object?>;
  final properties = schema['properties']! as Map<String, Object?>;
  final claimsSchema = properties['claims']! as Map<String, Object?>;
  _expect(
    schema['additionalProperties'] == false &&
        claimsSchema['minItems'] == 41 &&
        claimsSchema['maxItems'] == 41,
    'Schema must close the top level and fix the 41-claim inventory.',
  );
  final violations = validateDartToolingCompatibilityManifest(
    root: root,
    manifest: manifest,
  );
  if (violations.isNotEmpty) {
    throw StateError(violations.join('\n'));
  }
  final claims =
      (manifest['claims']! as List<Object?>).cast<Map<String, Object?>>();
  final evidence =
      (manifest['evidence']! as List<Object?>).cast<Map<String, Object?>>();
  _expect(claims.length == 41, 'Expected exactly 41 claims.');
  _expect(evidence.length == 41, 'Expected one evidence item per claim.');
  _expect(
    claims.every((claim) => claim['level'] != 'conformant'),
    'Phase 2b has no official conformance claim.',
  );
  _expect(
    claims.where((claim) => claim['protocol'] == 'dtd').every(
          (claim) =>
              claim['runtimeVersionPolicy'] ==
              'no-wire-version-exact-sdk-inventory',
        ),
    'DTD must not claim a fabricated wire version.',
  );

  final skipped = _copy(manifest);
  final skippedEvidence =
      (skipped['evidence']! as List<Object?>).first as Map<String, Object?>;
  skippedEvidence['result'] = 'skipped';
  _expect(
    _codes(root, skipped).contains('evidence_not_passed'),
    'Skipped evidence must not satisfy a claim.',
  );

  final oneFamily = _copy(manifest);
  final overlapEvidence = (oneFamily['evidence']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .singleWhere((item) => item['claimId'] == 'P2B-LSP-08');
  overlapEvidence['peerProfileRefs'] = <Object?>[
    'lsp-dart-minimum',
    'lsp-dart-current',
  ];
  _expect(
    _codes(root, oneFamily).contains('overlap_peer_family_undercoverage'),
    'General LSP overlap needs two independent peer families.',
  );

  final dtdVersion = _copy(manifest);
  final dtdPeer = (dtdVersion['peerProfiles']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .singleWhere((item) => item['id'] == 'dtd-minimum');
  dtdPeer['observedProtocol'] = 'invented';
  _expect(
    _codes(root, dtdVersion).contains('dtd_wire_version_overclaim'),
    'DTD evidence must reject a fabricated wire version.',
  );
  stdout.writeln('Phase 2b Dart tooling compatibility manifest is valid.');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Map<String, Object?> _copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

Set<String> _codes(Directory root, Map<String, Object?> manifest) => {
      for (final violation in validateDartToolingCompatibilityManifest(
        root: root,
        manifest: manifest,
      ))
        violation.code,
    };
