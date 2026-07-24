import 'dart:convert';
import 'dart:io';

const dartToolingCompatibilityManifestPath =
    'compatibility/phase-2b-dart-tooling.json';
const dartToolingCompatibilitySchemaPath =
    'compatibility/schema/dart-tooling-compatibility.schema.json';

// Replaced with the implementation merge SHA in the evidence-closure PR.
const phase2bDartToolingEvidenceCommit = 'pending-main-merge';

const phase2bDartToolingClaimIds = <String>{
  'P2B-LSP-01',
  'P2B-LSP-02',
  'P2B-LSP-03',
  'P2B-LSP-04',
  'P2B-LSP-05',
  'P2B-LSP-06',
  'P2B-LSP-07',
  'P2B-LSP-08',
  'P2B-LSP-09',
  'P2B-DAP-01',
  'P2B-DAP-02',
  'P2B-DAP-03',
  'P2B-DAP-04',
  'P2B-DAP-05',
  'P2B-DAP-06',
  'P2B-DAP-07',
  'P2B-DAP-08',
  'P2B-DAP-09',
  'P2B-AS-01',
  'P2B-AS-02',
  'P2B-AS-03',
  'P2B-AS-04',
  'P2B-AS-05',
  'P2B-AS-06',
  'P2B-DTD-01',
  'P2B-DTD-02',
  'P2B-DTD-03',
  'P2B-DTD-04',
  'P2B-DTD-05',
  'P2B-DTD-06',
  'P2B-VM-01',
  'P2B-VM-02',
  'P2B-VM-03',
  'P2B-VM-04',
  'P2B-VM-05',
  'P2B-VM-06',
  'P2B-VM-07',
  'P2B-CROSS-01',
  'P2B-CROSS-02',
  'P2B-CROSS-03',
  'P2B-CROSS-04',
};

const phase2bDartToolingKnownUnsupportedIds = <String>{
  'KU-P2B-LSP-PROPOSED',
  'KU-P2B-PEER-SPECIFIC',
  'KU-P2B-DAP-AUTHORIZATION',
  'KU-P2B-AS-VERSION-RANGE',
  'KU-P2B-DTD-VERSION-RANGE',
  'KU-P2B-VM-VERSION-RANGE',
  'KU-P2B-FLUTTER-PLATFORM-REMOTE',
  'KU-P2B-HOST-BOUNDARY',
  'KU-P2B-AGENT-RECONNECT',
};

