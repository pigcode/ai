import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const kernelStoreCompatibilityManifestPath =
    'compatibility/phase-3-kernel-store.json';
const kernelStoreCompatibilitySchemaPath =
    'compatibility/schema/kernel-store-compatibility.schema.json';

// Replaced with the main merge SHA in the dedicated evidence-closure PR.
const phase3KernelStoreEvidenceCommit = 'pending-main-merge';

const phase3KernelStoreClaimIds = <String>{
  'P3-KERNEL-01',
  'P3-KERNEL-02',
  'P3-KERNEL-03',
  'P3-KERNEL-04',
  'P3-KERNEL-05',
  'P3-KERNEL-06',
  'P3-KERNEL-07',
  'P3-KERNEL-08',
  'P3-KERNEL-09',
  'P3-KERNEL-10',
  'P3-KERNEL-11',
  'P3-KERNEL-12',
  'P3-KERNEL-13',
  'P3-KERNEL-14',
  'P3-STORE-01',
  'P3-STORE-02',
  'P3-STORE-03',
  'P3-STORE-04',
  'P3-STORE-05',
  'P3-STORE-06',
  'P3-STORE-07',
  'P3-STORE-08',
  'P3-STORE-09',
  'P3-STORE-10',
  'P3-CROSS-01',
  'P3-CROSS-02',
  'P3-CROSS-03',
  'P3-CROSS-04',
};

const phase3KnownUnsupportedIds = <String>{
  'KU-P3-POWER-LOSS',
  'KU-P3-MALICIOUS-ROOT',
  'KU-P3-ENCRYPTION',
  'KU-P3-NETWORK-FS',
  'KU-P3-NONCOOPERATIVE-WRITER',
  'KU-P3-HOST-SANDBOX',
  'KU-P3-PRODUCTION-DRIVER',
  'KU-P3-PERSISTENT-APPROVAL',
  'KU-P3-CROSS-PLATFORM',
  'KU-P3-FUTURE-MIGRATION',
};

