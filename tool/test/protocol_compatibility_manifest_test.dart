import 'dart:convert';
import 'dart:io';

import '../src/protocol_compatibility_manifest.dart';

void main() {
  final root = Directory.current.absolute;
  final manifest = loadProtocolCompatibilityManifest(root);

  _test('accepts the pinned Phase 2a manifest', () {
    _expectNoViolations(
      validateProtocolCompatibilityManifest(root: root, manifest: manifest),
    );
  });

  _test('rejects a source reference outside the source lock', () {
    final changed = _copy(manifest);
    _claims(changed).first['sourceRefs'] = <Object?>['unknown-source'];

    _expectViolation(
      validateProtocolCompatibilityManifest(root: root, manifest: changed),
      'unknown_source_ref',
    );
  });

  _test('rejects one evidence record reused by multiple claims', () {
    final changed = _copy(manifest);
    final claims = _claims(changed);
    claims[1]['evidenceRefs'] = claims.first['evidenceRefs'];

    _expectViolation(
      validateProtocolCompatibilityManifest(root: root, manifest: changed),
      'reused_evidence_ref',
    );
  });

  _test('rejects an ACP conformant overclaim', () {
    final changed = _copy(manifest);
    _claim(changed, 'P2A-ACP-10')['level'] = 'conformant';
    _evidence(changed, 'P2A-ACP-10')['claimLevel'] = 'conformant';

    _expectViolation(
      validateProtocolCompatibilityManifest(root: root, manifest: changed),
      'acp_conformance_overclaim',
    );
  });

  _test('rejects verified claims backed only by a unit test', () {
    final changed = _copy(manifest);
    _claim(changed, 'P2A-UTIL-01')['level'] = 'verified';
    _evidence(changed, 'P2A-UTIL-01')['claimLevel'] = 'verified';

    _expectViolation(
      validateProtocolCompatibilityManifest(root: root, manifest: changed),
      'invalid_verified_evidence',
    );
  });

  _test('rejects an MCP stdio conformant overclaim', () {
    final changed = _copy(manifest);
    final official = _evidence(changed, 'P2A-MCP-14');
    final stdioClaim = _claim(changed, 'P2A-MCP-13');
    final stdioEvidence = _evidence(changed, 'P2A-MCP-13');
    stdioClaim['level'] = 'conformant';
    stdioEvidence
      ..['claimLevel'] = 'conformant'
      ..['kind'] = 'official-conformance'
      ..['result'] = _copyObject(
        official['result']! as Map<String, Object?>,
      );

    _expectViolation(
      validateProtocolCompatibilityManifest(root: root, manifest: changed),
      'mcp_stdio_conformance_overclaim',
    );
  });

  _test('rejects incomplete official conformance results', () {
    final changed = _copy(manifest);
    final report =
        _evidence(changed, 'P2A-MCP-14')['result']! as Map<String, Object?>;
    report['passed'] = 17;

    _expectViolation(
      validateProtocolCompatibilityManifest(root: root, manifest: changed),
      'invalid_official_conformance_report',
    );
  });

  _test('rejects stale evidence artifact digests', () {
    final changed = _copy(manifest);
    final artifact =
        _evidence(changed, 'P2A-UTIL-01')['artifact']! as Map<String, Object?>;
    artifact['sha256'] = List<String>.filled(64, '0').join();

    _expectViolation(
      validateProtocolCompatibilityManifest(root: root, manifest: changed),
      'evidence_artifact_hash_mismatch',
    );
  });

  _test('rejects evidence not bound to the expected commit state', () {
    final changed = _copy(manifest);
    _evidence(changed, 'P2A-UTIL-01')['evidenceCommit'] =
        '1111111111111111111111111111111111111111';

    _expectViolation(
      validateProtocolCompatibilityManifest(root: root, manifest: changed),
      'evidence_commit_mismatch',
    );
    _expectViolation(
      validateProtocolCompatibilityManifest(root: root, manifest: changed),
      'evidence_commit_unreachable',
    );
  });

  stdout.writeln('PASS Phase 2a protocol compatibility manifest');
}

Map<String, Object?> _copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value))! as Map<String, Object?>;

Map<String, Object?> _copyObject(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value))! as Map<String, Object?>;

List<Map<String, Object?>> _claims(Map<String, Object?> manifest) =>
    (manifest['claims']! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> _claim(
  Map<String, Object?> manifest,
  String claimId,
) =>
    _claims(manifest).singleWhere((claim) => claim['id'] == claimId);

Map<String, Object?> _evidence(
  Map<String, Object?> manifest,
  String claimId,
) =>
    (manifest['evidence']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((evidence) => evidence['claimId'] == claimId);

void _expectNoViolations(List<ProtocolCompatibilityViolation> violations) {
  if (violations.isNotEmpty) {
    throw StateError(violations.join('\n'));
  }
}

void _expectViolation(
  List<ProtocolCompatibilityViolation> violations,
  String code,
) {
  if (!violations.any((violation) => violation.code == code)) {
    throw StateError(
      'Expected $code, found ${violations.map((value) => value.code).toList()}',
    );
  }
}

void _test(String name, void Function() body) {
  try {
    body();
    stdout.writeln('PASS $name');
  } on Object catch (error, stackTrace) {
    stderr
      ..writeln('FAIL $name: $error')
      ..writeln(stackTrace);
    exitCode = 1;
  }
}
