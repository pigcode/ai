import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'protocol_sources.dart';

const protocolCompatibilityManifestPath =
    'compatibility/phase-2a-protocol-foundation.json';
const protocolCompatibilitySchemaPath =
    'compatibility/schema/protocol-foundation-compatibility.schema.json';

// The implementation PR must use this sentinel. Task 26 replaces it with the
// completion PR's main-bound squash merge commit.
const phase2aProtocolEvidenceCommit = 'pending-main-merge';

const phase2aProtocolFixtureIds = <String>{
  'P2A-UTIL-01',
  'P2A-UTIL-02',
  'P2A-UTIL-03',
  'P2A-ACP-01',
  'P2A-ACP-02',
  'P2A-ACP-03',
  'P2A-ACP-04',
  'P2A-ACP-05',
  'P2A-ACP-06',
  'P2A-ACP-07',
  'P2A-ACP-08',
  'P2A-ACP-09',
  'P2A-ACP-10',
  'P2A-MCP-01',
  'P2A-MCP-02',
  'P2A-MCP-03',
  'P2A-MCP-04',
  'P2A-MCP-05',
  'P2A-MCP-06',
  'P2A-MCP-07',
  'P2A-MCP-08',
  'P2A-MCP-09',
  'P2A-MCP-10',
  'P2A-MCP-11',
  'P2A-MCP-12',
  'P2A-MCP-13',
  'P2A-MCP-14',
  'P2A-MCP-15',
  'P2A-MCP-16',
  'P2A-CROSS-01',
  'P2A-CROSS-02',
  'P2A-CROSS-03',
  'P2A-CROSS-04',
  'P2A-CROSS-05',
};

const phase2aMcpClientScenarios = <String>[
  'initialize',
  'tools_call',
  'elicitation-sep1034-client-defaults',
  'sse-retry',
  'auth/metadata-default',
  'auth/metadata-var1',
  'auth/metadata-var2',
  'auth/metadata-var3',
  'auth/basic-cimd',
  'auth/scope-from-www-authenticate',
  'auth/scope-from-scopes-supported',
  'auth/scope-omitted-when-undefined',
  'auth/scope-step-up',
  'auth/scope-retry-limit',
  'auth/token-endpoint-auth-basic',
  'auth/token-endpoint-auth-post',
  'auth/token-endpoint-auth-none',
  'auth/pre-registration',
];

const phase2aMcpServerScenarios = <String>[
  'server-initialize',
  'logging-set-level',
  'ping',
  'completion-complete',
  'tools-list',
  'tools-call-simple-text',
  'tools-call-image',
  'tools-call-audio',
  'tools-call-embedded-resource',
  'tools-call-mixed-content',
  'tools-call-with-logging',
  'tools-call-error',
  'tools-call-with-progress',
  'tools-call-sampling',
  'tools-call-elicitation',
  'json-schema-2020-12',
  'elicitation-sep1034-defaults',
  'server-sse-polling',
  'server-sse-multiple-streams',
  'elicitation-sep1330-enums',
  'resources-list',
  'resources-read-text',
  'resources-read-binary',
  'resources-templates-read',
  'resources-subscribe',
  'resources-unsubscribe',
  'prompts-list',
  'prompts-get-simple',
  'prompts-get-with-args',
  'prompts-get-embedded-resource',
  'prompts-get-with-image',
  'dns-rebinding-protection',
];

