import 'dart:convert';
import 'dart:io';

const phase1TargetRepository = 'https://github.com/vercel/ai';
const phase1TargetTag = 'ai@7.0.35';
const phase1TargetCommit = '799faf71e05a7d580914ad94d943d28c0400554c';
const phase1PeerVersion = 'phase1-ai-core-peer-v1';
const phase1RealPeerVersions = <String, String>{
  'ai-core-peer': phase1PeerVersion,
  'openai-peer': 'phase1-openai-peer-v1',
  'openai-compatible-peer': 'phase1-openai-compatible-peer-v1',
  'anthropic-peer': 'phase1-anthropic-peer-v1',
};
const phase1DartSdkConstraint = '^3.6.0';
const phase1EvidenceCommit = 'b0ef03a5852a83d1630d793f498a622f83c9d167';

const phase1FixtureIds = <String>{
  'P1-PROVIDER-01',
  'P1-PROVIDER-02',
  'P1-PROVIDER-03',
  'P1-PROVIDER-04',
  'P1-PROVIDER-05',
  'P1-PROVIDER-06',
  'P1-PROVIDER-07',
  'P1-PROVIDER-08',
  'P1-UTIL-01',
  'P1-UTIL-02',
  'P1-UTIL-03',
  'P1-UTIL-04',
  'P1-UTIL-05',
  'P1-UTIL-06',
  'P1-UTIL-07',
  'P1-UTIL-08',
  'P1-CORE-01',
  'P1-CORE-02',
  'P1-CORE-03',
  'P1-CORE-04',
  'P1-CORE-05',
  'P1-CORE-06',
  'P1-CORE-07',
  'P1-CORE-08',
  'P1-CORE-09',
  'P1-CORE-10',
  'P1-CORE-11',
  'P1-CORE-12',
  'P1-CORE-13',
  'P1-CORE-14',
  'P1-CORE-15',
  'P1-CORE-16',
  'P1-OPENAI-01',
  'P1-OPENAI-02',
  'P1-OPENAI-03',
  'P1-OPENAI-04',
  'P1-OPENAI-05',
  'P1-OPENAI-06',
  'P1-OPENAI-07',
  'P1-OPENAI-08',
  'P1-COMPAT-01',
  'P1-COMPAT-02',
  'P1-COMPAT-03',
  'P1-COMPAT-04',
  'P1-ANTHROPIC-01',
  'P1-ANTHROPIC-02',
  'P1-ANTHROPIC-03',
  'P1-ANTHROPIC-04',
  'P1-ANTHROPIC-05',
  'P1-ANTHROPIC-06',
  'P1-ANTHROPIC-07',
  'P1-ANTHROPIC-08',
  'P1-CROSS-01',
  'P1-CROSS-02',
  'P1-CROSS-03',
  'P1-CROSS-04',
  'P1-CROSS-05',
};

const phase1NotApplicableBoundaries = <String, String>{
  'P1-NA-01': 'javascript-callable-object',
  'P1-NA-02': 'node-express-server-response',
  'P1-NA-03': 'typescript-zod-ecosystem',
  'P1-NA-04': 'typescript-type-system',
};

const _sourcePins = <String, _SourcePin>{
  'pigcode_ai_provider': _SourcePin(
    upstreamPackage: '@ai-sdk/provider',
    version: '4.0.3',
    tree: 'e317bb78b50fd0bdd6e0f6968246b3bc20835265',
    upstreamDirectory: 'provider',
    dartDirectory: 'provider',
  ),
  'pigcode_ai_provider_utils': _SourcePin(
    upstreamPackage: '@ai-sdk/provider-utils',
    version: '5.0.12',
    tree: 'b14c493fddd3c9de574e794c5e688f417d55bb9f',
    upstreamDirectory: 'provider-utils',
    dartDirectory: 'provider_utils',
  ),
  'pigcode_ai': _SourcePin(
    upstreamPackage: 'ai',
    version: '7.0.35',
    tree: '4007b95ee6c90a1caa03b5f765886990f8526f38',
    upstreamDirectory: 'ai',
    dartDirectory: 'ai',
  ),
  'pigcode_ai_openai': _SourcePin(
    upstreamPackage: '@ai-sdk/openai',
    version: '4.0.18',
    tree: '2166f24dcc1fc273374bad00c2d8f63910c1a7c7',
    upstreamDirectory: 'openai',
    dartDirectory: 'openai',
  ),
  'pigcode_ai_openai_compatible': _SourcePin(
    upstreamPackage: '@ai-sdk/openai-compatible',
    version: '3.0.14',
    tree: 'daea26741bc9737bd0fe727c48f142b32346c8e8',
    upstreamDirectory: 'openai-compatible',
    dartDirectory: 'openai_compatible',
  ),
  'pigcode_ai_anthropic': _SourcePin(
    upstreamPackage: '@ai-sdk/anthropic',
    version: '4.0.18',
    tree: '67d1d5804f178fb74f8ec7b49d9d82f2ce562f5c',
    upstreamDirectory: 'anthropic',
    dartDirectory: 'anthropic',
  ),
  'workspace': _SourcePin(
    upstreamPackage: 'ai',
    version: '7.0.35',
    tree: '4007b95ee6c90a1caa03b5f765886990f8526f38',
    upstreamDirectory: 'ai',
    dartDirectory: '',
  ),
};