final class KernelStoreCompatibilityViolation {
  const KernelStoreCompatibilityViolation(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

Map<String, Object?> loadKernelStoreCompatibilityManifest(
  Directory root, {
  String path = kernelStoreCompatibilityManifestPath,
}) {
  final decoded = jsonDecode(_containedFile(root, path).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'Kernel/Store compatibility manifest must be a JSON object.',
    );
  }
  return decoded;
}

List<KernelStoreCompatibilityViolation>
    validateKernelStoreCompatibilityManifest({
  required Directory root,
  Map<String, Object?>? manifest,
}) {
  try {
    return _validateManifest(
      root.absolute,
      manifest ?? loadKernelStoreCompatibilityManifest(root),
    );
  } on Object catch (error) {
    return <KernelStoreCompatibilityViolation>[
      KernelStoreCompatibilityViolation('invalid_manifest', error.toString()),
    ];
  }
}

List<KernelStoreCompatibilityViolation> validateKernelStoreFixtureCoverage({
  required Directory root,
  Map<String, Object?>? manifest,
}) {
  try {
    final document = manifest ?? loadKernelStoreCompatibilityManifest(root);
    final claims = _objectList(document['claims'], 'claims');
    final evidence = _objectList(document['evidence'], 'evidence');
    final violations = <KernelStoreCompatibilityViolation>[];
    final claimIds = <String>{
      for (var index = 0; index < claims.length; index++)
        _string(claims[index]['id'], 'claims[$index].id'),
    };
    if (!_sameSet(claimIds, phase3KernelStoreClaimIds)) {
      violations.add(
        const KernelStoreCompatibilityViolation(
          'fixture_id_coverage_mismatch',
          'Claims must exactly cover the approved 28 Phase 3 IDs.',
        ),
      );
    }
    final evidenceByClaim = <String, int>{};
    for (var index = 0; index < evidence.length; index++) {
      final claimId =
          _string(evidence[index]['claimId'], 'evidence[$index].claimId');
      evidenceByClaim.update(claimId, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final claimId in phase3KernelStoreClaimIds) {
      if (evidenceByClaim[claimId] != 1) {
        violations.add(
          KernelStoreCompatibilityViolation(
            'fixture_evidence_cardinality',
            '$claimId must have exactly one evidence record.',
          ),
        );
      }
    }
    _requireEvidenceArtifacts(
      evidence,
      'P3-KERNEL-01',
      const <String>{
        'packages/agent_kernel/test/id/opaque_id_test.dart',
        'packages/agent_io/test/store/post_prune_identity_registry_test.dart',
      },
      'post_prune_identity_evidence_missing',
      violations,
    );
    _requireEvidenceAssertions(
      evidence,
      'P3-KERNEL-01',
      const <String>{'session-identity-registry-root-bound'},
      'registry_root_binding_missing',
      violations,
    );
    _requireEvidenceArtifacts(
      evidence,
      'P3-KERNEL-04',
      const <String>{
        'packages/agent_io/test/store/compare_and_append_test.dart',
        'packages/agent_io/test/store/post_prune_command_dedupe_test.dart',
      },
      'command_registry_evidence_missing',
      violations,
    );
    _requireEvidenceAssertions(
      evidence,
      'P3-KERNEL-04',
      const <String>{
        'root-session-catalog-and-create-command-roots-bound',
      },
      'create_session_root_lookup_evidence_missing',
      violations,
    );
    _requireEvidenceAssertions(
      evidence,
      'P3-KERNEL-04',
      const <String>{'post-prune-command-receipt-retained'},
      'post_prune_command_receipt_evidence_missing',
      violations,
    );
    _requireEvidenceArtifacts(
      evidence,
      'P3-KERNEL-11',
      const <String>{
        'packages/agent_kernel/test/reducer/snapshot_replay_property_test.dart',
        'packages/agent_io/test/store/prune_compaction_test.dart',
      },
      'snapshot_linkage_evidence_missing',
      violations,
    );
    _requireEvidenceAssertions(
      evidence,
      'P3-KERNEL-11',
      const <String>{'snapshot-prefix-suffix-linkage'},
      'snapshot_linkage_assertion_missing',
      violations,
    );
    return violations;
  } on Object catch (error) {
    return <KernelStoreCompatibilityViolation>[
      KernelStoreCompatibilityViolation(
        'invalid_fixture_coverage',
        error.toString(),
      ),
    ];
  }
}

List<KernelStoreCompatibilityViolation> _validateManifest(
  Directory root,
  Map<String, Object?> manifest,
) {
  final violations = <KernelStoreCompatibilityViolation>[];
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
          './schema/kernel-store-compatibility.schema.json' ||
      manifest['formatVersion'] != 1 ||
      manifest['phase'] != 'phase-3-kernel-store' ||
      manifest['dartSdkConstraint'] != '^3.6.0') {
    violations.add(
      const KernelStoreCompatibilityViolation(
        'invalid_manifest_identity',
        'Expected the pinned Phase 3 Kernel/Store manifest identity.',
      ),
    );
  }
  final implementationCommit =
      _string(manifest['implementationCommit'], 'implementationCommit');
  if (implementationCommit != phase3KernelStoreEvidenceCommit) {
    violations.add(
      KernelStoreCompatibilityViolation(
        'implementation_commit_mismatch',
        'Expected $phase3KernelStoreEvidenceCommit.',
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
      const <String>{'id', 'kind', 'path', 'sha256'},
      location,
    );
    final id = _string(source['id'], '$location.id');
    if (!sourceIds.add(id)) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'duplicate_source_id',
          'Duplicate source $id.',
        ),
      );
    }
    _string(source['kind'], '$location.kind');
    _validatePathDigest(
      root,
      source,
      location,
      'source_artifact_hash_mismatch',
      violations,
    );
  }

  final unsupportedIds = <String>{};
  for (final (index, unsupported) in _indexed(
    _objectList(manifest['knownUnsupported'], 'knownUnsupported'),
  )) {
    final location = 'knownUnsupported[$index]';
    _expectExactKeys(
      unsupported,
      const <String>{'id', 'scope', 'summary'},
      location,
    );
    final id = _string(unsupported['id'], '$location.id');
    if (!unsupportedIds.add(id)) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'duplicate_known_unsupported',
          'Duplicate knownUnsupported $id.',
        ),
      );
    }
    _string(unsupported['scope'], '$location.scope');
    _string(unsupported['summary'], '$location.summary');
  }
  if (!_sameSet(unsupportedIds, phase3KnownUnsupportedIds)) {
    violations.add(
      const KernelStoreCompatibilityViolation(
        'known_unsupported_coverage_mismatch',
        'Manifest must contain the exact approved unsupported inventory.',
      ),
    );
  }

  final claims = _objectList(manifest['claims'], 'claims');
  final claimsById = <String, Map<String, Object?>>{};
  final referencedSources = <String>{};
  final referencedEvidence = <String>{};
  final referencedUnsupported = <String>{};
  for (final (index, claim) in _indexed(claims)) {
    final location = 'claims[$index]';
    _expectExactKeys(
      claim,
      const <String>{
        'id',
        'component',
        'level',
        'summary',
        'sourceRefs',
        'evidenceRef',
        'knownUnsupportedRefs',
      },
      location,
    );
    final id = _string(claim['id'], '$location.id');
    if (claimsById.containsKey(id)) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'duplicate_claim_id',
          'Duplicate claim $id.',
        ),
      );
    }
    claimsById[id] = claim;
    final component = _string(claim['component'], '$location.component');
    if (!const <String>{'kernel', 'store', 'cross-package'}
        .contains(component)) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'invalid_claim_component',
          '$id has invalid component $component.',
        ),
      );
    }
    final level = _string(claim['level'], '$location.level');
    if (!const <String>{'implemented', 'verified'}.contains(level)) {
      violations.add(
        KernelStoreCompatibilityViolation(
          level == 'conformant'
              ? 'conformant_overclaim'
              : 'invalid_claim_level',
          '$id has unsupported claim level $level.',
        ),
      );
    }
    final summary = _string(claim['summary'], '$location.summary');
    if (_overclaimsPowerLoss(summary)) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'power_loss_overclaim',
          '$id overclaims power-loss durability.',
        ),
      );
    }
    for (final sourceRef
        in _stringSet(claim['sourceRefs'], '$location.sourceRefs')) {
      referencedSources.add(sourceRef);
      if (!sourceIds.contains(sourceRef)) {
        violations.add(
          KernelStoreCompatibilityViolation(
            'unknown_source_ref',
            '$id references unknown source $sourceRef.',
          ),
        );
      }
    }
    final evidenceRef = _string(claim['evidenceRef'], '$location.evidenceRef');
    if (!referencedEvidence.add(evidenceRef)) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'reused_evidence_ref',
          'Evidence $evidenceRef is reused.',
        ),
      );
    }
    for (final unsupportedRef in _stringSet(
      claim['knownUnsupportedRefs'],
      '$location.knownUnsupportedRefs',
    )) {
      referencedUnsupported.add(unsupportedRef);
      if (!unsupportedIds.contains(unsupportedRef)) {
        violations.add(
          KernelStoreCompatibilityViolation(
            'unknown_known_unsupported_ref',
            '$id references unknown limitation $unsupportedRef.',
          ),
        );
      }
    }
  }
  if (!_sameSet(claimsById.keys.toSet(), phase3KernelStoreClaimIds)) {
    violations.add(
      const KernelStoreCompatibilityViolation(
        'claim_coverage_mismatch',
        'Manifest must contain the exact approved 28 Phase 3 claims.',
      ),
    );
  }
  if (!_sameSet(referencedSources, sourceIds)) {
    violations.add(
      const KernelStoreCompatibilityViolation(
        'source_reference_closure',
        'Every source must be referenced by at least one claim.',
      ),
    );
  }
  if (!_sameSet(referencedUnsupported, unsupportedIds)) {
    violations.add(
      const KernelStoreCompatibilityViolation(
        'known_unsupported_reference_closure',
        'Every knownUnsupported item must be referenced.',
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
        'scenario',
        'artifacts',
        'verifiedAt',
        'result',
      },
      location,
    );
    final id = _string(item['id'], '$location.id');
    if (!evidenceIds.add(id)) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'duplicate_evidence_id',
          'Duplicate evidence $id.',
        ),
      );
    }
    final claimId = _string(item['claimId'], '$location.claimId');
    if (id != 'EV-$claimId') {
      violations.add(
        KernelStoreCompatibilityViolation(
          'evidence_id_mismatch',
          '$id must be EV-$claimId.',
        ),
      );
    }
    final claim = claimsById[claimId];
    if (claim == null) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'unknown_evidence_claim',
          '$id references unknown claim $claimId.',
        ),
      );
      continue;
    }
    final level = _string(item['claimLevel'], '$location.claimLevel');
    if (level != claim['level']) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'claim_level_mismatch',
          '$id does not match its claim level.',
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
      'peer',
      'scenario',
    ]) {
      _string(item[field], '$location.$field');
    }
    if (item['dartSdkConstraint'] != '^3.6.0') {
      violations.add(
        KernelStoreCompatibilityViolation(
          'dart_sdk_constraint_mismatch',
          '$id must bind Dart ^3.6.0.',
        ),
      );
    }
    if (item['evidenceCommit'] != implementationCommit ||
        item['evidenceCommit'] != phase3KernelStoreEvidenceCommit) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'evidence_commit_mismatch',
          '$id must bind to $phase3KernelStoreEvidenceCommit.',
        ),
      );
    }
    final verifiedAt = DateTime.tryParse(
      _string(item['verifiedAt'], '$location.verifiedAt'),
    );
    if (verifiedAt == null || !verifiedAt.isUtc) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'invalid_verified_at',
          '$id verifiedAt must be UTC.',
        ),
      );
    }
    if (item['platform'] != 'macos-arm64') {
      violations.add(
        KernelStoreCompatibilityViolation(
          'unverified_platform',
          '$id claims an unexecuted platform.',
        ),
      );
    }
    final artifacts = _objectList(item['artifacts'], '$location.artifacts');
    if (artifacts.isEmpty) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'missing_evidence_artifact',
          '$id must include an artifact.',
        ),
      );
    }
    for (final (artifactIndex, artifact) in _indexed(artifacts)) {
      _expectExactKeys(
        artifact,
        const <String>{'path', 'sha256'},
        '$location.artifacts[$artifactIndex]',
      );
      _validatePathDigest(
        root,
        artifact,
        '$location.artifacts[$artifactIndex]',
        'evidence_artifact_hash_mismatch',
        violations,
      );
    }
    final result = _object(item['result'], '$location.result');
    _expectExactKeys(
      result,
      const <String>{'status', 'assertions'},
      '$location.result',
    );
    if (result['status'] != 'passed' ||
        _stringSet(result['assertions'], '$location.result.assertions')
            .isEmpty) {
      violations.add(
        KernelStoreCompatibilityViolation(
          'invalid_evidence_result',
          '$id must record a passed result with assertions.',
        ),
      );
    }
    if (level == 'verified') {
      final validTuple = claim['component'] == 'store' &&
          const <String>{
            'child-process-crash',
            'child-process-lock',
          }.contains(item['kind']) &&
          item['role'] == 'store-writer' &&
          item['transport'] == 'os-process' &&
          item['peer'] == 'dart-child-process';
      if (!validTuple) {
        violations.add(
          KernelStoreCompatibilityViolation(
            'invalid_verified_evidence',
            '$id verified Store evidence requires a real child-process tuple.',
          ),
        );
      }
    }
  }
  if (!_sameSet(evidenceIds, referencedEvidence)) {
    violations.add(
      const KernelStoreCompatibilityViolation(
        'evidence_reference_closure',
        'Claims and evidence must form an exact closed set.',
      ),
    );
  }
  violations.addAll(
    validateKernelStoreFixtureCoverage(root: root, manifest: manifest),
  );
  return violations;
}

