import 'dart:convert';
import 'dart:io';

import '../src/native_containment_compatibility_manifest.dart';

void main() {
  final root = Directory.current.absolute;
  final original = loadNativeContainmentCompatibilityManifest(root);
  final baseline = validateNativeContainmentCompatibilityManifest(
    root: root,
    manifest: original,
  );
  if (baseline.isNotEmpty) {
    throw StateError('Mutation baseline is invalid: ${baseline.join(', ')}');
  }
  final mutations = <String, Map<String, Object?> Function()>{
    for (final field in <String>[
      r'$schema',
      'formatVersion',
      'phase',
      'implementationCommit',
      'dartSdkConstraint',
      'sources',
      'claims',
      'evidence',
      'knownUnsupported',
    ])
      'delete-root-field:$field': () => _copy(original)..remove(field),
    for (var index = 0; index < _claims(original).length; index++)
      'change-claim-level:$index': () {
        final changed = _copy(original);
        _claims(changed)[index]['level'] = 'forged-level';
        return changed;
      },
    for (var index = 0; index < _claims(original).length; index++)
      'rotate-evidence-ref:$index': () {
        final changed = _copy(original);
        final claims = _claims(changed);
        claims[index]['evidenceRef'] =
            claims[(index + 1) % claims.length]['evidenceRef'];
        return changed;
      },
    for (var index = 0; index < _evidence(original).length; index++)
      'break-claim-evidence-closure:$index': () {
        final changed = _copy(original);
        _evidence(changed)[index]['claimId'] = 'P4-UNKNOWN-99';
        return changed;
      },
    for (var index = 0; index < _evidence(original).length; index++)
      'delete-evidence:$index': () {
        final changed = _copy(original);
        _evidence(changed).removeAt(index);
        return changed;
      },
    for (final location in _artifactLocations(original))
      'tamper-artifact-digest:${location.$1}:${location.$2}': () {
        final changed = _copy(original);
        _artifacts(_evidence(changed)[location.$1])[location.$2]['sha256'] =
            ''.padLeft(64, '0');
        return changed;
      },
    for (final index in _executedEvidenceIndexes(original))
      'forge-platform-tuple:$index': () {
        final changed = _copy(original);
        (_evidence(changed)[index]['platformTuple']!
            as Map<String, Object?>)['executed'] = false;
        return changed;
      },
    for (var index = 0; index < _knownUnsupported(original).length; index++)
      'delete-known-unsupported:$index': () {
        final changed = _copy(original);
        _knownUnsupported(changed).removeAt(index);
        return changed;
      },
    'move-known-unsupported-reference': () {
      final changed = _copy(original);
      final claims = _claims(changed);
      final source = claims.firstWhere(
        (claim) => (claim['knownUnsupportedRefs']! as List<Object?>).isNotEmpty,
      );
      final target = claims.firstWhere(
        (claim) => (claim['knownUnsupportedRefs']! as List<Object?>).isEmpty,
      );
      final refs = source['knownUnsupportedRefs']! as List<Object?>;
      (target['knownUnsupportedRefs']! as List<Object?>).add(refs.removeLast());
      return changed;
    },
    'add-unknown-claim-field': () {
      final changed = _copy(original);
      _claims(changed).first['forged'] = true;
      return changed;
    },
    'add-unknown-evidence-field': () {
      final changed = _copy(original);
      _evidence(changed).first['forged'] = true;
      return changed;
    },
    'add-unknown-artifact-field': () {
      final changed = _copy(original);
      _artifacts(_evidence(changed).first).first['forged'] = true;
      return changed;
    },
  };

  final accepted = <String>[];
  for (final entry in mutations.entries) {
    final violations = validateNativeContainmentCompatibilityManifest(
      root: root,
      manifest: entry.value(),
    );
    if (violations.isEmpty) accepted.add(entry.key);
  }
  if (accepted.isNotEmpty) {
    stderr.writeln('FAIL accepted manifest mutations: ${accepted.join(', ')}');
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'PASS rejected ${mutations.length} independent manifest mutations',
  );
}

Map<String, Object?> _copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value))! as Map<String, Object?>;

List<Map<String, Object?>> _claims(Map<String, Object?> manifest) =>
    (manifest['claims']! as List<Object?>).cast<Map<String, Object?>>();

List<Map<String, Object?>> _evidence(Map<String, Object?> manifest) =>
    (manifest['evidence']! as List<Object?>).cast<Map<String, Object?>>();

List<Map<String, Object?>> _knownUnsupported(
  Map<String, Object?> manifest,
) =>
    (manifest['knownUnsupported']! as List<Object?>)
        .cast<Map<String, Object?>>();

List<Map<String, Object?>> _artifacts(Map<String, Object?> evidence) =>
    (evidence['artifacts']! as List<Object?>).cast<Map<String, Object?>>();

Iterable<(int, int)> _artifactLocations(Map<String, Object?> manifest) sync* {
  final evidence = _evidence(manifest);
  for (var evidenceIndex = 0;
      evidenceIndex < evidence.length;
      evidenceIndex++) {
    for (var artifactIndex = 0;
        artifactIndex < _artifacts(evidence[evidenceIndex]).length;
        artifactIndex++) {
      yield (evidenceIndex, artifactIndex);
    }
  }
}

Iterable<int> _executedEvidenceIndexes(
  Map<String, Object?> manifest,
) sync* {
  final evidence = _evidence(manifest);
  for (var index = 0; index < evidence.length; index++) {
    final tuple = evidence[index]['platformTuple']! as Map<String, Object?>;
    if (tuple['executed'] == true) yield index;
  }
}
