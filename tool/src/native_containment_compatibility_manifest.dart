import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const nativeContainmentCompatibilityManifestPath =
    'compatibility/phase-4-native-containment.json';
const nativeContainmentCompatibilitySchemaPath =
    'compatibility/schema/native-containment-compatibility.schema.json';
const phase4EvidenceCommit = 'pending-main-merge';

const phase4ClaimIds = <String>{
  'P4-HOST-01',
  'P4-HOST-02',
  'P4-HOST-03',
  'P4-HOST-04',
  'P4-HOST-05',
  'P4-HOST-06',
  'P4-HOST-07',
  'P4-HOST-08',
  'P4-HOST-09',
  'P4-HOST-10',
  'P4-AGENT-01',
  'P4-AGENT-02',
  'P4-AGENT-03',
  'P4-DART-01',
  'P4-DART-02',
  'P4-CROSS-01',
  'P4-CROSS-02',
  'P4-CROSS-03',
};

const phase4ThreatModelIds = <String>{
  'P4-TM-PATH-01',
  'P4-TM-PATH-02',
  'P4-TM-PATH-03',
  'P4-TM-PATH-04',
  'P4-TM-PATH-05',
  'P4-TM-PROC-01',
  'P4-TM-PROC-02',
  'P4-TM-PROC-03',
  'P4-TM-PROC-04',
  'P4-TM-PROC-05',
  'P4-TM-PTY-01',
  'P4-TM-PTY-02',
  'P4-TM-PTY-03',
  'P4-TM-PTY-04',
  'P4-TM-GIT-01',
  'P4-TM-GIT-02',
  'P4-TM-GIT-03',
  'P4-TM-GIT-04',
  'P4-TM-CRED-01',
  'P4-TM-CRED-02',
  'P4-TM-CRED-03',
  'P4-TM-CRED-04',
  'P4-TM-DLP-01',
  'P4-TM-DLP-02',
  'P4-TM-DLP-03',
  'P4-TM-DLP-04',
  'P4-TM-DLP-05',
};

const phase4InjectionScenarios = <String>{
  'probe-before-after',
  'sandbox-setup-before-apply',
  'sandbox-after-apply-before-exec',
  'effect-before-execution',
  'effect-mid-execution',
  'effect-after-execution-before-outcome',
  'outcome-after-write-before-receipt',
  'cleanup-after-cancel-before-confirm',
  'cleanup-after-confirm-before-record',
  'restart-recovery-mid-capability-rebuild',
};

const phase4KnownUnsupportedIds = <String>{
  'KU-P4-WINDOWS',
  'KU-P4-MACOS-X64',
  'KU-P4-LINUX-LOW-ABI',
  'KU-P4-NAMESPACE',
  'KU-P4-PTY-ABI4',
  'KU-P4-DLP-NONTCP',
  'KU-P4-MALICIOUS-HOST',
  'KU-P4-EXTERNAL-HARNESS',
  'KU-P4-STRONGER-ISOLATION',
  'KU-P4-APPLE-FUTURE',
  'KU-P4-DATA-AT-REST',
  'KU-P4-DURABLE-CHECKPOINT',
  'KU-P4-HARDLINK',
  'KU-P4-LANDLOCK-NESTED-RO',
  'KU-P4-DAP-POLICY',
  'KU-P4-CHROME-LOCAL',
  'KU-P4-MACOS-DETACHED-CRASH-CLEANUP',
};

const _claimScenarios = <String, String>{
  'P4-HOST-01': 'capability-probe-and-typed-failure',
  'P4-HOST-02': 'seatbelt-read-write-network-denial',
  'P4-HOST-03': 'landlock-seccomp-enforcement',
  'P4-HOST-04': 'path-traversal-link-toctou-readonly-roots',
  'P4-HOST-05': 'argv-no-shell-restart-cleanup-effect-control',
  'P4-HOST-06': 'pty-spawn-flood-cleanup-runtime-probed-ioctl-capability',
  'P4-HOST-07': 'git-metadata-remote-credential-process-boundary',
  'P4-HOST-08': 'credential-injection-crash-target-restart',
  'P4-HOST-09': 'exact-allowlist-adjacent-denial-bypass-drop-redaction',
  'P4-HOST-10': 'fixed-ten-point-containment-injection',
  'P4-AGENT-01': 'explicit-session-state-preconditions',
  'P4-AGENT-02': 'ai-sdk-kernel-effect-control-mapping',
  'P4-AGENT-03': 'normal-failure-deny-cancel-crash-restart',
  'P4-DART-01': 'sandbox-launch-proposal-only-no-mcp',
  'P4-DART-02': 'dual-dap-peer-sandbox-debug',
  'P4-CROSS-01': 'agent-portable-agent-io-dart-vm-only',
  'P4-CROSS-02': 'negative-overclaim-and-coverage-gates',
  'P4-CROSS-03': 'readme-examples-known-unsupported',
};

