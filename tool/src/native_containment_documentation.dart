import 'dart:io';

final class NativeContainmentDocumentationViolation {
  const NativeContainmentDocumentationViolation(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

const nativeContainmentPublicDocumentClaims = <String, Set<String>>{
  'README.md': <String>{
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
  },
  'docs/native-containment-support.md': <String>{
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
  },
  'packages/agent/README.md': <String>{
    'P4-AGENT-01',
    'P4-AGENT-02',
    'P4-AGENT-03',
  },
  'packages/agent_io/README.md': <String>{
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
  },
  'packages/agent_dart/README.md': <String>{
    'P4-DART-01',
    'P4-DART-02',
  },
};

const _exampleTests = <String, String>{
  'packages/agent/example/native_agent.dart':
      'packages/agent/test/example_compile_test.dart',
  'packages/agent_io/example/durable_store.dart':
      'packages/agent_io/test/example_compile_test.dart',
  'packages/agent_io/example/sandboxed_process.dart':
      'packages/agent_io/test/example_compile_test.dart',
  'packages/agent_dart/example/dart_tooling_agent.dart':
      'packages/agent_dart/test/example_compile_test.dart',
};

final _claimDeclaration = RegExp(
  r'^-\s+`(P4-(?:HOST|AGENT|DART|CROSS)-[0-9]+)`:\s+'
  r'`(implemented|verified|known-unsupported)`\s*$',
  multiLine: true,
);
final _claimReference = RegExp(r'P4-(?:HOST|AGENT|DART|CROSS)-[0-9]+');
final _unsupportedReference = RegExp(r'KU-P4-[A-Z0-9-]+');

Map<String, String> loadNativeContainmentPublicDocuments(Directory root) =>
    <String, String>{
      for (final path in nativeContainmentPublicDocumentClaims.keys)
        path: File.fromUri(root.absolute.uri.resolve(path)).readAsStringSync(),
    };

List<NativeContainmentDocumentationViolation>
    validateNativeContainmentPublicDocumentation({
  required Directory root,
  required Map<String, Object?> manifest,
  Map<String, String>? documents,
}) {
  final violations = <NativeContainmentDocumentationViolation>[];
  final contents = documents ?? loadNativeContainmentPublicDocuments(root);
  final claims = <String, String>{
    for (final claim
        in (manifest['claims']! as List<Object?>).cast<Map<String, Object?>>())
      claim['id']! as String: claim['level']! as String,
  };

  for (final entry in nativeContainmentPublicDocumentClaims.entries) {
    final document = contents[entry.key];
    if (document == null) {
      violations.add(
        NativeContainmentDocumentationViolation(
          'documentation_missing',
          '${entry.key} is unavailable to the public documentation checker.',
        ),
      );
      continue;
    }
    final declarations = <String, List<String>>{};
    for (final match in _claimDeclaration.allMatches(document)) {
      declarations
          .putIfAbsent(match.group(1)!, () => <String>[])
          .add(match.group(2)!);
    }
    for (final id in entry.value) {
      final levels = declarations[id];
      if (levels == null || levels.length != 1) {
        violations.add(
          NativeContainmentDocumentationViolation(
            'documentation_claim_missing',
            '${entry.key} must declare $id exactly once.',
          ),
        );
      } else if (levels.single != claims[id]) {
        violations.add(
          NativeContainmentDocumentationViolation(
            'documentation_claim_level_mismatch',
            '${entry.key} declares $id=${levels.single}, expected ${claims[id]}.',
          ),
        );
      }
    }
    for (final id in declarations.keys) {
      if (!claims.containsKey(id)) {
        violations.add(
          NativeContainmentDocumentationViolation(
            'documentation_unknown_claim',
            '${entry.key} declares unknown claim $id.',
          ),
        );
      } else if (!entry.value.contains(id)) {
        violations.add(
          NativeContainmentDocumentationViolation(
            'documentation_claim_scope_mismatch',
            '${entry.key} declares out-of-scope claim $id.',
          ),
        );
      }
    }
    for (final match in _claimReference.allMatches(document)) {
      final id = match.group(0)!;
      if (!claims.containsKey(id)) {
        violations.add(
          NativeContainmentDocumentationViolation(
            'documentation_unknown_claim',
            '${entry.key} references unknown claim $id.',
          ),
        );
      }
    }
  }

  final allText = contents.values.join('\n');
  final visibleUnsupported = _unsupportedReference
      .allMatches(allText)
      .map((match) => match.group(0)!)
      .toSet();
  for (final item in (manifest['knownUnsupported']! as List<Object?>)
      .cast<Map<String, Object?>>()) {
    final id = item['id']! as String;
    if (!visibleUnsupported.contains(id)) {
      violations.add(
        NativeContainmentDocumentationViolation(
          'documentation_known_unsupported_missing',
          '$id is absent from public documentation.',
        ),
      );
    }
  }

  for (final entry in _exampleTests.entries) {
    final example = File.fromUri(root.absolute.uri.resolve(entry.key));
    final test = File.fromUri(root.absolute.uri.resolve(entry.value));
    if (!example.existsSync() ||
        !test.existsSync() ||
        !test.readAsStringSync().contains(example.uri.pathSegments.last)) {
      violations.add(
        NativeContainmentDocumentationViolation(
          'documentation_example_closure_missing',
          '${entry.key} lacks its public compile/execute test.',
        ),
      );
    }
  }
  return violations;
}
