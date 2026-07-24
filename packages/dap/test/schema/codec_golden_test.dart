import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  final fixture = jsonDecode(
    File.fromUri(_packageRoot.resolve('test/fixtures/golden/messages.json'))
        .readAsStringSync(),
  ) as Map<String, Object?>;

  test('round-trips every concrete request, response, and event', () {
    final cases =
        (fixture['cases']! as List<Object?>).cast<Map<String, Object?>>();
    expect(cases, hasLength(107));
    for (final golden in cases) {
      final envelope = golden['envelope']! as Map<String, Object?>;
      final decoded = DapCodec.instance.decode(
        jsonEncode(envelope),
        requestCommand: golden['requestCommand'] as String?,
      );
      expect(
        jsonDecode(DapCodec.instance.encode(decoded)),
        envelope,
        reason: golden['id'] as String,
      );
      expect(decoded.name, golden['name']);
    }
  });

  test('generated samples cover every named validator', () {
    final samples = fixture['definitionSamples']! as Map<String, Object?>;
    expect(samples.keys.toSet(), dapDefinitionClassifications.keys.toSet());
    for (final entry in samples.entries) {
      expect(
        DapModelRegistry.instance.validateNamed(entry.key, entry.value),
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
              'dap'
      ? current
      : current.resolve('packages/dap/');
}