const _claimUnsupportedBindings = <String, Set<String>>{
  'P4-HOST-01': {
    'KU-P4-WINDOWS',
    'KU-P4-MACOS-X64',
    'KU-P4-LINUX-LOW-ABI',
    'KU-P4-MALICIOUS-HOST',
    'KU-P4-STRONGER-ISOLATION',
    'KU-P4-APPLE-FUTURE',
  },
  'P4-HOST-03': {'KU-P4-LINUX-LOW-ABI', 'KU-P4-LANDLOCK-NESTED-RO'},
  'P4-HOST-04': {'KU-P4-HARDLINK'},
  'P4-HOST-05': {
    'KU-P4-NAMESPACE',
    'KU-P4-MACOS-DETACHED-CRASH-CLEANUP',
  },
  'P4-HOST-06': {'KU-P4-PTY-ABI4'},
  'P4-HOST-07': {'KU-P4-LANDLOCK-NESTED-RO'},
  'P4-HOST-08': {'KU-P4-DATA-AT-REST'},
  'P4-HOST-09': {'KU-P4-DLP-NONTCP'},
  'P4-AGENT-03': {
    'KU-P4-DURABLE-CHECKPOINT',
    'KU-P4-EXTERNAL-HARNESS',
  },
  'P4-DART-02': {'KU-P4-DAP-POLICY'},
  'P4-CROSS-01': {'KU-P4-CHROME-LOCAL'},
};

const _verifiedEvidenceKinds = <String>{
  'real-sandbox-child-process',
  'real-sandbox-path-boundary',
  'real-sandbox-git-process',
  'real-sigkill-matrix',
  'real-credential-boundary',
  'real-dlp-boundary',
  'real-facade-state-matrix',
  'real-dart-tooling-composition',
  'manifest-mutation-closure',
  'public-document-consumer-closure',
  'real-agent-effect-path',
  'real-native-agent-journey',
};

final class NativeContainmentCompatibilityViolation {
  const NativeContainmentCompatibilityViolation(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

Map<String, Object?> loadNativeContainmentCompatibilityManifest(
  Directory root, {
  String path = nativeContainmentCompatibilityManifestPath,
}) {
  final decoded = jsonDecode(_containedFile(root, path).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'Native containment compatibility manifest must be a JSON object.',
    );
  }
  return decoded;
}

List<NativeContainmentCompatibilityViolation>
    validateNativeContainmentCompatibilityManifest({
  required Directory root,
  Map<String, Object?>? manifest,
}) {
  try {
    return _validate(
      root.absolute,
      manifest ?? loadNativeContainmentCompatibilityManifest(root),
    );
  } on Object catch (error) {
    return <NativeContainmentCompatibilityViolation>[
      NativeContainmentCompatibilityViolation(
        'invalid_manifest',
        error.toString(),
      ),
    ];
  }
}

List<NativeContainmentCompatibilityViolation> _validate(
  Directory root,
  Map<String, Object?> manifest,
) {
  final violations = <NativeContainmentCompatibilityViolation>[];
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
  );
  if (manifest[r'$schema'] !=
          './schema/native-containment-compatibility.schema.json' ||
      manifest['formatVersion'] != 1 ||
      manifest['phase'] != 'phase-4-native-containment' ||
      manifest['implementationCommit'] != phase4EvidenceCommit ||
      manifest['dartSdkConstraint'] != '^3.6.0') {
    violations.add(
      const NativeContainmentCompatibilityViolation(
        'manifest_identity_mismatch',
        'Phase, schema, SDK, and implementation commit must be pinned.',
      ),
    );
  }

  final sources = _objectList(manifest['sources'], 'sources');
  final sourceIds = <String>{};
  for (var index = 0; index < sources.length; index++) {
    final source = sources[index];
    _expectExactKeys(source, const <String>{'id', 'kind', 'path', 'sha256'});
    final id = _string(source['id'], 'sources[$index].id');
    final path = _string(source['path'], 'sources[$index].path');
    sourceIds.add(id);
    _validateDigest(root, path, source['sha256'], violations);
  }