void _requireEvidenceArtifacts(
  List<Map<String, Object?>> evidence,
  String claimId,
  Set<String> required,
  String code,
  List<KernelStoreCompatibilityViolation> violations,
) {
  final matches = evidence.where((item) => item['claimId'] == claimId).toList();
  if (matches.length != 1) {
    violations.add(
      KernelStoreCompatibilityViolation(code, '$claimId evidence is absent.'),
    );
    return;
  }
  final paths = <String>{
    for (final artifact
        in _objectList(matches.single['artifacts'], '$claimId.artifacts'))
      _string(artifact['path'], '$claimId.artifact.path'),
  };
  if (!paths.containsAll(required)) {
    violations.add(
      KernelStoreCompatibilityViolation(
        code,
        '$claimId must bind ${required.join(', ')}.',
      ),
    );
  }
}

void _requireEvidenceAssertions(
  List<Map<String, Object?>> evidence,
  String claimId,
  Set<String> required,
  String code,
  List<KernelStoreCompatibilityViolation> violations,
) {
  final matches = evidence.where((item) => item['claimId'] == claimId).toList();
  if (matches.length != 1) {
    violations.add(
      KernelStoreCompatibilityViolation(code, '$claimId evidence is absent.'),
    );
    return;
  }
  final result = _object(matches.single['result'], '$claimId.result');
  final assertions = _stringSet(
    result['assertions'],
    '$claimId.result.assertions',
  );
  if (!assertions.containsAll(required)) {
    violations.add(
      KernelStoreCompatibilityViolation(
        code,
        '$claimId must assert ${required.join(', ')}.',
      ),
    );
  }
}