final class ProtocolCompatibilityViolation {
  const ProtocolCompatibilityViolation(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

Map<String, Object?> loadProtocolCompatibilityManifest(
  Directory root, {
  String path = protocolCompatibilityManifestPath,
}) {
  final decoded = jsonDecode(_containedFile(root, path).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'Protocol compatibility manifest must be a JSON object.',
    );
  }
  return decoded;
}

List<ProtocolCompatibilityViolation> validateProtocolCompatibilityManifest({
  required Directory root,
  Map<String, Object?>? manifest,
}) {
  try {
    return _validateManifest(
      root.absolute,
      manifest ?? loadProtocolCompatibilityManifest(root),
    );
  } on Object catch (error) {
    return <ProtocolCompatibilityViolation>[
      ProtocolCompatibilityViolation('invalid_manifest', error.toString()),
    ];
  }
}

List<ProtocolCompatibilityViolation> validateProtocolFixtureCoverage({
  required Directory root,
  Map<String, Object?>? manifest,
}) {
  try {
    final document = manifest ?? loadProtocolCompatibilityManifest(root);
    final claims = _objectList(document['claims'], 'claims');
    final evidence = _objectList(document['evidence'], 'evidence');
    final violations = <ProtocolCompatibilityViolation>[];
    final claimIds = <String>{
      for (var index = 0; index < claims.length; index += 1)
        _string(claims[index]['id'], 'claims[$index].id'),
    };
    if (!_sameSet(claimIds, phase2aProtocolFixtureIds)) {
      violations.add(
        ProtocolCompatibilityViolation(
          'fixture_id_coverage_mismatch',
          'Expected fixture IDs $phase2aProtocolFixtureIds, found $claimIds.',
        ),
      );
    }

    final evidenceByClaim = <String, int>{};
    for (var index = 0; index < evidence.length; index += 1) {
      final claimId = _string(
        evidence[index]['claimId'],
        'evidence[$index].claimId',
      );
      evidenceByClaim.update(claimId, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final claimId in phase2aProtocolFixtureIds) {
      if (evidenceByClaim[claimId] != 1) {
        violations.add(
          ProtocolCompatibilityViolation(
            'fixture_evidence_cardinality',
            '$claimId must have exactly one dedicated evidence record.',
          ),
        );
      }
    }
    return violations;
  } on Object catch (error) {
    return <ProtocolCompatibilityViolation>[
      ProtocolCompatibilityViolation(
        'invalid_fixture_coverage',
        error.toString(),
      ),
    ];
  }
}

List<ProtocolCompatibilityViolation> _validateManifest(
  Directory root,
  Map<String, Object?> manifest,
) {
  final violations = <ProtocolCompatibilityViolation>[];
  _expectExactKeys(
    manifest,
    const <String>{
      r'$schema',
      'formatVersion',
      'phase',
      'implementationCommit',
      'dartSdkConstraint',
      'sources',
      'claims',
      'evidence',
      'knownUnsupported',
    },
    'manifest',
  );
  if (manifest[r'$schema'] !=
      './schema/protocol-foundation-compatibility.schema.json') {
    violations.add(
      const ProtocolCompatibilityViolation(
        'invalid_schema_reference',
        'Manifest must reference the pinned protocol compatibility schema.',
      ),
    );
  }
  if (manifest['formatVersion'] != 1 ||
      manifest['phase'] != 'phase-2a-protocol-foundation' ||
      manifest['dartSdkConstraint'] != '^3.6.0') {
    violations.add(
      const ProtocolCompatibilityViolation(
        'invalid_manifest_identity',
        'Expected Phase 2a format 1 with Dart SDK constraint ^3.6.0.',
      ),
    );
  }
  final implementationCommit = _string(
    manifest['implementationCommit'],
    'implementationCommit',
  );
  if (implementationCommit != phase2aProtocolEvidenceCommit) {
    violations.add(
      ProtocolCompatibilityViolation(
        'implementation_commit_mismatch',
        'Expected $phase2aProtocolEvidenceCommit, found $implementationCommit.',
      ),
    );
  }

  final sourceLock = loadProtocolSourceLock(root);
  final lockedSources = <String, ProtocolSource>{
    for (final source in sourceLock.sources) source.sourceId: source,
  };
  final sources = _objectList(manifest['sources'], 'sources');
  final manifestSourceIds = <String>{};
  for (var index = 0; index < sources.length; index += 1) {
    final location = 'sources[$index]';
    final source = sources[index];
    _expectExactKeys(
      source,
      const <String>{
        'sourceId',
        'release',
        'revision',
        'wireVersion',
        'artifactRefs',
      },
      location,
    );
    final sourceId = _string(source['sourceId'], '$location.sourceId');
    if (!manifestSourceIds.add(sourceId)) {
      violations.add(
        ProtocolCompatibilityViolation(
          'duplicate_source_ref',
          'Duplicate source record $sourceId.',
        ),
      );
      continue;
    }
    final locked = lockedSources[sourceId];
    if (locked == null) {
      violations.add(
        ProtocolCompatibilityViolation(
          'unknown_source_ref',
          '$location references unknown source $sourceId.',
        ),
      );
      continue;
    }
    final artifactRefs = _stringSet(
      source['artifactRefs'],
      '$location.artifactRefs',
    );
    final lockedArtifactRefs = <String>{
      for (final artifact in locked.artifacts) artifact.artifactId,
    };
    if (source['release'] != locked.release ||
        source['revision'] != locked.revision ||
        source['wireVersion'] != locked.wireVersion ||
        !_sameSet(artifactRefs, lockedArtifactRefs)) {
      violations.add(
        ProtocolCompatibilityViolation(
          'source_lock_mismatch',
          '$sourceId does not exactly match the protocol source lock.',
        ),
      );
    }
  }
  if (!_sameSet(manifestSourceIds, lockedSources.keys.toSet())) {
    violations.add(
      const ProtocolCompatibilityViolation(
        'source_coverage_mismatch',
        'Manifest sources must exactly cover the protocol source lock.',
      ),
    );
  }

  final unsupported = _objectList(
    manifest['knownUnsupported'],
    'knownUnsupported',
  );
  final unsupportedIds = <String>{};
  for (var index = 0; index < unsupported.length; index += 1) {
    final location = 'knownUnsupported[$index]';
    final item = unsupported[index];
    _expectExactKeys(
      item,
      const <String>{'id', 'scope', 'summary'},
      location,
    );
    final id = _string(item['id'], '$location.id');
    if (!unsupportedIds.add(id)) {
      violations.add(
        ProtocolCompatibilityViolation(
          'duplicate_known_unsupported',
          'Duplicate knownUnsupported ID $id.',
        ),
      );
    }
    _string(item['scope'], '$location.scope');
    _string(item['summary'], '$location.summary');
  }

  final claims = _objectList(manifest['claims'], 'claims');
  final claimsById = <String, Map<String, Object?>>{};
  final referencedSources = <String>{};
  final referencedEvidence = <String>{};
  final referencedUnsupported = <String>{};
  for (var index = 0; index < claims.length; index += 1) {
    final location = 'claims[$index]';
    final claim = claims[index];
    _expectExactKeys(
      claim,
      const <String>{
        'id',
        'protocol',
        'level',
        'summary',
        'sourceRefs',
        'evidenceRefs',
        'knownUnsupportedRefs',
      },
      location,
    );
    final id = _string(claim['id'], '$location.id');
    if (claimsById.containsKey(id)) {
      violations.add(
        ProtocolCompatibilityViolation(
          'duplicate_claim_id',
          'Duplicate claim ID $id.',
        ),
      );
    }
    claimsById[id] = claim;
    final protocol = _string(claim['protocol'], '$location.protocol');
    final level = _string(claim['level'], '$location.level');
    if (!const <String>{
      'protocol-utils',
      'acp',
      'mcp',
      'cross-package',
    }.contains(protocol)) {
      violations.add(
        ProtocolCompatibilityViolation(
          'invalid_claim_protocol',
          '$id has unsupported protocol $protocol.',
        ),
      );
    }
    if (!const <String>{
      'implemented',
      'verified',
      'conformant',
    }.contains(level)) {
      violations.add(
        ProtocolCompatibilityViolation(
          'invalid_claim_level',
          '$id has unsupported claim level $level.',
        ),
      );
    }
    if (protocol == 'acp' && level == 'conformant') {
      violations.add(
        ProtocolCompatibilityViolation(
          'acp_conformance_overclaim',
          '$id cannot be conformant because ACP has no official harness.',
        ),
      );
    }
    _string(claim['summary'], '$location.summary');
    final sourceRefs = _stringSet(
      claim['sourceRefs'],
      '$location.sourceRefs',
    );
    if (sourceRefs.isEmpty) {
      violations.add(
        ProtocolCompatibilityViolation(
          'missing_claim_source',
          '$id must reference at least one source.',
        ),
      );
    }
    for (final sourceRef in sourceRefs) {
      referencedSources.add(sourceRef);
      if (!manifestSourceIds.contains(sourceRef)) {
        violations.add(
          ProtocolCompatibilityViolation(
            'unknown_source_ref',
            '$id references unknown source $sourceRef.',
          ),
        );
      }
    }
    final evidenceRefs = _stringSet(
      claim['evidenceRefs'],
      '$location.evidenceRefs',
    );
    if (evidenceRefs.length != 1) {
      violations.add(
        ProtocolCompatibilityViolation(
          'claim_evidence_cardinality',
          '$id must reference exactly one dedicated evidence record.',
        ),
      );
    }
    for (final evidenceRef in evidenceRefs) {
      if (!referencedEvidence.add(evidenceRef)) {
        violations.add(
          ProtocolCompatibilityViolation(
            'reused_evidence_ref',
            'Evidence $evidenceRef is referenced by more than one claim.',
          ),
        );
      }
    }
    for (final unsupportedRef in _stringSet(
      claim['knownUnsupportedRefs'],
      '$location.knownUnsupportedRefs',
    )) {
      referencedUnsupported.add(unsupportedRef);
      if (!unsupportedIds.contains(unsupportedRef)) {
        violations.add(
          ProtocolCompatibilityViolation(
            'unknown_known_unsupported_ref',
            '$id references unknown limitation $unsupportedRef.',
          ),
        );
      }
    }
  }
  if (!_sameSet(claimsById.keys.toSet(), phase2aProtocolFixtureIds)) {
    violations.add(
      const ProtocolCompatibilityViolation(
        'claim_coverage_mismatch',
        'Manifest claim IDs must exactly cover the approved P2A fixture IDs.',
      ),
    );
  }
  if (!_sameSet(referencedSources, manifestSourceIds)) {
    violations.add(
      const ProtocolCompatibilityViolation(
        'unreferenced_source',
        'Every manifest source must be referenced by at least one claim.',
      ),
    );
  }
  if (!_sameSet(referencedUnsupported, unsupportedIds)) {
    violations.add(
      const ProtocolCompatibilityViolation(
        'known_unsupported_reference_closure',
        'Every knownUnsupported record must be referenced by a claim.',
      ),
    );
  }

  final evidence = _objectList(manifest['evidence'], 'evidence');
  final evidenceIds = <String>{};
  for (var index = 0; index < evidence.length; index += 1) {
    final location = 'evidence[$index]';
    final item = evidence[index];
    _expectExactKeys(
      item,
      const <String>{
        'id',
        'claimId',
        'claimLevel',
        'kind',
        'role',
        'transport',
        'version',
        'capabilityProfile',
        'platform',
        'peer',
        'dartSdkConstraint',
        'evidenceCommit',
        'artifact',
        'verifiedAt',
        'result',
      },
      location,
    );
    final id = _string(item['id'], '$location.id');
    if (!evidenceIds.add(id)) {
      violations.add(
        ProtocolCompatibilityViolation(
          'duplicate_evidence_id',
          'Duplicate evidence ID $id.',
        ),
      );
    }
    final claimId = _string(item['claimId'], '$location.claimId');
    if (id != 'EV-$claimId') {
      violations.add(
        ProtocolCompatibilityViolation(
          'evidence_id_mismatch',
          '$id must use the dedicated ID EV-$claimId.',
        ),
      );
    }
    final claim = claimsById[claimId];
    if (claim == null) {
      violations.add(
        ProtocolCompatibilityViolation(
          'unknown_evidence_claim',
          '$id references unknown claim $claimId.',
        ),
      );
      continue;
    }
    final claimLevel = _string(
      item['claimLevel'],
      '$location.claimLevel',
    );
    if (claimLevel != claim['level']) {
      violations.add(
        ProtocolCompatibilityViolation(
          'claim_level_mismatch',
          '$id level $claimLevel differs from $claimId level ${claim['level']}.',
        ),
      );
    }
    for (final field in const <String>[
      'kind',
      'role',
      'transport',
      'version',
      'capabilityProfile',
      'platform',
    ]) {
      _string(item[field], '$location.$field');
    }
    if (item['dartSdkConstraint'] != '^3.6.0') {
      violations.add(
        ProtocolCompatibilityViolation(
          'dart_sdk_constraint_mismatch',
          '$id must use Dart SDK constraint ^3.6.0.',
        ),
      );
    }
    final evidenceCommit = _string(
      item['evidenceCommit'],
      '$location.evidenceCommit',
    );
    if (evidenceCommit != implementationCommit ||
        evidenceCommit != phase2aProtocolEvidenceCommit) {
      violations.add(
        ProtocolCompatibilityViolation(
          'evidence_commit_mismatch',
          '$id must bind to $phase2aProtocolEvidenceCommit.',
        ),
      );
    }
    final verifiedAt = DateTime.tryParse(
      _string(item['verifiedAt'], '$location.verifiedAt'),
    );
    if (verifiedAt == null || !verifiedAt.isUtc) {
      violations.add(
        ProtocolCompatibilityViolation(
          'invalid_verified_at',
          '$id verifiedAt must be an ISO-8601 UTC timestamp.',
        ),
      );
    }
    _validateDigest(
      root,
      _object(item['peer'], '$location.peer'),
      '$location.peer',
      violations,
    );
    _validateDigest(
      root,
      _object(item['artifact'], '$location.artifact'),
      '$location.artifact',
      violations,
    );
    final result = _object(item['result'], '$location.result');
    final protocol = claim['protocol']! as String;
    final transport = item['transport']! as String;
    final kind = item['kind']! as String;
    if (claimLevel == 'verified' &&
        !const <String>{
          'scripted-peer',
          'real-process',
          'full-gate',
        }.contains(kind)) {
      violations.add(
        ProtocolCompatibilityViolation(
          'invalid_verified_evidence',
          '$id verified evidence must use a fixed peer or full gate.',
        ),
      );
    }
    if (claimLevel == 'conformant') {
      final hasOfficialTuple = protocol == 'mcp' &&
          transport == 'streamable-http' &&
          kind == 'official-conformance';
      if (!hasOfficialTuple) {
        violations.add(
          ProtocolCompatibilityViolation(
            'invalid_conformant_evidence',
            '$id conformant evidence must be MCP Streamable HTTP official '
                'conformance.',
          ),
        );
      } else {
        _validateOfficialConformance(id, result, violations);
      }
    }
    if (protocol == 'mcp' &&
        transport == 'stdio' &&
        claimLevel == 'conformant') {
      violations.add(
        ProtocolCompatibilityViolation(
          'mcp_stdio_conformance_overclaim',
          '$id cannot mark MCP stdio conformant.',
        ),
      );
    }
  }
  if (!_sameSet(evidenceIds, referencedEvidence)) {
    violations.add(
      const ProtocolCompatibilityViolation(
        'evidence_reference_closure',
        'Claims and evidence records must form an exact closed reference set.',
      ),
    );
  }
  violations.addAll(
    validateProtocolFixtureCoverage(root: root, manifest: manifest),
  );
  _validateDocumentationClaims(root, violations);
  return violations;
}

void _validateOfficialConformance(
  String evidenceId,
  Map<String, Object?> report,
  List<ProtocolCompatibilityViolation> violations,
) {
  _expectExactKeys(
    report,
    const <String>{
      'harnessVersion',
      'specVersion',
      'suite',
      'role',
      'scenarios',
      'applicable',
      'passed',
      'failed',
      'skipped',
      'expectedFailures',
    },
    '$evidenceId.result',
  );
  final role = _string(report['role'], '$evidenceId.result.role');
  final expected = switch (role) {
    'client' => phase2aMcpClientScenarios,
    'server' => phase2aMcpServerScenarios,
    _ => const <String>[],
  };
  final scenarios = _stringList(
    report['scenarios'],
    '$evidenceId.result.scenarios',
  );
  final valid = expected.isNotEmpty &&
      report['harnessVersion'] == 'v0.1.16' &&
      report['specVersion'] == '2025-11-25' &&
      report['suite'] == 'all' &&
      _sameList(scenarios, expected) &&
      report['applicable'] == expected.length &&
      report['passed'] == expected.length &&
      report['failed'] == 0 &&
      report['skipped'] == 0 &&
      report['expectedFailures'] == 0;
  if (!valid) {
    violations.add(
      ProtocolCompatibilityViolation(
        'invalid_official_conformance_report',
        '$evidenceId must record the exact v0.1.16 $role all-scenario result.',
      ),
    );
  }
}

void _validateDocumentationClaims(
  Directory root,
  List<ProtocolCompatibilityViolation> violations,
) {
  const supportPath = 'docs/protocol-support.md';
  final file = _containedFile(root, supportPath);
  if (!file.existsSync()) {
    violations.add(
      const ProtocolCompatibilityViolation(
        'missing_protocol_support_matrix',
        'docs/protocol-support.md is required.',
      ),
    );
    return;
  }
  final contents = file.readAsStringSync();
  final requiredClaims = <String>[
    '18/18 applicable client-role scenarios',
    '32/32 applicable server-role scenarios',
    'MCP stdio is not labelled conformant',
    'ACP has no official conformance harness',
    'Process lifecycle, socket binding, browser interaction, credential storage',
  ];
  for (final claim in requiredClaims) {
    if (!contents.contains(claim)) {
      violations.add(
        ProtocolCompatibilityViolation(
          'protocol_support_claim_missing',
          '$supportPath must contain the bounded claim: $claim',
        ),
      );
    }
  }
  if (RegExp(r'\| ACP \|[^\n]*\| conformant \|').hasMatch(contents) ||
      RegExp(r'\| MCP stdio \|[^\n]*\| conformant \|').hasMatch(contents)) {
    violations.add(
      const ProtocolCompatibilityViolation(
        'protocol_support_overclaim',
        'ACP and MCP stdio must not be labelled conformant.',
      ),
    );
  }
}

void _validateDigest(
  Directory root,
  Map<String, Object?> digest,
  String location,
  List<ProtocolCompatibilityViolation> violations,
) {
  _expectExactKeys(
    digest,
    const <String>{'name', 'path', 'sha256'},
    location,
  );
  _string(digest['name'], '$location.name');
  final path = _string(digest['path'], '$location.path');
  final expectedHash = _string(digest['sha256'], '$location.sha256');
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash)) {
    violations.add(
      ProtocolCompatibilityViolation(
        'invalid_artifact_digest',
        '$location.sha256 must be a lowercase SHA-256 digest.',
      ),
    );
    return;
  }
  if (!_isCanonicalRelativePath(path)) {
    violations.add(
      ProtocolCompatibilityViolation(
        'invalid_artifact_path',
        '$location.path must be a canonical relative path.',
      ),
    );
    return;
  }
  final file = _containedFile(root, path);
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    violations.add(
      ProtocolCompatibilityViolation(
        'missing_evidence_artifact',
        '$location references missing regular file $path.',
      ),
    );
    return;
  }
  final actualHash = sha256.convert(file.readAsBytesSync()).toString();
  if (actualHash != expectedHash) {
    violations.add(
      ProtocolCompatibilityViolation(
        'evidence_artifact_hash_mismatch',
        '$location expected $expectedHash but found $actualHash.',
      ),
    );
  }
}