  final claims = _objectList(manifest['claims'], 'claims');
  final evidence = _objectList(manifest['evidence'], 'evidence');
  final unsupported =
      _objectList(manifest['knownUnsupported'], 'knownUnsupported');
  final claimIds = <String>{
    for (var index = 0; index < claims.length; index++)
      _string(claims[index]['id'], 'claims[$index].id'),
  };
  if (!_sameSet(claimIds, phase4ClaimIds)) {
    violations.add(
      const NativeContainmentCompatibilityViolation(
        'claim_coverage_mismatch',
        'Claims must exactly cover the approved 18 Phase 4 IDs.',
      ),
    );
  }
  final unsupportedIds = <String>{
    for (var index = 0; index < unsupported.length; index++)
      _string(unsupported[index]['id'], 'knownUnsupported[$index].id'),
  };
  if (!_sameSet(unsupportedIds, phase4KnownUnsupportedIds)) {
    violations.add(
      const NativeContainmentCompatibilityViolation(
        'known_unsupported_coverage_mismatch',
        'Known unsupported records must exactly match the approved inventory.',
      ),
    );
  }

  final evidenceById = <String, Map<String, Object?>>{};
  final evidenceByClaim = <String, int>{};
  final observedThreatModels = <String>{};
  final referencedUnsupported = <String>{};
  for (var index = 0; index < evidence.length; index++) {
    final item = evidence[index];
    _expectExactKeys(item, const <String>{
      'id',
      'claimId',
      'claimLevel',
      'kind',
      'capabilityProfile',
      'platform',
      'platformTuple',
      'evidenceCommit',
      'scenario',
      'threatModelRefs',
      'injectionScenarios',
      'artifacts',
      'result',
    });
    final id = _string(item['id'], 'evidence[$index].id');
    final claimId = _string(item['claimId'], 'evidence[$index].claimId');
    evidenceById[id] = item;
    evidenceByClaim.update(claimId, (value) => value + 1, ifAbsent: () => 1);
    observedThreatModels.addAll(
      _stringList(item['threatModelRefs'], 'evidence[$index].threatModelRefs'),
    );
    _validateEvidence(root, item, claimId, violations);
  }

  for (var index = 0; index < claims.length; index++) {
    final claim = claims[index];
    _expectExactKeys(claim, const <String>{
      'id',
      'component',
      'level',
      'summary',
      'sourceRefs',
      'evidenceRef',
      'knownUnsupportedRefs',
    });
    final id = _string(claim['id'], 'claims[$index].id');
    final level = _string(claim['level'], 'claims[$index].level');
    if (level != 'implemented' &&
        level != 'verified' &&
        level != 'known-unsupported') {
      violations.add(
        NativeContainmentCompatibilityViolation(
          'invalid_claim_level',
          '$id uses unsupported level $level.',
        ),
      );
    }
    for (final sourceRef
        in _stringList(claim['sourceRefs'], 'claims[$index].sourceRefs')) {
      if (!sourceIds.contains(sourceRef)) {
        violations.add(
          NativeContainmentCompatibilityViolation(
            'unknown_source_ref',
            '$id references unknown source $sourceRef.',
          ),
        );
      }
    }
    final evidenceRef =
        _string(claim['evidenceRef'], 'claims[$index].evidenceRef');
    final item = evidenceById[evidenceRef];
    if (item == null ||
        item['claimId'] != id ||
        item['claimLevel'] != level ||
        evidenceByClaim[id] != 1) {
      violations.add(
        NativeContainmentCompatibilityViolation(
          'evidence_cardinality_mismatch',
          '$id must bind exactly one level-matched evidence record.',
        ),
      );
    }
    final refs = _stringList(
      claim['knownUnsupportedRefs'],
      'claims[$index].knownUnsupportedRefs',
    );
    referencedUnsupported.addAll(refs);
    final expectedRefs = _claimUnsupportedBindings[id] ?? const <String>{};
    if (!_sameSet(refs.toSet(), expectedRefs)) {
      violations.add(
        NativeContainmentCompatibilityViolation(
          'unsupported_binding_mismatch',
          '$id must bind exactly its claim-specific unsupported records.',
        ),
      );
    }
    if (refs.any((ref) => !unsupportedIds.contains(ref))) {
      violations.add(
        NativeContainmentCompatibilityViolation(
          'unknown_unsupported_ref',
          '$id references an unknown unsupported item.',
        ),
      );
    }
    if (level == 'known-unsupported' &&
        (item?['result'] as Map<String, Object?>?)?['status'] !=
            'known-unsupported') {
      violations.add(
        NativeContainmentCompatibilityViolation(
          'unsupported_claim_status_mismatch',
          '$id known-unsupported claim requires known-unsupported evidence.',
        ),
      );
    }
    if (level == 'verified' && refs.contains('KU-P4-DAP-POLICY')) {
      violations.add(
        NativeContainmentCompatibilityViolation(
          'verified_known_unsupported',
          '$id verified claim cannot retain unsupported boundaries.',
        ),
      );
    }
  }
  if (!_sameSet(referencedUnsupported, unsupportedIds)) {
    violations.add(
      const NativeContainmentCompatibilityViolation(
        'known_unsupported_not_referenced',
        'Every known unsupported item must be referenced by a claim.',
      ),
    );
  }
  for (var index = 0; index < unsupported.length; index++) {
    _expectExactKeys(
      unsupported[index],
      const <String>{'id', 'scope', 'summary'},
    );
  }
  if (!_sameSet(observedThreatModels, phase4ThreatModelIds)) {
    violations.add(
      const NativeContainmentCompatibilityViolation(
        'threat_model_coverage_mismatch',
        'Evidence must cover all 27 P4-TM IDs.',
      ),
    );
  }
  final crashEvidence = evidence.singleWhere(
    (item) => item['claimId'] == 'P4-HOST-10',
    orElse: () => <String, Object?>{},
  );
  final crashScenarios = <String>{
    ..._stringList(
      crashEvidence['injectionScenarios'],
      'P4-HOST-10.injectionScenarios',
    ),
  };
  if (!_sameSet(crashScenarios, phase4InjectionScenarios)) {
    violations.add(
      const NativeContainmentCompatibilityViolation(
        'crash_matrix_coverage_mismatch',
        'Crash evidence must cover the fixed 10-point matrix.',
      ),
    );
  }
  return violations;
}