const _crossRootTestPaths = <String>{
  'tool/test/compatibility_manifest_test.dart',
  'tool/test/workspace_contract_test.dart',
  'tool/test/ai_core_cross_scripted_peer_test.dart',
  'tool/test/ai_core_cross_process_test.dart',
};

const _manifestKeys = <String>{'manifestVersion', 'claims', 'notApplicable'};
const _claimKeys = <String>{
  'claimId',
  'package',
  'surface',
  'status',
  'source',
  'fixtureIds',
  'upstreamRefs',
  'dartTests',
  'scriptedPeerTests',
  'realProcessTests',
  'notes',
};
const _sourceKeys = <String>{
  'repository',
  'tag',
  'commit',
  'package',
  'packageVersion',
  'tree',
};
const _upstreamRefKeys = <String>{'commit', 'path', 'fixtureIds'};
const _dartTestRefKeys = <String>{'path', 'fixtureIds'};
const _evidenceRefKeys = <String>{
  'path',
  'fixtureIds',
  'role',
  'transport',
  'version',
  'capabilityProfile',
  'platform',
  'peer',
  'peerBinaryHash',
  'dartSdkConstraint',
  'evidenceCommit',
};
const _notApplicableKeys = <String>{
  'id',
  'boundary',
  'upstreamCommit',
  'upstreamPath',
  'reason',
};
const _inventoryKeys = <String>{
  'inventoryVersion',
  'repository',
  'tag',
  'commit',
  'packages',
};
const _inventoryPackageKeys = <String>{
  'dartPackage',
  'upstreamPackage',
  'packageVersion',
  'tree',
  'root',
  'paths',
};

final _claimIdPattern = RegExp(r'^P1-[A-Z]+-CLAIM-[0-9]{2}$');
final _sha40Pattern = RegExp(r'^[a-f0-9]{40}$');
final _fixtureMetadataPattern = RegExp(
  r'Compatibility fixture \((unit|scripted-peer|real-process)\):\s*'
  r'(P1-[A-Z]+-[0-9]{2})',
);

final class CompatibilityViolation {
  const CompatibilityViolation(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

List<CompatibilityViolation> validateCompatibilityManifest({
  required Directory root,
  required File manifestFile,
  required File schemaFile,
  required File inventoryFile,
}) {
  final violations = <CompatibilityViolation>[];
  final schema = _readJsonObject(schemaFile, 'schema', violations);
  final manifest = _readJsonObject(manifestFile, 'manifest', violations);
  final inventoryObject = _readJsonObject(
    inventoryFile,
    'upstream_inventory',
    violations,
  );
  if (schema == null || manifest == null || inventoryObject == null) {
    return violations;
  }

  _validateSchemaFixtureSet(schema, violations);
  final inventory = _validateUpstreamInventory(inventoryObject, violations);
  _validateObjectKeys(
    manifest,
    allowed: _manifestKeys,
    required: _manifestKeys,
    location: 'manifest',
    violations: violations,
  );
  if (manifest['manifestVersion'] != 1) {
    violations.add(
      const CompatibilityViolation(
        'invalid_manifest_version',
        'manifestVersion must be 1.',
      ),
    );
  }

  final claims = _objectList(
    manifest['claims'],
    location: 'manifest.claims',
    violations: violations,
  );
  final fixtureIds = <String>{};
  final claimIds = <String>{};
  if (claims != null) {
    for (var index = 0; index < claims.length; index += 1) {
      _validateClaim(
        root,
        claims[index],
        index,
        fixtureIds,
        claimIds,
        inventory,
        violations,
      );
    }
  }
  if (!_setsEqual(fixtureIds, phase1FixtureIds)) {
    violations.add(
      CompatibilityViolation(
        'manifest_fixture_set_mismatch',
        _setDifferenceMessage(
          'Manifest fixture IDs',
          fixtureIds,
          phase1FixtureIds,
        ),
      ),
    );
  }

  _validateNotApplicable(manifest['notApplicable'], inventory, violations);
  return violations;
}

List<CompatibilityViolation> validateFixtureCoverage(Directory root) {
  final violations = <CompatibilityViolation>[];
  final coverage = <String, Set<String>>{
    'unit': <String>{},
    'scripted-peer': <String>{},
    'real-process': <String>{},
  };

  final files = <File>[];
  for (final relativeDirectory in const <String>['packages', 'tool/test']) {
    final directory = Directory.fromUri(
      root.uri.resolve('$relativeDirectory/'),
    );
    if (!directory.existsSync()) {
      continue;
    }
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(entity);
      }
    }
  }

