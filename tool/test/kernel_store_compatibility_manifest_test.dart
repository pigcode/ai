import 'dart:convert';
import 'dart:io';

import '../src/kernel_store_compatibility_manifest.dart';

void main() {
  final root = Directory.current.absolute;
  final manifest = loadKernelStoreCompatibilityManifest(root);

  _test('accepts the pinned Phase 3 manifest', () {
    _expectNoViolations(
      validateKernelStoreCompatibilityManifest(
        root: root,
        manifest: manifest,
      ),
    );
  });

  _test('rejects missing claims', () {
    final changed = _copy(manifest);
    _claims(changed).removeLast();
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'claim_coverage_mismatch',
    );
  });

  _test('rejects reused evidence', () {
    final changed = _copy(manifest);
    final claims = _claims(changed);
    claims[1]['evidenceRef'] = claims.first['evidenceRef'];
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'reused_evidence_ref',
    );
  });

  _test('rejects a fake verified unit test', () {
    final changed = _copy(manifest);
    _claim(changed, 'P3-KERNEL-03')['level'] = 'verified';
    _evidence(changed, 'P3-KERNEL-03')['claimLevel'] = 'verified';
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'invalid_verified_evidence',
    );
  });

  _test('rejects conformant overclaims', () {
    final changed = _copy(manifest);
    _claim(changed, 'P3-KERNEL-03')['level'] = 'conformant';
    _evidence(changed, 'P3-KERNEL-03')['claimLevel'] = 'conformant';
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'conformant_overclaim',
    );
  });

  _test('rejects a power-loss overclaim', () {
    final changed = _copy(manifest);
    _claim(changed, 'P3-STORE-06')['summary'] =
        'Raw-device power-loss supported.';
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'power_loss_overclaim',
    );
  });

  _test('rejects stale artifact digests', () {
    final changed = _copy(manifest);
    _artifacts(_evidence(changed, 'P3-KERNEL-03')).first['sha256'] =
        ''.padLeft(64, '0');
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'evidence_artifact_hash_mismatch',
    );
  });

  _test('rejects missing unsupported records', () {
    final changed = _copy(manifest);
    (changed['knownUnsupported']! as List<Object?>).removeLast();
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'known_unsupported_coverage_mismatch',
    );
  });

  _test('rejects evidence bound to the wrong commit', () {
    final changed = _copy(manifest);
    _evidence(changed, 'P3-KERNEL-03')['evidenceCommit'] = ''.padLeft(40, '1');
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'evidence_commit_mismatch',
    );
  });

  _test('rejects a platform that was not executed', () {
    final changed = _copy(manifest);
    _evidence(changed, 'P3-KERNEL-03')['platform'] = 'windows-x64';
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'unverified_platform',
    );
  });

  _test('rejects generator-only collision evidence', () {
    final changed = _copy(manifest);
    _artifacts(_evidence(changed, 'P3-KERNEL-01')).removeWhere(
      (artifact) => artifact['path']
          .toString()
          .contains('post_prune_identity_registry_test.dart'),
    );
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'post_prune_identity_evidence_missing',
    );
  });

  _test('rejects missing registry root binding', () {
    final changed = _copy(manifest);
    _assertions(_evidence(changed, 'P3-KERNEL-01'))
        .remove('session-identity-registry-root-bound');
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'registry_root_binding_missing',
    );
  });

  _test('rejects missing create-session root lookup evidence', () {
    final changed = _copy(manifest);
    _assertions(_evidence(changed, 'P3-KERNEL-04'))
        .remove('root-session-catalog-and-create-command-roots-bound');
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'create_session_root_lookup_evidence_missing',
    );
  });

  _test('rejects missing post-prune command receipt evidence', () {
    final changed = _copy(manifest);
    _assertions(_evidence(changed, 'P3-KERNEL-04'))
        .remove('post-prune-command-receipt-retained');
    _expectViolation(
      validateKernelStoreCompatibilityManifest(root: root, manifest: changed),
      'post_prune_command_receipt_evidence_missing',
    );
  });

  stdout.writeln('PASS Phase 3 Kernel/Store compatibility manifest');
}

Map<String, Object?> _copy(Map<String, Object?> value) =>
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

List<Map<String, Object?>> _artifacts(Map<String, Object?> evidence) =>
    (evidence['artifacts']! as List<Object?>).cast<Map<String, Object?>>();

List<Object?> _assertions(Map<String, Object?> evidence) =>
    ((evidence['result']! as Map<String, Object?>)['assertions']!
        as List<Object?>);

void _expectNoViolations(
  List<KernelStoreCompatibilityViolation> violations,
) {
  if (violations.isNotEmpty) throw StateError(violations.join('\n'));
}

void _expectViolation(
  List<KernelStoreCompatibilityViolation> violations,
  String code,
) {
  if (!violations.any((violation) => violation.code == code)) {
    throw StateError(
      'Expected $code, found '
      '${violations.map((violation) => violation.code).toList()}',
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