void _validateEvidence(
  Directory root,
  Map<String, Object?> evidence,
  String claimId,
  List<NativeContainmentCompatibilityViolation> violations,
) {
  if (evidence['evidenceCommit'] != phase4EvidenceCommit) {
    violations.add(
      NativeContainmentCompatibilityViolation(
        'evidence_commit_mismatch',
        '$claimId evidence is not bound to pending-main-merge.',
      ),
    );
  }
  final profile =
      _string(evidence['capabilityProfile'], '$claimId.capabilityProfile');
  if (profile.contains('unsafe/dev-only')) {
    violations.add(
      NativeContainmentCompatibilityViolation(
        'unsafe_production_evidence',
        '$claimId uses unsafe/dev-only evidence.',
      ),
    );
  }
  final level = _string(evidence['claimLevel'], '$claimId.claimLevel');
  final scenario = _string(evidence['scenario'], '$claimId.scenario');
  if (scenario != _claimScenarios[claimId]) {
    violations.add(
      NativeContainmentCompatibilityViolation(
        'scenario_claim_mismatch',
        '$claimId evidence scenario is not the pinned claim scenario.',
      ),
    );
  }
  final kind = _string(evidence['kind'], '$claimId.kind');
  final result = _object(evidence['result'], '$claimId.result');
  _expectExactKeys(result, const <String>{'status', 'assertions'});
  final resultStatus = _string(result['status'], '$claimId.result.status');
  final platform = _string(evidence['platform'], '$claimId.platform');
  final tuple = _object(evidence['platformTuple'], '$claimId.platformTuple');
  _expectNoUnknownKeys(tuple, const <String>{
    'executed',
    'osVersion',
    'kernelVersion',
    'arch',
    'sandboxBackend',
    'landlockAbi',
  });
  if ((platform == 'macos-arm64' ||
          platform == 'linux-x86_64' ||
          platform == 'linux-arm64') &&
      tuple['executed'] != true) {
    violations.add(
      NativeContainmentCompatibilityViolation(
        'recorded_platform_unexecuted',
        '$claimId records a concrete platform tuple without execution.',
      ),
    );
  }
  if (level == 'verified') {
    if (resultStatus != 'passed') {
      violations.add(
        NativeContainmentCompatibilityViolation(
          'verified_result_not_passed',
          '$claimId verified evidence must have result.status=passed.',
        ),
      );
    }
    if (!_verifiedEvidenceKinds.contains(kind)) {
      violations.add(
        NativeContainmentCompatibilityViolation(
          'verified_evidence_kind_invalid',
          '$claimId uses non-production verified evidence kind $kind.',
        ),
      );
    }
    final executed = tuple['executed'] == true;
    if (!executed) {
      violations.add(
        NativeContainmentCompatibilityViolation(
          'unverified_platform',
          '$claimId claims verified without an executed tuple.',
        ),
      );
    }
    if (platform == 'macos-arm64') {
      final osVersion = _string(tuple['osVersion'], '$claimId.osVersion');
      final major =
          int.tryParse(RegExp(r'\d+').firstMatch(osVersion)?.group(0) ?? '');
      if (major == null ||
          major < 13 ||
          tuple['arch'] != 'arm64' ||
          tuple['sandboxBackend'] != 'seatbelt') {
        violations.add(
          NativeContainmentCompatibilityViolation(
            'unverified_platform',
            '$claimId has an invalid macOS production tuple.',
          ),
        );
      }
    } else if (platform == 'linux-x86_64' || platform == 'linux-arm64') {
      if (!tuple.containsKey('landlockAbi')) {
        violations.add(
          NativeContainmentCompatibilityViolation(
            'linux_abi_missing',
            '$claimId Linux tuple omits Landlock ABI.',
          ),
        );
      } else {
        final abi = tuple['landlockAbi'];
        final kernel = tuple['kernelVersion'];
        if (abi is! int ||
            abi < 4 ||
            kernel is! String ||
            !_kernelAtLeast67(kernel)) {
          violations.add(
            NativeContainmentCompatibilityViolation(
              'unverified_platform',
              '$claimId has an unsupported Linux kernel/ABI tuple.',
            ),
          );
        }
      }
    } else {
      violations.add(
        NativeContainmentCompatibilityViolation(
          'unverified_platform',
          '$claimId verified unsupported platform $platform.',
        ),
      );
    }
  }
  final artifactContents = StringBuffer();
  for (final artifact
      in _objectList(evidence['artifacts'], '$claimId.artifacts')) {
    _expectExactKeys(artifact, const <String>{'path', 'sha256'});
    final path = _string(artifact['path'], '$claimId.artifact.path');
    _validateDigest(
      root,
      path,
      artifact['sha256'],
      violations,
    );
    artifactContents.writeln(_containedFile(root, path).readAsStringSync());
  }
  final contents = artifactContents.toString();
  if (level == 'verified' &&
      kind.startsWith('real-sandbox') &&
      contents.contains('UnsafeDevSandboxBackend')) {
    violations.add(
      NativeContainmentCompatibilityViolation(
        'unsafe_production_artifact',
        '$claimId verified artifact uses an unsafe process path.',
      ),
    );
  }
  for (final threatModel in _stringList(
    evidence['threatModelRefs'],
    '$claimId.threatModelRefs',
  )) {
    if (!contents.contains(threatModel)) {
      violations.add(
        NativeContainmentCompatibilityViolation(
          'threat_model_artifact_mismatch',
          '$claimId artifact does not name $threatModel.',
        ),
      );
    }
  }
}