Map<String, Object?> _object(Object? value, String location) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$location must be a JSON object.');
  }
  return value;
}

List<Map<String, Object?>> _objectList(Object? value, String location) {
  if (value is! List<Object?>) {
    throw FormatException('$location must be a JSON array.');
  }
  return <Map<String, Object?>>[
    for (var index = 0; index < value.length; index += 1)
      _object(value[index], '$location[$index]'),
  ];
}

List<String> _stringList(Object? value, String location) {
  if (value is! List<Object?>) {
    throw FormatException('$location must be a JSON array.');
  }
  return <String>[
    for (var index = 0; index < value.length; index += 1)
      _string(value[index], '$location[$index]'),
  ];
}

Set<String> _stringSet(Object? value, String location) =>
    _stringList(value, location).toSet();

String _string(Object? value, String location) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$location must be a non-empty string.');
  }
  return value;
}

void _expectExactKeys(
  Map<String, Object?> object,
  Set<String> expected,
  String location,
) {
  final actual = object.keys.toSet();
  if (!_sameSet(actual, expected)) {
    throw FormatException(
      '$location keys differ: expected $expected, found $actual.',
    );
  }
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

bool _sameList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _isCanonicalRelativePath(String path) =>
    path.isNotEmpty &&
    !path.startsWith('/') &&
    !path.endsWith('/') &&
    !path.contains(r'\') &&
    path.split('/').every(
          (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
        );

File _containedFile(Directory root, String relativePath) {
  if (!_isCanonicalRelativePath(relativePath)) {
    throw ArgumentError.value(
      relativePath,
      'relativePath',
      'Expected a canonical relative path.',
    );
  }
  return File.fromUri(root.absolute.uri.resolve(relativePath));
}
