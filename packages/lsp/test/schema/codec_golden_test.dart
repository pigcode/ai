import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  final fixture = jsonDecode(
    File.fromUri(
            _packageRoot.resolve('test/fixtures/golden/stable_messages.json'))
        .readAsStringSync(),
  ) as Map<String, Object?>;

  test('round-trips every stable request, result, and notification family', () {
    final cases =
        (fixture['cases']! as List<Object?>).cast<Map<String, Object?>>();
    expect(cases, hasLength(164));

    final covered = <String>{};
    for (final golden in cases) {
      final envelope = golden['envelope']! as Map<String, Object?>;
      final decoded = LspCodec.instance.decode(
        jsonEncode(envelope),
        sender: LspMessageSender.values.byName(golden['sender']! as String),
        responseMethod: golden['responseMethod'] as String?,
      );
      expect(
        jsonDecode(LspCodec.instance.encode(decoded)),
        envelope,
        reason: golden['id'] as String,
      );
      expect(decoded.methodDescriptor.method, golden['method']);
      covered.add(golden['id']! as String);
    }

    expect(
      covered.where((id) => id.startsWith('request:')),
      hasLength(69),
    );
    expect(
      covered.where((id) => id.startsWith('response:')),
      hasLength(69),
    );
    expect(
      covered.where((id) => id.startsWith('notification:')),
      hasLength(26),
    );
  });

  test('generated samples cover every named model validator', () {
    final samples = fixture['definitionSamples']! as Map<String, Object?>;
    expect(samples.keys.toSet(), lspDefinitionClassifications.keys.toSet());
    for (final entry in samples.entries) {
      expect(
        LspModelRegistry.instance.validateNamed(entry.key, entry.value),
        entry.value,
        reason: entry.key,
      );
    }
  });
}

Uri get _packageRoot {
  final current = Directory.current.absolute.uri;
  return File.fromUri(current.resolve('pubspec.yaml')).existsSync() &&
          current.pathSegments.where((segment) => segment.isNotEmpty).last ==
              'lsp'
      ? current
      : current.resolve('packages/lsp/');
}