  for (final file in files) {
    String contents;
    try {
      contents = file.readAsStringSync();
    } on FileSystemException {
      violations.add(
        CompatibilityViolation(
          'fixture_scan_failed',
          'Unable to read fixture test ${file.path}.',
        ),
      );
      continue;
    } on FormatException {
      violations.add(
        CompatibilityViolation(
          'fixture_scan_failed',
          'Fixture test is not valid UTF-8: ${file.path}.',
        ),
      );
      continue;
    }
    for (final match in _fixtureMetadataPattern.allMatches(contents)) {
      coverage[match.group(1)]!.add(match.group(2)!);
    }
  }

  const codes = <String, String>{
    'unit': 'unit_fixture_set_mismatch',
    'scripted-peer': 'scripted_peer_fixture_set_mismatch',
    'real-process': 'real_process_fixture_set_mismatch',
  };
  for (final entry in coverage.entries) {
    if (!_setsEqual(entry.value, phase1FixtureIds)) {
      violations.add(
        CompatibilityViolation(
          codes[entry.key]!,
          _setDifferenceMessage(
            '${entry.key} fixture IDs',
            entry.value,
            phase1FixtureIds,
          ),
        ),
      );
    }
  }
  return violations;
}

Map<String, Set<String>> _validateUpstreamInventory(
  Map<String, Object?> inventory,
  List<CompatibilityViolation> violations,
) {
  _validateObjectKeys(
    inventory,
    allowed: _inventoryKeys,
    required: _inventoryKeys,
    location: 'upstreamInventory',
    violations: violations,
  );
  if (inventory['inventoryVersion'] != 1 ||
      inventory['repository'] != phase1TargetRepository ||
      inventory['tag'] != phase1TargetTag ||
      inventory['commit'] != phase1TargetCommit) {
    violations.add(
      const CompatibilityViolation(
        'invalid_upstream_inventory',
        'Upstream inventory header does not match the fixed target.',
      ),
    );
  }
  final records = _objectList(
    inventory['packages'],
    location: 'upstreamInventory.packages',
    violations: violations,
  );
  final result = <String, Set<String>>{};
  if (records == null) {
    return result;
  }
  final expectedPackages =
      _sourcePins.keys.where((package) => package != 'workspace').toSet();
  for (var index = 0; index < records.length; index += 1) {
    final record = records[index];
    final location = 'upstreamInventory.packages[$index]';
    _validateObjectKeys(
      record,
      allowed: _inventoryPackageKeys,
      required: _inventoryPackageKeys,
      location: location,
      violations: violations,
    );
    final dartPackage = record['dartPackage'];
    final pin = dartPackage is String ? _sourcePins[dartPackage] : null;
    if (pin == null || dartPackage == 'workspace') {
      violations.add(
        CompatibilityViolation(
          'invalid_upstream_inventory',
          '$location.dartPackage is not one of the six fixed packages.',
        ),
      );
      continue;
    }
    if (result.containsKey(dartPackage)) {
      violations.add(
        CompatibilityViolation(
          'invalid_upstream_inventory',
          'Duplicate upstream inventory package: $dartPackage.',
        ),
      );
      continue;
    }
    if (record['upstreamPackage'] != pin.upstreamPackage ||
        record['packageVersion'] != pin.version ||
        record['tree'] != pin.tree ||
        record['root'] != pin.upstreamRoot) {
      violations.add(
        CompatibilityViolation(
          'invalid_upstream_inventory',
          '$location does not match the fixed package/version/tree/root pin.',
        ),
      );
    }
    final paths = _stringList(
      record['paths'],
      location: '$location.paths',
      violations: violations,
    );
    if (paths == null) {
      continue;
    }
    final sortedPaths = paths.toList()..sort();
    final pathSet = paths.toSet();
    if (paths.isEmpty ||
        pathSet.length != paths.length ||
        !_listsEqual(paths, sortedPaths) ||
        paths.any(
          (path) =>
              !_isCanonicalRepoPath(path) ||
              !path.startsWith('${pin.upstreamRoot}/'),
        )) {
      violations.add(
        CompatibilityViolation(
          'invalid_upstream_inventory',
          '$location.paths must be a non-empty, canonical, sorted, unique '
              'snapshot below ${pin.upstreamRoot}/.',
        ),
      );
    }
    result[dartPackage as String] = pathSet;
  }
  if (!_setsEqual(result.keys.toSet(), expectedPackages)) {
    violations.add(
      CompatibilityViolation(
        'invalid_upstream_inventory',
        _setDifferenceMessage(
          'Upstream inventory packages',
          result.keys.toSet(),
          expectedPackages,
        ),
      ),
    );
  }
  final aiPaths = result['pigcode_ai'];
  if (aiPaths != null) {
    result['workspace'] = aiPaths;
  }
  return result;
}

void _validateSchemaFixtureSet(
  Map<String, Object?> schema,
  List<CompatibilityViolation> violations,
) {
  final definitions = _object(schema[r'$defs']);
  final fixtureDefinition = _object(definitions?['fixtureId']);
  final values = _stringList(
    fixtureDefinition?['enum'],
    location: r'schema.$defs.fixtureId.enum',
    violations: violations,
  );
  final fixtureIds = values?.toSet() ?? <String>{};
  if (values == null ||
      fixtureIds.length != values.length ||
      !_setsEqual(fixtureIds, phase1FixtureIds)) {
    violations.add(
      CompatibilityViolation(
        'schema_fixture_set_mismatch',
        _setDifferenceMessage(
          'Schema fixture IDs',
          fixtureIds,
          phase1FixtureIds,
        ),
      ),
    );
  }
}