void _validateDigest(
  Directory root,
  String path,
  Object? expected,
  List<NativeContainmentCompatibilityViolation> violations,
) {
  final file = _containedFile(root, path);
  final actual = sha256.convert(file.readAsBytesSync()).toString();
  if (expected != actual) {
    violations.add(
      NativeContainmentCompatibilityViolation(
        'evidence_artifact_hash_mismatch',
        '$path expected $expected but found $actual.',
      ),
    );
  }
}

bool _kernelAtLeast67(String value) {
  final match = RegExp(r'(\d+)\.(\d+)').firstMatch(value);
  if (match == null) return false;
  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  return major > 6 || (major == 6 && minor >= 7);
}

File _containedFile(Directory root, String path) {
  if (path.isEmpty || path.startsWith('/') || path.contains('..')) {
    throw FormatException('Manifest path escapes the repository.', path);
  }
  final file = File.fromUri(root.absolute.uri.resolve(path));
  if (!file.existsSync()) {
    throw FormatException('Manifest artifact is missing.', path);
  }
  return file;
}

List<Map<String, Object?>> _objectList(Object? value, String label) {
  if (value is! List<Object?>) throw FormatException('$label must be a list.');
  return value.map((item) => _object(item, label)).toList(growable: false);
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$label must contain objects.');
  }
  return value;
}

List<String> _stringList(Object? value, String label) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$label must be a string list.');
  }
  return value.cast<String>();
}

String _string(Object? value, String label) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$label must be a non-empty string.');
  }
  return value;
}

void _expectExactKeys(Map<String, Object?> value, Set<String> expected) {
  if (!_sameSet(value.keys.toSet(), expected)) {
    throw const FormatException('Manifest keys do not match the schema.');
  }
}

void _expectNoUnknownKeys(Map<String, Object?> value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Manifest contains unknown schema keys.');
  }
}

bool _sameSet<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);
