import 'dart:io';
import 'dart:convert';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

void main() {
  final marker = <String>['sk', '-', 'abcdefghijklmnopqrstuvwx'].join();
  Object? rejection;
  try {
    validateSafePersistedJson(<String, Object?>{'value': marker});
  } on Object catch (error) {
    rejection = error;
  }
  _expect(rejection != null, 'Credential marker was not rejected.');
  _expect(
    !rejection.toString().contains(marker),
    'Credential marker leaked through rejection output.',
  );

  final findings = <String>[];
  for (final root in <FileSystemEntity>[
    Directory('packages/agent_kernel/lib'),
    Directory('packages/agent_kernel/test/fixtures'),
    Directory('tool/schema/agent_kernel'),
    Directory('tool/fixtures/agent_kernel'),
    Directory('packages/agent_io/lib/src/credential'),
    Directory('packages/agent_io/lib/src/dlp'),
    Directory('packages/agent_io/test/security'),
    Directory('packages/agent_io/test/fixtures'),
    File('tool/fixtures/agent_sandbox_crash_child.dart'),
    File('tool/src/agent_sandbox_crash_harness.dart'),
  ]) {
    if (!root.existsSync()) continue;
    final entities = root is File
        ? <FileSystemEntity>[root]
        : (root as Directory).listSync(recursive: true, followLinks: false);
    for (final entity in entities) {
      if (entity is! File) continue;
      final text = utf8.decode(entity.readAsBytesSync(), allowMalformed: true);
      if (_credentialPatterns.any((pattern) => pattern.hasMatch(text))) {
        findings.add(entity.path);
      }
    }
  }
  _expect(
    findings.isEmpty,
    'Credential-shaped values found in Kernel artifacts: $findings',
  );
  stdout.writeln('PASS Agent Kernel secret scan and redaction gate');
}

final _credentialPatterns = <RegExp>[
  RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
  RegExp(r'github_pat_[A-Za-z0-9_]{20,}'),
  RegExp(r'gh[pousr]_[A-Za-z0-9]{30,}'),
  RegExp(r'sk-ant-[A-Za-z0-9_-]{20,}'),
  RegExp(r'sk-[A-Za-z0-9_-]{24,}'),
  RegExp(r'AKIA[0-9A-Z]{16}'),
  RegExp(r'\bBearer\s+\S+', caseSensitive: false),
];

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