void _validateClaim(
  Directory root,
  Map<String, Object?> claim,
  int index,
  Set<String> manifestFixtureIds,
  Set<String> claimIds,
  Map<String, Set<String>> inventory,
  List<CompatibilityViolation> violations,
) {
  final location = 'manifest.claims[$index]';
  _validateObjectKeys(
    claim,
    allowed: _claimKeys,
    required: _claimKeys,
    location: location,
    violations: violations,
  );

  final claimId = claim['claimId'];
  if (claimId is! String || !_claimIdPattern.hasMatch(claimId)) {
    violations.add(
      CompatibilityViolation(
        'invalid_claim_id',
        '$location.claimId must be a stable P1 claim ID.',
      ),
    );
  } else if (!claimIds.add(claimId)) {
    violations.add(
      CompatibilityViolation(
        'duplicate_claim_id',
        'Duplicate claimId: $claimId.',
      ),
    );
  }

  final package = claim['package'];
  final pin = package is String ? _sourcePins[package] : null;
  if (pin == null) {
    violations.add(
      CompatibilityViolation(
        'invalid_claim_package',
        '$location.package must name one of the six Dart packages or workspace.',
      ),
    );
  }
  if (!_isNonEmptyString(claim['surface'])) {
    violations.add(
      CompatibilityViolation(
        'invalid_surface',
        '$location.surface must be non-empty.',
      ),
    );
  }
  if (!_isNonEmptyString(claim['notes'])) {
    violations.add(
      CompatibilityViolation(
        'invalid_notes',
        '$location.notes must be non-empty.',
      ),
    );
  }

  final status = claim['status'];
  if (status == 'unsupported') {
    violations.add(
      CompatibilityViolation(
        'unsupported_status',
        '$location may not use unsupported.',
      ),
    );
  } else if (status != 'implemented' && status != 'verified') {
    violations.add(
      CompatibilityViolation(
        'invalid_status',
        '$location.status must be implemented or verified.',
      ),
    );
  }

  final fixtureIds = _fixtureIdList(
        claim['fixtureIds'],
        location: '$location.fixtureIds',
        violations: violations,
      ) ??
      <String>[];
  for (final fixtureId in fixtureIds) {
    if (!manifestFixtureIds.add(fixtureId)) {
      violations.add(
        CompatibilityViolation(
          'duplicate_fixture_id',
          'Fixture ID appears more than once in the manifest: $fixtureId.',
        ),
      );
    }
    if (package is String &&
        _packageForFixture(fixtureId) != null &&
        _packageForFixture(fixtureId) != package) {
      violations.add(
        CompatibilityViolation(
          'fixture_package_mismatch',
          '$fixtureId cannot be claimed by $package.',
        ),
      );
    }
  }

  if (pin != null) {
    _validateSource(claim['source'], pin, location, violations);
    _validateUpstreamRefs(
      claim['upstreamRefs'],
      pin,
      inventory[package] ?? const <String>{},
      fixtureIds.toSet(),
      location,
      violations,
    );
    _validateDartTestRefs(
      root,
      claim['dartTests'],
      package as String,
      pin,
      fixtureIds.toSet(),
      location,
      violations,
    );
    _validateEvidenceRefs(
      root,
      claim['scriptedPeerTests'],
      package,
      pin,
      fixtureIds.toSet(),
      location,
      kind: _EvidenceKind.scriptedPeer,
      requireCompleteCoverage: status == 'verified',
      violations: violations,
    );
    _validateEvidenceRefs(
      root,
      claim['realProcessTests'],
      package,
      pin,
      fixtureIds.toSet(),
      location,
      kind: _EvidenceKind.realProcess,
      requireCompleteCoverage: status == 'verified',
      violations: violations,
    );
  }
}

void _validateSource(
  Object? value,
  _SourcePin pin,
  String claimLocation,
  List<CompatibilityViolation> violations,
) {
  final source = _object(value);
  if (source == null) {
    violations.add(
      CompatibilityViolation(
        'invalid_source',
        '$claimLocation.source must be an object.',
      ),
    );
    return;
  }
  _validateObjectKeys(
    source,
    allowed: _sourceKeys,
    required: _sourceKeys,
    location: '$claimLocation.source',
    violations: violations,
  );
  final expected = <String, String>{
    'repository': phase1TargetRepository,
    'tag': phase1TargetTag,
    'commit': phase1TargetCommit,
    'package': pin.upstreamPackage,
    'packageVersion': pin.version,
    'tree': pin.tree,
  };
  for (final entry in expected.entries) {
    if (source[entry.key] != entry.value) {
      violations.add(
        CompatibilityViolation(
          'invalid_source',
          '$claimLocation.source.${entry.key} must be ${entry.value}.',
        ),
      );
    }
  }
}

