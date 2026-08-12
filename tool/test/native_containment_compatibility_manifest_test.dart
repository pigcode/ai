import 'dart:convert';
import 'dart:io';

import '../src/native_containment_compatibility_manifest.dart';

void main() {
  final root = Directory.current.absolute;
  final manifest = loadNativeContainmentCompatibilityManifest(root);

  _test('accepts the honest Phase 4 manifest', () {
    _expectNoViolations(
      validateNativeContainmentCompatibilityManifest(
        root: root,
        manifest: manifest,
      ),
    );
  });

  _test('rejects fake verified evidence', () {
    final changed = _copy(manifest);
    _claim(changed, 'P4-DART-02')['level'] = 'verified';
    _evidence(changed, 'P4-DART-02')['claimLevel'] = 'verified';
    _expectViolation(changed, root, 'verified_known_unsupported');
  });

  _test('rejects missing P4-TM coverage', () {
    final changed = _copy(manifest);
    _threatModels(_evidence(changed, 'P4-HOST-04')).remove('P4-TM-PATH-01');
    _expectViolation(changed, root, 'threat_model_coverage_mismatch');
  });

  _test('rejects unsafe evidence as production evidence', () {
    final changed = _copy(manifest);
    _evidence(changed, 'P4-HOST-02')['capabilityProfile'] = 'unsafe/dev-only';
    _expectViolation(changed, root, 'unsafe_production_evidence');
  });

  _test('rejects an unexecuted platform overclaim', () {
    final changed = _copy(manifest);
    final evidence = _evidence(changed, 'P4-HOST-02');
    evidence['platform'] = 'windows-x64';
    (evidence['platformTuple']! as Map<String, Object?>)['executed'] = false;
    _expectViolation(changed, root, 'unverified_platform');
  });

  _test('rejects Linux verified evidence without ABI', () {
    final changed = _copy(manifest);
    final evidence = _evidence(changed, 'P4-HOST-03');
    _claim(changed, 'P4-HOST-03')['level'] = 'verified';
    evidence
      ..['claimLevel'] = 'verified'
      ..['platform'] = 'linux-x86_64'
      ..['platformTuple'] = <String, Object?>{
        'executed': true,
        'osVersion': 'ubuntu-24.04',
        'kernelVersion': '6.8.0',
        'arch': 'x86_64',
        'sandboxBackend': 'landlock-seccomp',
      };
    _expectViolation(changed, root, 'linux_abi_missing');
  });

  _test('rejects incomplete crash injection evidence', () {
    final changed = _copy(manifest);
    _scenarios(_evidence(changed, 'P4-HOST-10')).removeLast();
    _expectViolation(changed, root, 'crash_matrix_coverage_mismatch');
  });

  _test('rejects verified evidence whose result is deferred', () {
    final changed = _copy(manifest);
    _evidence(changed, 'P4-HOST-02')['result'] = <String, Object?>{
      'status': 'ci-deferred',
      'assertions': <Object?>['not-executed'],
    };
    _expectViolation(changed, root, 'verified_result_not_passed');
  });

  _test('rejects verified evidence with an unapproved kind', () {
    final changed = _copy(manifest);
    _evidence(changed, 'P4-HOST-02')['kind'] = 'unit-test';
    _expectViolation(changed, root, 'verified_evidence_kind_invalid');
  });

  _test('rejects a scenario borrowed from another claim', () {
    final changed = _copy(manifest);
    _evidence(changed, 'P4-HOST-02')['scenario'] =
        _evidence(changed, 'P4-HOST-07')['scenario'];
    _expectViolation(changed, root, 'scenario_claim_mismatch');
  });

  _test('rejects moving a KU reference while preserving global closure', () {
    final changed = _copy(manifest);
    final dartRefs =
        _claim(changed, 'P4-DART-02')['knownUnsupportedRefs']! as List<Object?>;
    dartRefs.remove('KU-P4-DAP-POLICY');
    final hostRefs =
        _claim(changed, 'P4-HOST-01')['knownUnsupportedRefs']! as List<Object?>;
    hostRefs.add('KU-P4-DAP-POLICY');
    _expectViolation(changed, root, 'unsupported_binding_mismatch');
  });

  _test('rejects unsafe implementation found in the actual artifact', () {
    final changed = _copy(manifest);
    final artifact =
        (_evidence(changed, 'P4-HOST-02')['artifacts']! as List<Object?>).single
            as Map<String, Object?>;
    artifact
      ..['path'] = 'packages/agent_io/test/sandbox/fail_closed_test.dart'
      ..['sha256'] =
          '9ac40ddc26758d7987a3400046ea10227964a03ea2cbaa6d39e0a6ace18f3fb7';
    _expectViolation(changed, root, 'unsafe_production_artifact');
  });

  _test('rejects threat-model refs absent from bound artifacts', () {
    final changed = _copy(manifest);
    _evidence(changed, 'P4-HOST-04')['artifacts'] = <Object?>[
      <String, Object?>{
        'path': 'packages/agent_io/test/sandbox/seatbelt_enforcement_test.dart',
        'sha256':
            '2349cc3d0e07487b896aeeed8c370c8149e6b17b27c60a2df9468d74c41fadf5',
      },
    ];
    _expectViolation(changed, root, 'threat_model_artifact_mismatch');
  });

  stdout.writeln('PASS Phase 4 native containment compatibility manifest');
}

Map<String, Object?> _copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value))! as Map<String, Object?>;

List<Map<String, Object?>> _claims(Map<String, Object?> manifest) =>
    (manifest['claims']! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> _claim(Map<String, Object?> manifest, String id) =>
    _claims(manifest).singleWhere((claim) => claim['id'] == id);

Map<String, Object?> _evidence(Map<String, Object?> manifest, String claimId) =>
    (manifest['evidence']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((evidence) => evidence['claimId'] == claimId);

List<Object?> _threatModels(Map<String, Object?> evidence) =>
    (evidence['threatModelRefs']! as List<Object?>);

List<Object?> _scenarios(Map<String, Object?> evidence) =>
    (evidence['injectionScenarios']! as List<Object?>);

void _expectViolation(
  Map<String, Object?> manifest,
  Directory root,
  String code,
) {
  final violations = validateNativeContainmentCompatibilityManifest(
    root: root,
    manifest: manifest,
  );
  if (!violations.any((violation) => violation.code == code)) {
    throw StateError(
      'Expected $code, found '
      '${violations.map((violation) => violation.code).toList()}',
    );
  }
}

void _expectNoViolations(
  List<NativeContainmentCompatibilityViolation> violations,
) {
  if (violations.isNotEmpty) throw StateError(violations.join('\n'));
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