final class DartToolingCompatibilityViolation {
  const DartToolingCompatibilityViolation(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

Map<String, Object?> buildDartToolingCompatibilityManifest() {
  final peerProfiles = _peerProfiles();
  return <String, Object?>{
    r'$schema': './schema/dart-tooling-compatibility.schema.json',
    'formatVersion': 1,
    'phase': 'phase-2b-dart-tooling',
    'implementationCommit': phase2bDartToolingEvidenceCommit,
    'dartSdkConstraint': '^3.6.0',
    'sources': _sources(),
    'peerProfiles': peerProfiles,
    'claims': <Object?>[
      for (final seed in _claimSeeds)
        <String, Object?>{
          'claimId': seed.id,
          'protocol': seed.protocol,
          'surface': seed.surface,
          'level': seed.level,
          'role': seed.role,
          'transport': seed.transport,
          'sourceRefs': seed.sourceRefs,
          'runtimeVersionPolicy': seed.runtimeVersionPolicy,
          'peerScope': seed.peerScope,
          'platform': seed.platform,
          'evidenceIds': <String>['EV-${seed.id}'],
          'implementationCommit': phase2bDartToolingEvidenceCommit,
          'evidenceCommit': phase2bDartToolingEvidenceCommit,
          'limitations': seed.limitations,
        },
    ],
    'evidence': <Object?>[
      for (final seed in _claimSeeds)
        <String, Object?>{
          'id': 'EV-${seed.id}',
          'claimId': seed.id,
          'kind': seed.kind,
          'peerProfileRefs': seed.peerProfileRefs,
          'artifactPaths': seed.artifactPaths,
          'scenarios': seed.scenarios,
          'result': 'passed',
        },
    ],
    'knownUnsupported': _knownUnsupported(),
  };
}

Map<String, Object?> loadDartToolingCompatibilityManifest(
  Directory root, {
  String path = dartToolingCompatibilityManifestPath,
}) {
  final decoded = jsonDecode(_containedFile(root, path).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'Dart tooling compatibility manifest must be a JSON object.',
    );
  }
  return decoded;
}

List<DartToolingCompatibilityViolation>
    validateDartToolingCompatibilityManifest({
  required Directory root,
  Map<String, Object?>? manifest,
}) {
  try {
    return _validateManifest(
      root.absolute,
      manifest ?? loadDartToolingCompatibilityManifest(root),
    );
  } on Object catch (error) {
    return <DartToolingCompatibilityViolation>[
      DartToolingCompatibilityViolation('invalid_manifest', error.toString()),
    ];
  }
}

List<DartToolingCompatibilityViolation> validateDartToolingFixtureCoverage({
  required Directory root,
  Map<String, Object?>? manifest,
}) {
  try {
    final document = manifest ?? loadDartToolingCompatibilityManifest(root);
    final claims = _objectList(document['claims'], 'claims');
    final evidence = _objectList(document['evidence'], 'evidence');
    final violations = <DartToolingCompatibilityViolation>[];
    final claimIds = <String>{
      for (var index = 0; index < claims.length; index++)
        _string(claims[index]['claimId'], 'claims[$index].claimId'),
    };
    if (!_sameSet(claimIds, phase2bDartToolingClaimIds)) {
      violations.add(
        const DartToolingCompatibilityViolation(
          'fixture_id_coverage_mismatch',
          'Claims must exactly cover the approved 41 Phase 2b IDs.',
        ),
      );
    }
    final evidenceByClaim = <String, int>{};
    for (var index = 0; index < evidence.length; index++) {
      final claimId =
          _string(evidence[index]['claimId'], 'evidence[$index].claimId');
      evidenceByClaim.update(claimId, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final claimId in phase2bDartToolingClaimIds) {
      if (evidenceByClaim[claimId] != 1) {
        violations.add(
          DartToolingCompatibilityViolation(
            'fixture_evidence_cardinality',
            '$claimId must have exactly one dedicated evidence record.',
          ),
        );
      }
    }
    return violations;
  } on Object catch (error) {
    return <DartToolingCompatibilityViolation>[
      DartToolingCompatibilityViolation(
        'invalid_fixture_coverage',
        error.toString(),
      ),
    ];
  }
}

List<DartToolingCompatibilityViolation> _validateManifest(
  Directory root,
  Map<String, Object?> manifest,
) {
  final violations = <DartToolingCompatibilityViolation>[];
  _expectExactKeys(
    manifest,
    const <String>{
      r'$schema',
      'formatVersion',
      'phase',
      'implementationCommit',
      'dartSdkConstraint',
      'sources',
      'peerProfiles',
      'claims',
      'evidence',
      'knownUnsupported',
    },
    'manifest',
  );
  if (manifest[r'$schema'] !=
          './schema/dart-tooling-compatibility.schema.json' ||
      manifest['formatVersion'] != 1 ||
      manifest['phase'] != 'phase-2b-dart-tooling' ||
      manifest['dartSdkConstraint'] != '^3.6.0') {
    violations.add(
      const DartToolingCompatibilityViolation(
        'invalid_manifest_identity',
        'Expected the pinned Phase 2b Dart tooling manifest identity.',
      ),
    );
  }
  final implementationCommit =
      _string(manifest['implementationCommit'], 'implementationCommit');
  if (implementationCommit != phase2bDartToolingEvidenceCommit) {
    violations.add(
      DartToolingCompatibilityViolation(
        'implementation_commit_mismatch',
        'Expected $phase2bDartToolingEvidenceCommit.',
      ),
    );
  }

  final sourceIds = <String>{};
  for (final (index, source) in _indexed(
    _objectList(manifest['sources'], 'sources'),
  )) {
    final location = 'sources[$index]';
    _expectExactKeys(
      source,
      const <String>{
        'sourceId',
        'protocols',
        'release',
        'revision',
        'artifactRefs',
        'profiles',
      },
      location,
    );
    final id = _string(source['sourceId'], '$location.sourceId');
    if (!sourceIds.add(id)) {
      violations.add(
        DartToolingCompatibilityViolation(
          'duplicate_source_id',
          'Duplicate source ID $id.',
        ),
      );
    }
    _stringList(source['protocols'], '$location.protocols');
    _string(source['release'], '$location.release');
    if (!RegExp(r'^[a-f0-9]{40}$')
        .hasMatch(_string(source['revision'], '$location.revision'))) {
      violations.add(
        DartToolingCompatibilityViolation(
          'invalid_source_revision',
          '$id must bind an exact source revision.',
        ),
      );
    }
    _stringList(source['artifactRefs'], '$location.artifactRefs');
    _object(source['profiles'], '$location.profiles');
  }
  if (!_sameSet(
    sourceIds,
    const <String>{
      'lsp-3.18-b7f5132',
      'dap-v1.71.0',
      'dart-3.6.0',
      'dart-3.12.2',
    },
  )) {
    violations.add(
      const DartToolingCompatibilityViolation(
        'source_coverage_mismatch',
        'Manifest must bind the four approved source records.',
      ),
    );
  }

  final peerProfiles = <String, Map<String, Object?>>{};
  for (final (index, peer) in _indexed(
    _objectList(manifest['peerProfiles'], 'peerProfiles'),
  )) {
    final location = 'peerProfiles[$index]';
    final allowedKeys = <String>{
      'id',
      'family',
      'role',
      'release',
      'revision',
      'platform',
      'transport',
      'observedProtocol',
    };
    if (peer.keys.any((key) => !allowedKeys.contains(key))) {
      throw FormatException('$location has unexpected keys.');
    }
    for (final field in const <String>[
      'id',
      'family',
      'role',
      'release',
      'revision',
      'platform',
      'transport',
    ]) {
      _string(peer[field], '$location.$field');
    }
    final id = peer['id']! as String;
    if (peerProfiles.containsKey(id)) {
      violations.add(
        DartToolingCompatibilityViolation(
          'duplicate_peer_profile',
          'Duplicate peer profile $id.',
        ),
      );
    }
    if (peer['role'] == 'dtd' && peer.containsKey('observedProtocol')) {
      violations.add(
        DartToolingCompatibilityViolation(
          'dtd_wire_version_overclaim',
          '$id must not fabricate a DTD wire version.',
        ),
      );
    }
    if (peer.containsKey('observedProtocol')) {
      _string(peer['observedProtocol'], '$location.observedProtocol');
    }
    peerProfiles[id] = peer;
  }

  final unsupportedIds = <String>{};
  for (final (index, item) in _indexed(
    _objectList(manifest['knownUnsupported'], 'knownUnsupported'),
  )) {
    final location = 'knownUnsupported[$index]';
    _expectExactKeys(
      item,
      const <String>{'id', 'scope', 'summary'},
      location,
    );
    final id = _string(item['id'], '$location.id');
    unsupportedIds.add(id);
    _string(item['scope'], '$location.scope');
    _string(item['summary'], '$location.summary');
  }
  if (!_sameSet(unsupportedIds, phase2bDartToolingKnownUnsupportedIds)) {
    violations.add(
      const DartToolingCompatibilityViolation(
        'known_unsupported_coverage_mismatch',
        'Known unsupported IDs must exactly cover the approved inventory.',
      ),
    );
  }

  final claims = _objectList(manifest['claims'], 'claims');
  final claimsById = <String, Map<String, Object?>>{};
  final evidenceRefs = <String>{};
  final referencedUnsupported = <String>{};
  final referencedSources = <String>{};
  for (final (index, claim) in _indexed(claims)) {
    final location = 'claims[$index]';
    _expectExactKeys(
      claim,
      const <String>{
        'claimId',
        'protocol',
        'surface',
        'level',
        'role',
        'transport',
        'sourceRefs',
        'runtimeVersionPolicy',
        'peerScope',
        'platform',
        'evidenceIds',
        'implementationCommit',
        'evidenceCommit',
        'limitations',
      },
      location,
    );
    final id = _string(claim['claimId'], '$location.claimId');
    if (claimsById.containsKey(id)) {
      violations.add(
        DartToolingCompatibilityViolation(
          'duplicate_claim_id',
          'Duplicate claim ID $id.',
        ),
      );
    }
    claimsById[id] = claim;
    final protocol = _string(claim['protocol'], '$location.protocol');
    final level = _string(claim['level'], '$location.level');
    if (!const <String>{
      'lsp',
      'dap',
      'analysis-server',
      'dtd',
      'vm-service',
      'cross-package',
    }.contains(protocol)) {
      violations.add(
        DartToolingCompatibilityViolation(
          'invalid_claim_protocol',
          '$id has unknown protocol $protocol.',
        ),
      );
    }
    if (!const <String>{'implemented', 'verified'}.contains(level)) {
      violations.add(
        DartToolingCompatibilityViolation(
          'invalid_claim_level',
          '$id must be implemented or verified.',
        ),
      );
    }
    for (final field in const <String>[
      'surface',
      'role',
      'transport',
      'runtimeVersionPolicy',
      'peerScope',
      'platform',
    ]) {
      _string(claim[field], '$location.$field');
    }
    if (claim['implementationCommit'] != implementationCommit ||
        claim['evidenceCommit'] != implementationCommit ||
        claim['evidenceCommit'] != phase2bDartToolingEvidenceCommit) {
      violations.add(
        DartToolingCompatibilityViolation(
          'claim_commit_mismatch',
          '$id must bind implementation and evidence to '
              '$phase2bDartToolingEvidenceCommit.',
        ),
      );
    }
    final claimEvidence = _stringList(
      claim['evidenceIds'],
      '$location.evidenceIds',
    );
    if (claimEvidence.length != 1 ||
        claimEvidence.single != 'EV-$id' ||
        !evidenceRefs.add(claimEvidence.single)) {
      violations.add(
        DartToolingCompatibilityViolation(
          'claim_evidence_cardinality',
          '$id must own exactly one dedicated evidence record.',
        ),
      );
    }
    for (final sourceRef
        in _stringList(claim['sourceRefs'], '$location.sourceRefs')) {
      referencedSources.add(sourceRef);
      if (!sourceIds.contains(sourceRef)) {
        violations.add(
          DartToolingCompatibilityViolation(
            'unknown_source_ref',
            '$id references unknown source $sourceRef.',
          ),
        );
      }
    }
    final policy = claim['runtimeVersionPolicy']! as String;
    if (protocol == 'dtd' && policy != 'no-wire-version-exact-sdk-inventory') {
      violations.add(
        DartToolingCompatibilityViolation(
          'dtd_wire_version_overclaim',
          '$id must use the no-wire-version DTD policy.',
        ),
      );
    }
    for (final limitation
        in _stringList(claim['limitations'], '$location.limitations')) {
      referencedUnsupported.add(limitation);
      if (!unsupportedIds.contains(limitation)) {
        violations.add(
          DartToolingCompatibilityViolation(
            'unknown_limitation',
            '$id references unknown limitation $limitation.',
          ),
        );
      }
    }
  }
  if (!_sameSet(claimsById.keys.toSet(), phase2bDartToolingClaimIds)) {
    violations.add(
      const DartToolingCompatibilityViolation(
        'claim_coverage_mismatch',
        'Manifest must contain exactly 41 approved claims.',
      ),
    );
  }
  _validateFamilyCounts(claimsById.keys, violations);
  if (!_sameSet(referencedSources, sourceIds)) {
    violations.add(
      const DartToolingCompatibilityViolation(
        'source_reference_closure',
        'Every source must be referenced by a claim.',
      ),
    );
  }
  if (!_sameSet(referencedUnsupported, unsupportedIds)) {
    violations.add(
      const DartToolingCompatibilityViolation(
        'known_unsupported_reference_closure',
        'Every known limitation must be referenced by a claim.',
      ),
    );
  }

  final evidenceIds = <String>{};
  for (final (index, item) in _indexed(
    _objectList(manifest['evidence'], 'evidence'),
  )) {
    final location = 'evidence[$index]';
    _expectExactKeys(
      item,
      const <String>{
        'id',
        'claimId',
        'kind',
        'peerProfileRefs',
        'artifactPaths',
        'scenarios',
        'result',
      },
      location,
    );
    final id = _string(item['id'], '$location.id');
    final claimId = _string(item['claimId'], '$location.claimId');
    if (!evidenceIds.add(id) || id != 'EV-$claimId') {
      violations.add(
        DartToolingCompatibilityViolation(
          'invalid_evidence_identity',
          '$id is duplicated or does not match $claimId.',
        ),
      );
    }
    final claim = claimsById[claimId];
    if (claim == null) {
      violations.add(
        DartToolingCompatibilityViolation(
          'unknown_evidence_claim',
          '$id references unknown claim $claimId.',
        ),
      );
      continue;
    }
    final kind = _string(item['kind'], '$location.kind');
    final peers =
        _stringList(item['peerProfileRefs'], '$location.peerProfileRefs');
    if (peers.isEmpty) {
      violations.add(
        DartToolingCompatibilityViolation(
          'missing_peer_evidence',
          '$id must bind at least one exact peer profile.',
        ),
      );
    }
    final families = <String>{};
    for (final peerRef in peers) {
      final peer = peerProfiles[peerRef];
      if (peer == null) {
        violations.add(
          DartToolingCompatibilityViolation(
            'unknown_peer_profile',
            '$id references unknown peer profile $peerRef.',
          ),
        );
      } else {
        families.add(peer['family']! as String);
      }
    }
    final level = claim['level']! as String;
    final peerScope = claim['peerScope']! as String;
    if (level == 'verified' &&
        !const <String>{
          'real-process-matrix',
          'full-portability-gate',
        }.contains(kind)) {
      violations.add(
        DartToolingCompatibilityViolation(
          'invalid_verified_evidence',
          '$id verified evidence must be a real process or full gate.',
        ),
      );
    }
    if (level == 'verified' &&
        const <String>{'lsp', 'dap'}.contains(claim['protocol']) &&
        peerScope == 'overlap' &&
        families.length < 2) {
      violations.add(
        DartToolingCompatibilityViolation(
          'overlap_peer_family_undercoverage',
          '$id overlap evidence needs two independent peer families.',
        ),
      );
    }
    if (peerScope == 'peer-specific' && peers.length != 1) {
      violations.add(
        DartToolingCompatibilityViolation(
          'peer_specific_identity_ambiguous',
          '$id peer-specific evidence must bind exactly one peer.',
        ),
      );
    }
    if (const <String>{
          'P2B-AS-06',
          'P2B-DTD-06',
          'P2B-VM-07',
        }.contains(claimId) &&
        !_containsExactDartPair(
            peers, peerProfiles, claim['role']! as String)) {
      violations.add(
        DartToolingCompatibilityViolation(
          'dart_sdk_pair_incomplete',
          '$id must bind exact Dart 3.6.0 and 3.12.2 revisions.',
        ),
      );
    }
    if (item['result'] != 'passed') {
      violations.add(
        DartToolingCompatibilityViolation(
          'evidence_not_passed',
          '$id must record a real pass, never skip or empty success.',
        ),
      );
    }
    if (_stringList(item['scenarios'], '$location.scenarios').isEmpty) {
      violations.add(
        DartToolingCompatibilityViolation(
          'empty_evidence_scenarios',
          '$id has no exercised scenario.',
        ),
      );
    }
    final artifacts =
        _stringList(item['artifactPaths'], '$location.artifactPaths');
    if (artifacts.isEmpty) {
      violations.add(
        DartToolingCompatibilityViolation(
          'missing_evidence_artifact',
          '$id has no evidence artifact.',
        ),
      );
    }
    for (final path in artifacts) {
      if (!_isCanonicalRelativePath(path) ||
          FileSystemEntity.typeSync(
                _containedFile(root, path).path,
                followLinks: false,
              ) !=
              FileSystemEntityType.file) {
        violations.add(
          DartToolingCompatibilityViolation(
            'missing_evidence_artifact',
            '$id references missing or unsafe artifact $path.',
          ),
        );
      }
    }
  }
  if (!_sameSet(evidenceIds, evidenceRefs)) {
    violations.add(
      const DartToolingCompatibilityViolation(
        'evidence_reference_closure',
        'Claims and evidence must form an exact closed set.',
      ),
    );
  }

  violations.addAll(
    validateDartToolingFixtureCoverage(root: root, manifest: manifest),
  );
  _validateDocumentation(root, violations);
  if (jsonEncode(manifest) !=
      jsonEncode(buildDartToolingCompatibilityManifest())) {
    violations.add(
      const DartToolingCompatibilityViolation(
        'manifest_generation_mismatch',
        'Run dart run tool/check_dart_tooling_compatibility.dart --write.',
      ),
    );
  }
  return violations;
}

void _validateFamilyCounts(
  Iterable<String> ids,
  List<DartToolingCompatibilityViolation> violations,
) {
  const expected = <String, int>{
    'P2B-LSP-': 9,
    'P2B-DAP-': 9,
    'P2B-AS-': 6,
    'P2B-DTD-': 6,
    'P2B-VM-': 7,
    'P2B-CROSS-': 4,
  };
  for (final entry in expected.entries) {
    if (ids.where((id) => id.startsWith(entry.key)).length != entry.value) {
      violations.add(
        DartToolingCompatibilityViolation(
          'claim_family_count_mismatch',
          '${entry.key} must contain ${entry.value} claims.',
        ),
      );
    }
  }
}

bool _containsExactDartPair(
  List<String> peerRefs,
  Map<String, Map<String, Object?>> peers,
  String role,
) {
  final matching = <String, String>{
    for (final ref in peerRefs)
      if (peers[ref]?['role'] == role)
        peers[ref]!['release']! as String: peers[ref]!['revision']! as String,
  };
  return matching['3.6.0'] == 'ae7ca5199a0559db0ae60533e9cedd3ce0d6ab04' &&
      matching['3.12.2'] == 'd684a576a6aa954ae107a03b2b4e1d61c3bebe93';
}

void _validateDocumentation(
  Directory root,
  List<DartToolingCompatibilityViolation> violations,
) {
  const required = <String, List<String>>{
    'docs/dart-tooling-support.md': <String>[
      '41/41',
      'DTD has no wire version or version range',
      'caller-owned transport and authorization',
      'Flutter tooling is not claimed',
    ],
    'packages/lsp/README.md': <String>[
      'proposed APIs require an explicit import',
      'does not authorize workspace edits',
    ],
    'packages/dap/README.md': <String>[
      'does not launch processes or terminals',
      'caller-owned transport',
    ],
    'packages/dart/README.md': <String>[
      'DTD has no wire-version range',
      'object IDs are not durable',
    ],
  };
  for (final entry in required.entries) {
    final file = _containedFile(root, entry.key);
    if (!file.existsSync()) {
      violations.add(
        DartToolingCompatibilityViolation(
          'missing_documentation',
          '${entry.key} is required.',
        ),
      );
      continue;
    }
    final contents = file.readAsStringSync();
    for (final phrase in entry.value) {
      if (!contents.contains(phrase)) {
        violations.add(
          DartToolingCompatibilityViolation(
            'documentation_claim_missing',
            '${entry.key} must contain "$phrase".',
          ),
        );
      }
    }
  }
}

List<Map<String, Object?>> _sources() => <Map<String, Object?>>[
      <String, Object?>{
        'sourceId': 'lsp-3.18-b7f5132',
        'protocols': <String>['lsp'],
        'release': '3.18-audit-snapshot',
        'revision': 'b7f5132c95261c0898ae5124e7a91707abc48fcd',
        'artifactRefs': <String>[
          'lsp-meta-model',
          'lsp-meta-model-schema',
          'lsp-meta-model-typescript',
          'lsp-license',
          'lsp-code-license',
        ],
        'profiles': <String, Object?>{
          'stable': '3.17 overlap',
          'proposed': '3.18 explicit opt-in only',
        },
      },
      <String, Object?>{
        'sourceId': 'dap-v1.71.0',
        'protocols': <String>['dap'],
        'release': 'v1.71.0',
        'revision': '51d95ea4e692b34c5d06601bbd1bebc1ff3fbdd4',
        'artifactRefs': <String>[
          'dap-schema',
          'dap-license',
          'dap-code-license',
        ],
        'profiles': <String, Object?>{'schemaVersion': '1.71.0'},
      },
      <String, Object?>{
        'sourceId': 'dart-3.6.0',
        'protocols': <String>[
          'analysis-server',
          'dtd',
          'vm-service',
        ],
        'release': '3.6.0',
        'revision': 'ae7ca5199a0559db0ae60533e9cedd3ce0d6ab04',
        'artifactRefs': <String>[
          'dart-3.6.0-analysis-spec',
          'dart-3.6.0-analysis-api',
          'dart-3.6.0-analysis-generated',
          'dart-3.6.0-analysis-constants',
          'dart-3.6.0-dtd-protocol',
          'dart-3.6.0-vm-service',
          'dart-3.6.0-vm-generated',
          'dart-3.6.0-vm-runtime-version',
          'dart-sdk-license',
        ],
        'profiles': <String, Object?>{
          'analysisServerApi': '1.38.0',
          'dtdInventory': 'dtd-fixed-inventory-v1',
          'vmService': '4.16',
        },
      },
      <String, Object?>{
        'sourceId': 'dart-3.12.2',
        'protocols': <String>[
          'analysis-server',
          'dtd',
          'vm-service',
        ],
        'release': '3.12.2',
        'revision': 'd684a576a6aa954ae107a03b2b4e1d61c3bebe93',
        'artifactRefs': <String>[
          'dart-3.12.2-analysis-spec',
          'dart-3.12.2-analysis-api',
          'dart-3.12.2-analysis-generated',
          'dart-3.12.2-analysis-constants',
          'dart-3.12.2-dtd-protocol',
          'dart-3.12.2-vm-service',
          'dart-3.12.2-vm-generated',
          'dart-3.12.2-vm-runtime-version',
        ],
        'profiles': <String, Object?>{
          'analysisServerApi': '1.40.1',
          'dtdInventory': 'dtd-fixed-inventory-v1',
          'vmService': '4.21',
        },
      },
    ];

List<Map<String, Object?>> _peerProfiles() {
  const minRevision = 'ae7ca5199a0559db0ae60533e9cedd3ce0d6ab04';
  const currentRevision = 'd684a576a6aa954ae107a03b2b4e1d61c3bebe93';
  Map<String, Object?> peer({
    required String id,
    required String family,
    required String role,
    required String release,
    required String revision,
    required String transport,
    String platform = 'macos-arm64',
    String? observedProtocol,
  }) =>
      <String, Object?>{
        'id': id,
        'family': family,
        'role': role,
        'release': release,
        'revision': revision,
        'platform': platform,
        'transport': transport,
        if (observedProtocol != null) 'observedProtocol': observedProtocol,
      };
  return <Map<String, Object?>>[
    peer(
      id: 'dart-test-current',
      family: 'dart-sdk',
      role: 'unit-contract',
      release: '3.12.2',
      revision: currentRevision,
      transport: 'in-process',
    ),
    peer(
      id: 'dart-sdk-minimum',
      family: 'dart-sdk',
      role: 'portability',
      release: '3.6.0',
      revision: minRevision,
      transport: 'vm-js-wasm',
    ),
    peer(
      id: 'dart-sdk-current',
      family: 'dart-sdk',
      role: 'portability',
      release: '3.12.2',
      revision: currentRevision,
      transport: 'vm-chrome-js-wasm',
    ),
    peer(
      id: 'lsp-dart-minimum',
      family: 'dart-language-server',
      role: 'lsp',
      release: '3.6.0',
      revision: minRevision,
      transport: 'stdio-content-length',
      observedProtocol: 'LSP stable overlap',
    ),
    peer(
      id: 'lsp-dart-current',
      family: 'dart-language-server',
      role: 'lsp',
      release: '3.12.2',
      revision: currentRevision,
      transport: 'stdio-content-length',
      observedProtocol: 'LSP stable overlap',
    ),
    peer(
      id: 'lsp-typescript-5.3.0',
      family: 'typescript-language-server',
      role: 'lsp',
      release: '5.3.0+typescript-6.0.3',
      revision: '589044479e4bc2bffb796b593242136f5323b582',
      transport: 'stdio-content-length',
      observedProtocol: 'LSP stable overlap',
    ),
    peer(
      id: 'dap-dart-minimum',
      family: 'dart-debug-adapter',
      role: 'dap',
      release: '3.6.0',
      revision: minRevision,
      transport: 'stdio-content-length',
      observedProtocol: 'DAP 1.x',
    ),
    peer(
      id: 'dap-dart-current',
      family: 'dart-debug-adapter',
      role: 'dap',
      release: '3.12.2',
      revision: currentRevision,
      transport: 'stdio-content-length',
      observedProtocol: 'DAP 1.x',
    ),
    peer(
      id: 'dap-js-debug-1.117.0',
      family: 'vscode-js-debug',
      role: 'dap',
      release: '1.117.0',
      revision: '496a6f1a4fc8198bcd563f97b84a07aa39917404',
      transport: 'tcp-content-length',
      observedProtocol: 'DAP 1.x',
    ),
    for (final entry in const <(String, String, String, String)>[
      ('analysis-server-minimum', 'analysis-server', '3.6.0', minRevision),
      ('analysis-server-current', 'analysis-server', '3.12.2', currentRevision),
      ('dtd-minimum', 'dtd', '3.6.0', minRevision),
      ('dtd-current', 'dtd', '3.12.2', currentRevision),
      ('vm-service-minimum', 'vm-service', '3.6.0', minRevision),
      ('vm-service-current', 'vm-service', '3.12.2', currentRevision),
    ])
      peer(
        id: entry.$1,
        family: entry.$2 == 'analysis-server'
            ? 'dart-analysis-server'
            : 'dart-${entry.$2}',
        role: entry.$2,
        release: entry.$3,
        revision: entry.$4,
        transport:
            entry.$2 == 'analysis-server' ? 'stdio-json' : 'websocket-json-rpc',
        observedProtocol: switch (entry.$2) {
          'analysis-server' => entry.$3 == '3.6.0' ? '1.38.0' : '1.40.1',
          'vm-service' => entry.$3 == '3.6.0' ? '4.16' : '4.21',
          _ => null,
        },
      ),
  ];
}

List<Map<String, Object?>> _knownUnsupported() => const <Map<String, Object?>>[
      <String, Object?>{
        'id': 'KU-P2B-LSP-PROPOSED',
        'scope': 'lsp',
        'summary':
            'LSP 3.18 proposed APIs are explicit opt-in and not generally verified.',
      },
      <String, Object?>{
        'id': 'KU-P2B-PEER-SPECIFIC',
        'scope': 'lsp-dap',
        'summary': 'Single-peer methods and capabilities remain peer-specific.',
      },
      <String, Object?>{
        'id': 'KU-P2B-DAP-AUTHORIZATION',
        'scope': 'dap',
        'summary':
            'DAP capabilities do not authorize terminals, processes, filesystems, or debuggees.',
      },
      <String, Object?>{
        'id': 'KU-P2B-AS-VERSION-RANGE',
        'scope': 'analysis-server',
        'summary':
            'Only API 1.38.0 and 1.40.1 at the exact SDK revisions are verified.',
      },
      <String, Object?>{
        'id': 'KU-P2B-DTD-VERSION-RANGE',
        'scope': 'dtd',
        'summary':
            'DTD has no wire range; only the fixed inventory at two SDK revisions is verified.',
      },
      <String, Object?>{
        'id': 'KU-P2B-VM-VERSION-RANGE',
        'scope': 'vm-service',
        'summary': 'Only VM Service 4.16 and 4.21 fixed profiles are verified.',
      },
      <String, Object?>{
        'id': 'KU-P2B-FLUTTER-PLATFORM-REMOTE',
        'scope': 'platform',
        'summary':
            'Flutter tooling, all OS and CPU combinations, and remote/container transports are not claimed.',
      },
      <String, Object?>{
        'id': 'KU-P2B-HOST-BOUNDARY',
        'scope': 'host',
        'summary':
            'Caller-owned process, socket, authorization, credential, and sandbox policy remain outside the packages.',
      },
      <String, Object?>{
        'id': 'KU-P2B-AGENT-RECONNECT',
        'scope': 'agent',
        'summary':
            'Protocol reconnect does not restore a higher-level Agent Run.',
      },
    ];

final class _ClaimSeed {
  const _ClaimSeed(
    this.id,
    this.protocol,
    this.surface,
    this.level,
    this.role,
    this.transport,
    this.sourceRefs,
    this.runtimeVersionPolicy,
    this.peerScope,
    this.peerProfileRefs,
    this.artifactPaths,
    this.scenarios, {
    this.limitations = const <String>[],
    this.kind = 'unit-and-contract',
    this.platform = 'portable-dart',
  });

  final String id;
  final String protocol;
  final String surface;
  final String level;
  final String role;
  final String transport;
  final List<String> sourceRefs;
  final String runtimeVersionPolicy;
  final String peerScope;
  final List<String> peerProfileRefs;
  final List<String> artifactPaths;
  final List<String> scenarios;
  final List<String> limitations;
  final String kind;
  final String platform;
}

const _host = <String>['dart-test-current'];
const _dartSources = <String>['dart-3.6.0', 'dart-3.12.2'];
const _lspSource = <String>['lsp-3.18-b7f5132'];
const _dapSource = <String>['dap-v1.71.0'];

const _claimSeeds = <_ClaimSeed>[
  _ClaimSeed(
      'P2B-LSP-01',
      'lsp',
      'source-and-generated-union',
      'implemented',
      'codec',
      'json',
      _lspSource,
      'lsp-3.18-audit-snapshot',
      'in-process',
      _host,
      <String>['packages/lsp/test/schema/source_test.dart'],
      <String>['source-lock-and-inventory'],
      limitations: <String>['KU-P2B-LSP-PROPOSED']),
  _ClaimSeed(
      'P2B-LSP-02',
      'lsp',
      'stable-codec-and-open-values',
      'implemented',
      'codec',
      'json-rpc',
      _lspSource,
      'lsp-stable-overlap',
      'in-process',
      _host,
      <String>['packages/lsp/test/schema/codec_golden_test.dart'],
      <String>['golden-positive-negative']),
  _ClaimSeed(
      'P2B-LSP-03',
      'lsp',
      'lifecycle-correlation-cancellation',
      'implemented',
      'client',
      'caller-owned',
      _lspSource,
      'lsp-stable-overlap',
      'in-process',
      _host,
      <String>['packages/lsp/test/lifecycle_test.dart'],
      <String>['initialize-shutdown-cancel-races'],
      limitations: <String>['KU-P2B-AGENT-RECONNECT']),
  _ClaimSeed(
      'P2B-LSP-04',
      'lsp',
      'capability-and-dynamic-registration',
      'implemented',
      'client',
      'caller-owned',
      _lspSource,
      'lsp-stable-overlap',
      'in-process',
      _host,
      <String>['packages/lsp/test/dynamic_registration_test.dart'],
      <String>['immutable-capability-generations']),
  _ClaimSeed(
      'P2B-LSP-05',
      'lsp',
      'document-sync-and-content-version',
      'implemented',
      'client',
      'caller-owned',
      _lspSource,
      'lsp-stable-overlap',
      'in-process',
      _host,
      <String>['packages/lsp/test/document_sync_test.dart'],
      <String>['incremental-sync-and-content-modified']),
  _ClaimSeed(
      'P2B-LSP-06',
      'lsp',
      'reverse-request-proposals',
      'implemented',
      'client',
      'caller-owned',
      _lspSource,
      'lsp-stable-overlap',
      'in-process',
      _host,
      <String>['packages/lsp/test/apply_edit_proposal_test.dart'],
      <String>['proposal-without-side-effect'],
      limitations: <String>['KU-P2B-HOST-BOUNDARY']),
  _ClaimSeed(
      'P2B-LSP-07',
      'lsp',
      'scripted-chaos-and-replay',
      'implemented',
      'client',
      'stdio-content-length',
      _lspSource,
      'lsp-stable-overlap',
      'in-process',
      _host,
      <String>['packages/lsp/test/scripted_peer_test.dart'],
      <String>['chaos-framing-and-sanitized-replay']),
  _ClaimSeed(
      'P2B-LSP-08',
      'lsp',
      'cross-family-overlap-peer-matrix',
      'verified',
      'lsp',
      'stdio-content-length',
      _lspSource,
      'lsp-stable-overlap',
      'overlap',
      <String>['lsp-dart-minimum', 'lsp-dart-current', 'lsp-typescript-5.3.0'],
      <String>['tool/run_lsp_peer_matrix.dart'],
      <String>['initialize', 'open', 'hover', 'completion', 'shutdown'],
      limitations: <String>['KU-P2B-PEER-SPECIFIC'],
      kind: 'real-process-matrix',
      platform: 'macos-arm64'),
  _ClaimSeed(
      'P2B-LSP-09',
      'lsp',
      'typescript-peer-profile',
      'verified',
      'lsp',
      'stdio-content-length',
      _lspSource,
      'lsp-stable-overlap',
      'peer-specific',
      <String>['lsp-typescript-5.3.0'],
      <String>['tool/src/lsp_peer_harness.dart'],
      <String>['typescript-language-server-5.3.0-typescript-6.0.3'],
      limitations: <String>['KU-P2B-PEER-SPECIFIC'],
      kind: 'real-process-matrix',
      platform: 'macos-arm64'),
  _ClaimSeed(
      'P2B-DAP-01',
      'dap',
      'source-and-generated-union',
      'implemented',
      'codec',
      'json',
      _dapSource,
      'dap-1.71.0',
      'in-process',
      _host,
      <String>['packages/dap/test/schema/source_test.dart'],
      <String>['source-lock-and-schema-inventory']),
  _ClaimSeed(
      'P2B-DAP-02',
      'dap',
      'codec-and-open-values',
      'implemented',
      'codec',
      'json',
      _dapSource,
      'dap-1.71.0',
      'in-process',
      _host,
      <String>['packages/dap/test/schema/codec_golden_test.dart'],
      <String>['golden-positive-negative']),
  _ClaimSeed(
      'P2B-DAP-03',
      'dap',
      'lifecycle-correlation-cancellation',
      'implemented',
      'client',
      'caller-owned',
      _dapSource,
      'dap-1.71.0',
      'in-process',
      _host,
      <String>['packages/dap/test/lifecycle_test.dart'],
      <String>['initialize-configure-terminal-races'],
      limitations: <String>['KU-P2B-AGENT-RECONNECT']),
  _ClaimSeed(
      'P2B-DAP-04',
      'dap',
      'capability-generations',
      'implemented',
      'client',
      'caller-owned',
      _dapSource,
      'dap-1.71.0',
      'in-process',
      _host,
      <String>['packages/dap/test/capabilities_event_test.dart'],
      <String>['initialize-and-capabilities-event']),
  _ClaimSeed(
      'P2B-DAP-05',
      'dap',
      'debug-state-and-reference-lifetime',
      'implemented',
      'client',
      'caller-owned',
      _dapSource,
      'dap-1.71.0',
      'in-process',
      _host,
      <String>['packages/dap/test/reference_lifetime_test.dart'],
      <String>['stopped-continued-reference-expiry']),
  _ClaimSeed(
      'P2B-DAP-06',
      'dap',
      'terminal-and-start-debugging-proposals',
      'implemented',
      'client',
      'caller-owned',
      _dapSource,
      'dap-1.71.0',
      'in-process',
      _host, <String>[
    'packages/dap/test/run_in_terminal_proposal_test.dart'
  ], <String>[
    'proposal-without-side-effect'
  ],
      limitations: <String>[
        'KU-P2B-DAP-AUTHORIZATION',
        'KU-P2B-HOST-BOUNDARY'
      ]),
  _ClaimSeed(
      'P2B-DAP-07',
      'dap',
      'scripted-chaos-and-replay',
      'implemented',
      'client',
      'content-length',
      _dapSource,
      'dap-1.71.0',
      'in-process',
      _host,
      <String>['packages/dap/test/scripted_peer_test.dart'],
      <String>['chaos-framing-and-sanitized-replay']),
  _ClaimSeed(
      'P2B-DAP-08',
      'dap',
      'cross-family-overlap-peer-matrix',
      'verified',
      'dap',
      'content-length',
      _dapSource,
      'dap-1.71.0',
      'overlap',
      <String>['dap-dart-minimum', 'dap-dart-current', 'dap-js-debug-1.117.0'],
      <String>['tool/run_dap_peer_matrix.dart'],
      <String>[
        'initialize',
        'breakpoint',
        'launch',
        'stopped',
        'stack',
        'continue',
        'disconnect'
      ],
      limitations: <String>['KU-P2B-PEER-SPECIFIC'],
      kind: 'real-process-matrix',
      platform: 'macos-arm64'),
  _ClaimSeed(
      'P2B-DAP-09',
      'dap',
      'js-debug-peer-profile',
      'verified',
      'dap',
      'tcp-content-length',
      _dapSource,
      'dap-1.71.0',
      'peer-specific',
      <String>['dap-js-debug-1.117.0'],
      <String>['tool/src/dap_peer_harness.dart'],
      <String>['js-debug-1.117.0-start-debugging-profile'],
      limitations: <String>['KU-P2B-PEER-SPECIFIC'],
      kind: 'real-process-matrix',
      platform: 'macos-arm64'),
  _ClaimSeed(
      'P2B-AS-01',
      'analysis-server',
      'pinned-source-and-union',
      'implemented',
      'analysis-server',
      'stdio-json',
      _dartSources,
      'api-1.38.0-and-1.40.1',
      'in-process',
      _host,
      <String>['packages/dart/test/analysis_server/source_test.dart'],
      <String>['source-and-generated-inventory'],
      limitations: <String>['KU-P2B-AS-VERSION-RANGE']),
  _ClaimSeed(
      'P2B-AS-02',
      'analysis-server',
      'version-and-availability',
      'implemented',
      'analysis-server',
      'stdio-json',
      _dartSources,
      'api-1.38.0-and-1.40.1',
      'in-process',
      _host, <String>[
    'packages/dart/test/analysis_server/version_availability_test.dart'
  ], <String>[
    'minimum-current-diff-and-major-rejection'
  ]),
  _ClaimSeed(
      'P2B-AS-03',
      'analysis-server',
      'codec-and-generated-models',
      'implemented',
      'analysis-server',
      'stdio-json',
      _dartSources,
      'api-1.38.0-and-1.40.1',
      'in-process',
      _host,
      <String>['packages/dart/test/analysis_server/codec_golden_test.dart'],
      <String>['request-response-notification-goldens']),
  _ClaimSeed(
      'P2B-AS-04',
      'analysis-server',
      'client-lifecycle-and-correlation',
      'implemented',
      'analysis-server',
      'caller-owned',
      _dartSources,
      'api-1.38.0-and-1.40.1',
      'in-process',
      _host,
      <String>['packages/dart/test/analysis_server/lifecycle_test.dart'],
      <String>['version-first-cancel-shutdown-reconnect']),
  _ClaimSeed(
      'P2B-AS-05',
      'analysis-server',
      'edit-proposals',
      'implemented',
      'analysis-server',
      'caller-owned',
      _dartSources,
      'api-1.38.0-and-1.40.1',
      'in-process',
      _host,
      <String>['packages/dart/test/analysis_server/edit_proposal_test.dart'],
      <String>['source-change-without-filesystem-write'],
      limitations: <String>['KU-P2B-HOST-BOUNDARY']),
  _ClaimSeed(
      'P2B-AS-06',
      'analysis-server',
      'exact-sdk-peer-matrix',
      'verified',
      'analysis-server',
      'stdio-json',
      _dartSources,
      'api-1.38.0-and-1.40.1',
      'exact-sdk-matrix',
      <String>['analysis-server-minimum', 'analysis-server-current'],
      <String>['tool/run_analysis_server_peer_matrix.dart'],
      <String>[
        'version',
        'clientCapabilities',
        'setRoots',
        'status',
        'errors',
        'hover',
        'shutdown'
      ],
      kind: 'real-process-matrix',
      platform: 'macos-arm64'),
  _ClaimSeed(
      'P2B-DTD-01',
      'dtd',
      'pinned-docs-and-fixed-inventory',
      'implemented',
      'dtd',
      'websocket-json-rpc',
      _dartSources,
      'no-wire-version-exact-sdk-inventory',
      'in-process',
      _host,
      <String>['packages/dart/test/dtd/source_test.dart'],
      <String>['two-docs-and-fixed-method-inventory'],
      limitations: <String>['KU-P2B-DTD-VERSION-RANGE']),
  _ClaimSeed(
      'P2B-DTD-02',
      'dtd',
      'codec-and-dynamic-method-boundary',
      'implemented',
      'dtd',
      'websocket-json-rpc',
      _dartSources,
      'no-wire-version-exact-sdk-inventory',
      'in-process',
      _host,
      <String>['packages/dart/test/dtd/codec_golden_test.dart'],
      <String>['fixed-and-dynamic-codec']),
  _ClaimSeed(
      'P2B-DTD-03',
      'dtd',
      'stream-lifecycle',
      'implemented',
      'dtd',
      'websocket-json-rpc',
      _dartSources,
      'no-wire-version-exact-sdk-inventory',
      'in-process',
      _host,
      <String>['packages/dart/test/dtd/stream_test.dart'],
      <String>['listen-cancel-notify-bounds']),
  _ClaimSeed(
      'P2B-DTD-04',
      'dtd',
      'service-ownership',
      'implemented',
      'dtd',
      'websocket-json-rpc',
      _dartSources,
      'no-wire-version-exact-sdk-inventory',
      'in-process',
      _host,
      <String>['packages/dart/test/dtd/service_lifecycle_test.dart'],
      <String>['owner-generation-and-late-response']),
  _ClaimSeed(
      'P2B-DTD-05',
      'dtd',
      'filesystem-and-secret-boundary',
      'implemented',
      'dtd',
      'caller-owned',
      _dartSources,
      'no-wire-version-exact-sdk-inventory',
      'in-process',
      _host,
      <String>['packages/dart/test/dtd/secret_redaction_test.dart'],
      <String>['typed-rpc-and-secret-redaction'],
      limitations: <String>['KU-P2B-HOST-BOUNDARY']),
  _ClaimSeed(
      'P2B-DTD-06',
      'dtd',
      'exact-sdk-devtools-peer-matrix',
      'verified',
      'dtd',
      'websocket-json-rpc',
      _dartSources,
      'no-wire-version-exact-sdk-inventory',
      'exact-sdk-matrix',
      <String>['dtd-minimum', 'dtd-current'],
      <String>['tool/run_dtd_peer_matrix.dart'],
      <String>[
        'machineEvent',
        'stream',
        'service',
        'fileSystemDenied',
        'invalidRootSecret',
        'cleanup'
      ],
      kind: 'real-process-matrix',
      platform: 'macos-arm64'),
  _ClaimSeed(
      'P2B-VM-01',
      'vm-service',
      'pinned-source-runtime-oracle-and-union',
      'implemented',
      'vm-service',
      'websocket-json-rpc',
      _dartSources,
      'major-4-minor-16-and-21',
      'in-process',
      _host,
      <String>['packages/dart/test/vm_service/source_test.dart'],
      <String>['service-doc-generated-api-runtime-oracle'],
      limitations: <String>['KU-P2B-VM-VERSION-RANGE']),
  _ClaimSeed(
      'P2B-VM-02',
      'vm-service',
      'version-and-availability',
      'implemented',
      'vm-service',
      'websocket-json-rpc',
      _dartSources,
      'major-4-minor-16-and-21',
      'in-process',
      _host,
      <String>['packages/dart/test/vm_service/version_availability_test.dart'],
      <String>['runtime-version-and-current-only-diff']),
  _ClaimSeed(
      'P2B-VM-03',
      'vm-service',
      'codec-model-and-sentinel',
      'implemented',
      'vm-service',
      'websocket-json-rpc',
      _dartSources,
      'major-4-minor-16-and-21',
      'in-process',
      _host,
      <String>['packages/dart/test/vm_service/codec_golden_test.dart'],
      <String>['rpc-result-error-event-sentinel']),
  _ClaimSeed(
      'P2B-VM-04',
      'vm-service',
      'client-and-protocol-gates',
      'implemented',
      'vm-service',
      'caller-owned',
      _dartSources,
      'major-4-minor-16-and-21',
      'in-process',
      _host,
      <String>['packages/dart/test/vm_service/lifecycle_test.dart'],
      <String>['version-first-supported-protocols-reconnect']),
  _ClaimSeed(
      'P2B-VM-05',
      'vm-service',
      'stream-lifecycle',
      'implemented',
      'vm-service',
      'caller-owned',
      _dartSources,
      'major-4-minor-16-and-21',
      'in-process',
      _host,
      <String>['packages/dart/test/vm_service/stream_test.dart'],
      <String>['listen-cancel-ordering-late-event']),
  _ClaimSeed(
      'P2B-VM-06',
      'vm-service',
      'object-and-isolate-reference-lifetime',
      'implemented',
      'vm-service',
      'caller-owned',
      _dartSources,
      'major-4-minor-16-and-21',
      'in-process',
      _host,
      <String>['packages/dart/test/vm_service/reference_lifetime_test.dart'],
      <String>['sentinel-pause-isolate-connection-generations']),
  _ClaimSeed(
      'P2B-VM-07',
      'vm-service',
      'exact-sdk-vm-peer-matrix',
      'verified',
      'vm-service',
      'websocket-json-rpc',
      _dartSources,
      'major-4-minor-16-and-21',
      'exact-sdk-matrix',
      <String>['vm-service-minimum', 'vm-service-current'],
      <String>['tool/run_vm_service_peer_matrix.dart'],
      <String>[
        'version',
        'supportedProtocols',
        'vm',
        'stream',
        'isolate',
        'object',
        'temporaryIdExpired',
        'disconnect',
        'cleanup'
      ],
      kind: 'real-process-matrix',
      platform: 'macos-arm64'),
  _ClaimSeed(
      'P2B-CROSS-01',
      'cross-package',
      'minimum-current-portability',
      'verified',
      'portability',
      'vm-js-wasm-chrome',
      <String>['lsp-3.18-b7f5132', 'dap-v1.71.0', 'dart-3.6.0', 'dart-3.12.2'],
      'dart-sdk-3.6.0-and-3.12.2',
      'full-gate',
      <String>['dart-sdk-minimum', 'dart-sdk-current'],
      <String>['packages/dart/test/portable_compile_smoke.dart'],
      <String>['minimum-current-vm-js-wasm-current-chrome'],
      limitations: <String>['KU-P2B-FLUTTER-PLATFORM-REMOTE'],
      kind: 'full-portability-gate',
      platform: 'macos-arm64'),
  _ClaimSeed(
      'P2B-CROSS-02',
      'cross-package',
      'dependency-and-side-effect-boundary',
      'implemented',
      'boundary',
      'source',
      <String>['lsp-3.18-b7f5132', 'dap-v1.71.0', 'dart-3.6.0', 'dart-3.12.2'],
      'portable-default-barrels',
      'in-process',
      _host,
      <String>['packages/dart/test/entrypoint_boundary_test.dart'],
      <String>['no-dart-io-no-flutter-no-host-authorization'],
      limitations: <String>['KU-P2B-HOST-BOUNDARY']),
  _ClaimSeed(
      'P2B-CROSS-03',
      'cross-package',
      'claim-evidence-source-closure',
      'implemented',
      'compatibility',
      'json',
      <String>['lsp-3.18-b7f5132', 'dap-v1.71.0', 'dart-3.6.0', 'dart-3.12.2'],
      'phase-2b-manifest-v1',
      'in-process',
      _host,
      <String>['tool/test/dart_tooling_fixture_coverage_test.dart'],
      <String>['41-claim-one-to-one-evidence-closure']),
  _ClaimSeed(
      'P2B-CROSS-04',
      'cross-package',
      'documentation-and-unsupported-closure',
      'implemented',
      'documentation',
      'markdown',
      <String>['lsp-3.18-b7f5132', 'dap-v1.71.0', 'dart-3.6.0', 'dart-3.12.2'],
      'phase-2b-bounded-support',
      'in-process',
      _host,
      <String>['docs/dart-tooling-support.md'],
      <String>['readme-example-support-matrix-alignment'],
      limitations: <String>[
        'KU-P2B-LSP-PROPOSED',
        'KU-P2B-PEER-SPECIFIC',
        'KU-P2B-DAP-AUTHORIZATION',
        'KU-P2B-AS-VERSION-RANGE',
        'KU-P2B-DTD-VERSION-RANGE',
        'KU-P2B-VM-VERSION-RANGE',
        'KU-P2B-FLUTTER-PLATFORM-REMOTE',
        'KU-P2B-HOST-BOUNDARY',
        'KU-P2B-AGENT-RECONNECT',
      ]),
];

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
    for (var index = 0; index < value.length; index++)
      _object(value[index], '$location[$index]'),
  ];
}