void _validatePathDigest(
  Directory root,
  Map<String, Object?> digest,
  String location,
  String mismatchCode,
  List<KernelStoreCompatibilityViolation> violations,
) {
  final path = _string(digest['path'], '$location.path');
  final expected = _string(digest['sha256'], '$location.sha256');
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
    throw FormatException('$location.sha256 is not lowercase SHA-256.');
  }
  final file = _containedFile(root, path);
  if (!file.existsSync()) {
    violations.add(
      KernelStoreCompatibilityViolation(
        'missing_evidence_artifact',
        '$location is missing $path.',
      ),
    );
    return;
  }
  final actual = sha256.convert(file.readAsBytesSync()).toString();
  if (actual != expected) {
    violations.add(
      KernelStoreCompatibilityViolation(
        mismatchCode,
        '$location digest differs for $path.',
      ),
    );
  }
}

bool _overclaimsPowerLoss(String value) {
  final normalized = value.toLowerCase();
  return normalized.contains('powerlossdurable') ||
      normalized.contains('power-loss durable') ||
      normalized.contains('raw-device power-loss supported');
}

File _containedFile(Directory root, String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.contains(r'\') ||
      path.split('/').any((segment) => segment.isEmpty || segment == '..')) {
    throw FormatException('Path is not a contained repository path: $path');
  }
  final candidate = File.fromUri(root.uri.resolve(path));
  final rootPath = root.resolveSymbolicLinksSync();
  final parent = candidate.parent;
  if (!parent.existsSync()) {
    throw FormatException('Artifact parent does not exist: $path');
  }
  final parentPath = parent.resolveSymbolicLinksSync();
  if (parentPath != rootPath &&
      !parentPath.startsWith('$rootPath${Platform.pathSeparator}')) {
    throw FormatException('Artifact escapes the repository root: $path');
  }
  return candidate;
}

Map<String, Object?> _object(Object? value, String location) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$location must be an object.');
  }
  return value;
}

List<Map<String, Object?>> _objectList(Object? value, String location) {
  if (value is! List<Object?>) {
    throw FormatException('$location must be a list.');
  }
  return <Map<String, Object?>>[
    for (var index = 0; index < value.length; index++)
      _object(value[index], '$location[$index]'),
  ];
}

String _string(Object? value, String location) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$location must be a non-empty string.');
  }
  return value;
}

Set<String> _stringSet(Object? value, String location) {
  if (value is! List<Object?>) {
    throw FormatException('$location must be a list.');
  }
  final result = <String>{};
  for (var index = 0; index < value.length; index++) {
    final item = _string(value[index], '$location[$index]');
    if (!result.add(item)) {
      throw FormatException('$location contains duplicate $item.');
    }
  }
  return result;
}

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String location,
) {
  if (!_sameSet(value.keys.toSet(), expected)) {
    throw FormatException('$location has an unexpected object shape.');
  }
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

Iterable<(int, T)> _indexed<T>(List<T> values) sync* {
  for (var index = 0; index < values.length; index++) {
    yield (index, values[index]);
  }
}
