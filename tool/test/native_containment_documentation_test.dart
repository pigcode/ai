import 'dart:io';

import '../src/native_containment_compatibility_manifest.dart';
import '../src/native_containment_documentation.dart';

Future<void> main() async {
  final root = Directory.current.absolute;
  final manifest = loadNativeContainmentCompatibilityManifest(root);
  final documents = loadNativeContainmentPublicDocuments(root);

  _expectNoViolations(
    validateNativeContainmentPublicDocumentation(
      root: root,
      manifest: manifest,
      documents: documents,
    ),
  );
  _expectViolation(
    root,
    manifest,
    <String, String>{
      ...documents,
      'packages/agent/README.md': documents['packages/agent/README.md']!
          .replaceFirst(
              'P4-AGENT-01`: `implemented', 'P4-AGENT-01`: `verified'),
    },
    'documentation_claim_level_mismatch',
  );
  _expectViolation(
    root,
    manifest,
    <String, String>{
      ...documents,
      'packages/agent_io/README.md':
          documents['packages/agent_io/README.md']!.replaceFirst(
        RegExp(r'^- `P4-HOST-01`.*\n', multiLine: true),
        '',
      ),
    },
    'documentation_claim_missing',
  );
  _expectViolation(
    root,
    manifest,
    <String, String>{
      ...documents,
      'README.md': '${documents['README.md']}\n- `P4-HOST-99`: `verified`\n',
    },
    'documentation_unknown_claim',
  );
  final unsupported = (manifest['knownUnsupported']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .first['id']! as String;
  _expectViolation(
    root,
    manifest,
    <String, String>{
      for (final entry in documents.entries)
        entry.key: entry.value.replaceAll(unsupported, 'REMOVED-KU'),
    },
    'documentation_known_unsupported_missing',
  );

  for (final example in const <String>[
    'packages/agent/example/native_agent.dart',
    'packages/agent_io/example/durable_store.dart',
    'packages/agent_io/example/sandboxed_process.dart',
    'packages/agent_dart/example/dart_tooling_agent.dart',
  ]) {
    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>[example],
      workingDirectory: root.path,
    ).timeout(const Duration(seconds: 30));
    if (result.exitCode != 0) {
      throw StateError('$example failed: ${result.stderr}');
    }
  }
  stdout.writeln('PASS Phase 4 public documentation consumer closure');
}

void _expectViolation(
  Directory root,
  Map<String, Object?> manifest,
  Map<String, String> documents,
  String code,
) {
  final violations = validateNativeContainmentPublicDocumentation(
    root: root,
    manifest: manifest,
    documents: documents,
  );
  if (!violations.any((violation) => violation.code == code)) {
    throw StateError(
      'Expected $code, found '
      '${violations.map((violation) => violation.code).toList()}',
    );
  }
}

void _expectNoViolations(
  List<NativeContainmentDocumentationViolation> violations,
) {
  if (violations.isNotEmpty) throw StateError(violations.join('\n'));
}