List<String> _stringList(Object? value, String location) {
  if (value is! List<Object?>) {
    throw FormatException('$location must be a JSON array.');
  }
  return <String>[
    for (var index = 0; index < value.length; index++)
      _string(value[index], '$location[$index]'),
  ];
}

String _string(Object? value, String location) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$location must be a non-empty string.');
  }
  return value;
}

Iterable<(int, T)> _indexed<T>(List<T> values) sync* {
  for (var index = 0; index < values.length; index++) {
    yield (index, values[index]);
  }
}

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String location,
) {
  if (!_sameSet(value.keys.toSet(), expected)) {
    throw FormatException(
      '$location keys must be exactly $expected, found ${value.keys.toSet()}.',
    );
  }
}

bool _sameSet<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

bool _isCanonicalRelativePath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.startsWith('\\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(path)) {
    return false;
  }
  final segments = path.replaceAll('\\', '/').split('/');
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

File _containedFile(Directory root, String path) {
  if (!_isCanonicalRelativePath(path)) {
    throw FormatException('Unsafe repository-relative path: $path.');
  }
  final canonicalRoot = root.absolute.path;
  final file = File.fromUri(root.absolute.uri.resolve(path));
  final parent = file.parent.absolute.path;
  final separator = Platform.pathSeparator;
  if (parent != canonicalRoot &&
      !parent.startsWith('$canonicalRoot$separator')) {
    throw FormatException('Path escapes repository root: $path.');
  }
  return file;
}