void _validateUpstreamRefs(
  Object? value,
  _SourcePin pin,
  Set<String> inventoryPaths,
  Set<String> claimFixtureIds,
  String claimLocation,
  List<CompatibilityViolation> violations,
) {
  final refs = _objectList(
    value,
    location: '$claimLocation.upstreamRefs',
    violations: violations,
  );
  if (refs == null || refs.isEmpty) {
    violations.add(
      CompatibilityViolation(
        'upstream_coverage_mismatch',
        '$claimLocation.upstreamRefs must cover every claim fixture.',
      ),
    );
    return;
  }
  final covered = <String>{};
  for (var index = 0; index < refs.length; index += 1) {
    final ref = refs[index];
    final location = '$claimLocation.upstreamRefs[$index]';
    _validateObjectKeys(
      ref,
      allowed: _upstreamRefKeys,
      required: _upstreamRefKeys,
      location: location,
      violations: violations,
    );
    if (ref['commit'] != phase1TargetCommit) {
      violations.add(
        CompatibilityViolation(
          'invalid_upstream_ref',
          '$location.commit must be $phase1TargetCommit.',
        ),
      );
    }
    final path = ref['path'];
    if (path is! String ||
        !_isCanonicalRepoPath(path) ||
        !path.startsWith('packages/${pin.upstreamDirectory}/')) {
      violations.add(
        CompatibilityViolation(
          'invalid_upstream_path',
          '$location.path must be a canonical path under '
              'packages/${pin.upstreamDirectory}/.',
        ),
      );
    } else if (!inventoryPaths.contains(path)) {
      violations.add(
        CompatibilityViolation(
          'upstream_path_not_in_inventory',
          '$location.path is absent from the fixed upstream tree inventory: '
              '$path.',
        ),
      );
    }
    final ids = _fixtureIdList(
      ref['fixtureIds'],
      location: '$location.fixtureIds',
      violations: violations,
    );
    if (ids != null) {
      covered.addAll(ids);
      _rejectOutOfClaimIds(ids, claimFixtureIds, location, violations);
    }
  }
  if (!_setsEqual(covered, claimFixtureIds)) {
    violations.add(
      CompatibilityViolation(
        'upstream_coverage_mismatch',
        _setDifferenceMessage(
          '$claimLocation upstream fixture IDs',
          covered,
          claimFixtureIds,
        ),
      ),
    );
  }
}

void _validateDartTestRefs(
  Directory root,
  Object? value,
  String package,
  _SourcePin pin,
  Set<String> claimFixtureIds,
  String claimLocation,
  List<CompatibilityViolation> violations,
) {
  final refs = _objectList(
    value,
    location: '$claimLocation.dartTests',
    violations: violations,
  );
  if (refs == null || refs.isEmpty) {
    violations.add(
      CompatibilityViolation(
        'dart_test_coverage_mismatch',
        '$claimLocation.dartTests must cover every claim fixture.',
      ),
    );
    return;
  }
  final covered = <String>{};
  for (var index = 0; index < refs.length; index += 1) {
    final ref = refs[index];
    final location = '$claimLocation.dartTests[$index]';
    _validateObjectKeys(
      ref,
      allowed: _dartTestRefKeys,
      required: _dartTestRefKeys,
      location: location,
      violations: violations,
    );
    final ids = _fixtureIdList(
      ref['fixtureIds'],
      location: '$location.fixtureIds',
      violations: violations,
    );
    if (ids != null) {
      covered.addAll(ids);
      _rejectOutOfClaimIds(ids, claimFixtureIds, location, violations);
      _validateTestPathAndTokens(
        root,
        ref['path'],
        ids,
        package,
        pin,
        location,
        metadataKind: 'unit',
        violations: violations,
      );
    }
  }
  if (!_setsEqual(covered, claimFixtureIds)) {
    violations.add(
      CompatibilityViolation(
        'dart_test_coverage_mismatch',
        _setDifferenceMessage(
          '$claimLocation Dart test fixture IDs',
          covered,
          claimFixtureIds,
        ),
      ),
    );
  }
}

void _validateEvidenceRefs(
  Directory root,
  Object? value,
  String package,
  _SourcePin pin,
  Set<String> claimFixtureIds,
  String claimLocation, {
  required _EvidenceKind kind,
  required bool requireCompleteCoverage,
  required List<CompatibilityViolation> violations,
}) {
  final field = kind == _EvidenceKind.scriptedPeer
      ? 'scriptedPeerTests'
      : 'realProcessTests';
  final code = kind == _EvidenceKind.scriptedPeer
      ? 'scripted_peer_coverage_mismatch'
      : 'real_process_coverage_mismatch';
  final metadataKind =
      kind == _EvidenceKind.scriptedPeer ? 'scripted-peer' : 'real-process';
  final refs = _objectList(
    value,
    location: '$claimLocation.$field',
    violations: violations,
  );
  if (refs == null) {
    if (requireCompleteCoverage) {
      violations.add(
        CompatibilityViolation(
          code,
          '$claimLocation.$field must cover every verified fixture.',
        ),
      );
    }
    return;
  }

  final covered = <String>{};
  for (var index = 0; index < refs.length; index += 1) {
    final ref = refs[index];
    final location = '$claimLocation.$field[$index]';
    _validateObjectKeys(
      ref,
      allowed: _evidenceRefKeys,
      required: _evidenceRefKeys,
      location: location,
      violations: violations,
    );
    final ids = _fixtureIdList(
      ref['fixtureIds'],
      location: '$location.fixtureIds',
      violations: violations,
    );
    if (ids != null) {
      covered.addAll(ids);
      _rejectOutOfClaimIds(ids, claimFixtureIds, location, violations);
      _validateTestPathAndTokens(
        root,
        ref['path'],
        ids,
        package,
        pin,
        location,
        metadataKind: metadataKind,
        violations: violations,
      );
    }
    _validateEvidenceTuple(ref, location, kind, violations);
  }
  if (requireCompleteCoverage && !_setsEqual(covered, claimFixtureIds)) {
    violations.add(
      CompatibilityViolation(
        code,
        _setDifferenceMessage(
          '$claimLocation $field fixture IDs',
          covered,
          claimFixtureIds,
        ),
      ),
    );
  }
}

void _validateEvidenceTuple(
  Map<String, Object?> ref,
  String location,
  _EvidenceKind kind,
  List<CompatibilityViolation> violations,
) {
  for (final key in const <String>{
    'role',
    'capabilityProfile',
    'platform',
    'peer',
  }) {
    if (!_isNonEmptyString(ref[key])) {
      violations.add(
        CompatibilityViolation(
          'invalid_evidence_tuple',
          '$location.$key must be non-empty.',
        ),
      );
    }
  }
  final transport = ref['transport'];
  final allowedTransports = kind == _EvidenceKind.scriptedPeer
      ? const <String>{'in-process'}
      : const <String>{
          'stdio',
          'loopback-http',
          'loopback-sse',
          'loopback-websocket',
        };
  if (transport is! String || !allowedTransports.contains(transport)) {
    violations.add(
      CompatibilityViolation(
        'invalid_evidence_tuple',
        '$location.transport is not valid for ${kind.name}.',
      ),
    );
  }

  final version = ref['version'];
  if (version is! String || _isMutableVersion(version)) {
    violations.add(
      CompatibilityViolation(
        'mutable_evidence_version',
        '$location.version must be immutable.',
      ),
    );
  } else if (kind == _EvidenceKind.realProcess) {
    final peer = ref['peer'];
    final expectedVersion =
        peer is String ? phase1RealPeerVersions[peer] : null;
    if (expectedVersion == null || version != expectedVersion) {
      violations.add(
        CompatibilityViolation(
          'invalid_evidence_tuple',
          '$location.version must match the fixed version for peer $peer.',
        ),
      );
    }
  }
  final peerBinaryHash = ref['peerBinaryHash'];
  if (peerBinaryHash is! String || !_sha40Pattern.hasMatch(peerBinaryHash)) {
    violations.add(
      CompatibilityViolation(
        'invalid_evidence_tuple',
        '$location.peerBinaryHash must be a lowercase Git source blob hash.',
      ),
    );
  }
  if (ref['dartSdkConstraint'] != phase1DartSdkConstraint) {
    violations.add(
      CompatibilityViolation(
        'invalid_evidence_tuple',
        '$location.dartSdkConstraint must be $phase1DartSdkConstraint.',
      ),
    );
  }
  final evidenceCommit = ref['evidenceCommit'];
  if (evidenceCommit is! String || !_sha40Pattern.hasMatch(evidenceCommit)) {
    violations.add(
      CompatibilityViolation(
        'invalid_evidence_tuple',
        '$location.evidenceCommit must be a lowercase 40-character commit.',
      ),
    );
  } else if (evidenceCommit != phase1EvidenceCommit) {
    violations.add(
      CompatibilityViolation(
        'evidence_commit_mismatch',
        '$location.evidenceCommit must match the Phase 1 implementation '
            'merge commit $phase1EvidenceCommit.',
      ),
    );
  }
}

void _validateTestPathAndTokens(
  Directory root,
  Object? pathValue,
  List<String> fixtureIds,
  String package,
  _SourcePin pin,
  String location, {
  required String metadataKind,
  required List<CompatibilityViolation> violations,
}) {
  if (pathValue is! String || !_isAllowedTestPath(pathValue, package, pin)) {
    violations.add(
      CompatibilityViolation(
        'invalid_test_path',
        '$location.path is not an approved test path.',
      ),
    );
    return;
  }
  final file = _regularContainedFile(root, pathValue);
  if (file == null) {
    violations.add(
      CompatibilityViolation(
        'missing_test_path',
        '$location.path does not name a regular test file: $pathValue.',
      ),
    );
    return;
  }
  String contents;
  try {
    contents = file.readAsStringSync();
  } on FileSystemException {
    violations.add(
      CompatibilityViolation(
        'missing_test_path',
        '$location.path could not be read: $pathValue.',
      ),
    );
    return;
  } on FormatException {
    violations.add(
      CompatibilityViolation(
        'missing_test_path',
        '$location.path is not valid UTF-8: $pathValue.',
      ),
    );
    return;
  }
  for (final fixtureId in fixtureIds) {
    if (!_containsFixtureToken(contents, metadataKind, fixtureId)) {
      violations.add(
        CompatibilityViolation(
          'missing_fixture_token',
          '$pathValue does not bind $fixtureId as $metadataKind evidence.',
        ),
      );
    }
  }
}

bool _containsFixtureToken(
  String contents,
  String metadataKind,
  String fixtureId,
) {
  if (contents.contains('Compatibility fixture ($metadataKind): $fixtureId')) {
    return true;
  }
  final escapedId = RegExp.escape(fixtureId);
  return RegExp(
    "(?:test|group)\\s*\\(\\s*[\"']"
    "[^\"']*$escapedId[^\"']*[\"']",
  ).hasMatch(contents);
}

bool _isAllowedTestPath(String path, String package, _SourcePin pin) {
  if (!_isCanonicalRepoPath(path) || !path.endsWith('_test.dart')) {
    return false;
  }
  if (package == 'workspace') {
    return _crossRootTestPaths.contains(path);
  }
  return path.startsWith('packages/${pin.dartDirectory}/test/');
}

void _validateNotApplicable(
  Object? value,
  Map<String, Set<String>> inventory,
  List<CompatibilityViolation> violations,
) {
  final records = _objectList(
    value,
    location: 'manifest.notApplicable',
    violations: violations,
  );
  if (records == null) {
    violations.add(
      const CompatibilityViolation(
        'not_applicable_set_mismatch',
        'notApplicable must contain the fixed four records.',
      ),
    );
    return;
  }
  final actual = <String, String>{};
  for (var index = 0; index < records.length; index += 1) {
    final record = records[index];
    final location = 'manifest.notApplicable[$index]';
    _validateObjectKeys(
      record,
      allowed: _notApplicableKeys,
      required: _notApplicableKeys,
      location: location,
      violations: violations,
    );
    final id = record['id'];
    final boundary = record['boundary'];
    if (id is String && boundary is String) {
      if (actual.containsKey(id)) {
        violations.add(
          CompatibilityViolation(
            'invalid_not_applicable',
            'Duplicate notApplicable ID: $id.',
          ),
        );
      }
      actual[id] = boundary;
    }
    final expectedBoundary =
        id is String ? phase1NotApplicableBoundaries[id] : null;
    final upstreamPath = record['upstreamPath'];
    final pathExists = upstreamPath is String &&
        inventory.values.any((paths) => paths.contains(upstreamPath));
    if (expectedBoundary == null ||
        boundary != expectedBoundary ||
        record['upstreamCommit'] != phase1TargetCommit ||
        upstreamPath is! String ||
        !_isCanonicalRepoPath(upstreamPath) ||
        !upstreamPath.startsWith('packages/') ||
        !pathExists ||
        !_isNonEmptyString(record['reason'])) {
      violations.add(
        CompatibilityViolation(
          'invalid_not_applicable',
          '$location must match the fixed boundary, revision, path and reason.',
        ),
      );
    }
  }
  if (actual.length != phase1NotApplicableBoundaries.length ||
      phase1NotApplicableBoundaries.entries.any(
        (entry) => actual[entry.key] != entry.value,
      )) {
    violations.add(
      const CompatibilityViolation(
        'not_applicable_set_mismatch',
        'notApplicable must equal the fixed four ID/boundary records.',
      ),
    );
  }
}

void _validateObjectKeys(
  Map<String, Object?> object, {
  required Set<String> allowed,
  required Set<String> required,
  required String location,
  required List<CompatibilityViolation> violations,
}) {
  for (final key in object.keys) {
    if (!allowed.contains(key)) {
      violations.add(
        CompatibilityViolation('unknown_key', 'Unknown key $location.$key.'),
      );
    }
  }
  for (final key in required) {
    if (!object.containsKey(key)) {
      violations.add(
        CompatibilityViolation(
          'missing_key',
          'Missing required key $location.$key.',
        ),
      );
    }
  }
}

List<String>? _fixtureIdList(
  Object? value, {
  required String location,
  required List<CompatibilityViolation> violations,
}) {
  final values = _stringList(value, location: location, violations: violations);
  if (values == null) {
    return null;
  }
  final seen = <String>{};
  for (final value in values) {
    if (!phase1FixtureIds.contains(value)) {
      violations.add(
        CompatibilityViolation(
          'unknown_fixture_id',
          '$location contains unknown fixture ID $value.',
        ),
      );
    }
    if (!seen.add(value)) {
      violations.add(
        CompatibilityViolation(
          'duplicate_fixture_id',
          '$location contains duplicate fixture ID $value.',
        ),
      );
    }
  }
  return values;
}

List<String>? _stringList(
  Object? value, {
  required String location,
  required List<CompatibilityViolation> violations,
}) {
  if (value is! List<Object?> || value.any((element) => element is! String)) {
    violations.add(
      CompatibilityViolation(
        'invalid_type',
        '$location must be an array of strings.',
      ),
    );
    return null;
  }
  return value.cast<String>();
}

List<Map<String, Object?>>? _objectList(
  Object? value, {
  required String location,
  required List<CompatibilityViolation> violations,
}) {
  if (value is! List<Object?>) {
    violations.add(
      CompatibilityViolation(
        'invalid_type',
        '$location must be an array of objects.',
      ),
    );
    return null;
  }
  final result = <Map<String, Object?>>[];
  for (var index = 0; index < value.length; index += 1) {
    final object = _object(value[index]);
    if (object == null) {
      violations.add(
        CompatibilityViolation(
          'invalid_type',
          '$location[$index] must be an object.',
        ),
      );
    } else {
      result.add(object);
    }
  }
  return result;
}

Map<String, Object?>? _object(Object? value) =>
    value is Map<String, Object?> ? value : null;

Map<String, Object?>? _readJsonObject(
  File file,
  String label,
  List<CompatibilityViolation> violations,
) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    final object = _object(decoded);
    if (object != null) {
      return object;
    }
  } on FileSystemException catch (error) {
    violations.add(
      CompatibilityViolation(
        'missing_$label',
        'Unable to read ${file.path}: ${error.message}.',
      ),
    );
    return null;
  } on FormatException catch (error) {
    violations.add(
      CompatibilityViolation(
        'invalid_$label',
        '${file.path} is not valid JSON: ${error.message}.',
      ),
    );
    return null;
  }
  violations.add(
    CompatibilityViolation(
      'invalid_$label',
      '${file.path} must contain a JSON object.',
    ),
  );
  return null;
}

void _rejectOutOfClaimIds(
  Iterable<String> ids,
  Set<String> claimFixtureIds,
  String location,
  List<CompatibilityViolation> violations,
) {
  final extra = ids.toSet().difference(claimFixtureIds);
  if (extra.isNotEmpty) {
    violations.add(
      CompatibilityViolation(
        'reference_fixture_mismatch',
        '$location references fixtures outside its claim: ${_sorted(extra)}.',
      ),
    );
  }
}

String? _packageForFixture(String fixtureId) {
  if (fixtureId.startsWith('P1-PROVIDER-')) {
    return 'pigcode_ai_provider';
  }
  if (fixtureId.startsWith('P1-UTIL-')) {
    return 'pigcode_ai_provider_utils';
  }
  if (fixtureId.startsWith('P1-CORE-')) {
    return 'pigcode_ai';
  }
  if (fixtureId.startsWith('P1-OPENAI-')) {
    return 'pigcode_ai_openai';
  }
  if (fixtureId.startsWith('P1-COMPAT-')) {
    return 'pigcode_ai_openai_compatible';
  }
  if (fixtureId.startsWith('P1-ANTHROPIC-')) {
    return 'pigcode_ai_anthropic';
  }
  if (fixtureId.startsWith('P1-CROSS-')) {
    return 'workspace';
  }
  return null;
}

bool _isCanonicalRepoPath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.endsWith('/') ||
      path.contains(r'\') ||
      path.contains('://')) {
    return false;
  }
  return path.split('/').every(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      );
}

File? _regularContainedFile(Directory root, String path) {
  if (!_isCanonicalRepoPath(path)) {
    return null;
  }
  var current = root.absolute.path;
  final segments = path.split('/');
  for (var index = 0; index < segments.length; index += 1) {
    current = current.endsWith(Platform.pathSeparator)
        ? '$current${segments[index]}'
        : '$current${Platform.pathSeparator}${segments[index]}';
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    final isLast = index == segments.length - 1;
    if (isLast) {
      return type == FileSystemEntityType.file ? File(current) : null;
    }
    if (type != FileSystemEntityType.directory) {
      return null;
    }
  }
  return null;
}

bool _isMutableVersion(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'latest' ||
      normalized == 'main' ||
      normalized == 'master' ||
      normalized == 'head' ||
      normalized.contains('://') ||
      normalized.contains('*') ||
      normalized.startsWith('^') ||
      normalized.startsWith('~') ||
      normalized.startsWith('>') ||
      normalized.startsWith('<');
}

bool _isNonEmptyString(Object? value) =>
    value is String && value.trim().isNotEmpty;

bool _setsEqual(Set<String> left, Set<String> right) =>
    left.length == right.length &&
    left.difference(right).isEmpty &&
    right.difference(left).isEmpty;

bool _listsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

String _setDifferenceMessage(
  String label,
  Set<String> actual,
  Set<String> expected,
) =>
    '$label differ from the fixed set; '
    'missing=${_sorted(expected.difference(actual))}, '
    'extra=${_sorted(actual.difference(expected))}.';

String _sorted(Iterable<String> values) {
  final sorted = values.toList()..sort();
  return sorted.join(', ');
}

final class _SourcePin {
  const _SourcePin({
    required this.upstreamPackage,
    required this.version,
    required this.tree,
    required this.upstreamDirectory,
    required this.dartDirectory,
  });

  final String upstreamPackage;
  final String version;
  final String tree;
  final String upstreamDirectory;
  final String dartDirectory;

  String get upstreamRoot => 'packages/$upstreamDirectory';
}

enum _EvidenceKind { scriptedPeer, realProcess }
