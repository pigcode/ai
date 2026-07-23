import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:test/test.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/golden/stable_messages.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('round-trips every stable request, result, and notification family', () {
    final cases =
        (fixture['cases']! as List<Object?>).cast<Map<String, Object?>>();
    final coveredDefinitions = <String>{};

    expect(cases, hasLength(43));
    for (final golden in cases) {
      final envelope = golden['envelope']! as Map<String, Object?>;
      final source = jsonEncode(envelope);
      final responseMethod = golden['responseMethod'] as String?;
      late final AcpDecodedMessage decoded;
      try {
        decoded = switch (golden['root']) {
          'agent' => AcpCodec.instance.decodeAgentMessage(
              source,
              responseMethod: responseMethod,
            ),
          'client' => AcpCodec.instance.decodeClientMessage(
              source,
              responseMethod: responseMethod,
            ),
          'protocolLevel' => AcpCodec.instance.decodeProtocolMessage(source),
          final Object? root => throw StateError('Unknown golden root: $root'),
        };
      } on AcpCodecException catch (error) {
        final schemaError = error.cause;
        fail(
          '${golden['id']} failed: ${error.code}; '
          'schema=${schemaError is AcpSchemaException ? schemaError.code : schemaError}; '
          'path=${schemaError is AcpSchemaException ? schemaError.instancePath : null}',
        );
      }

      expect(
        jsonDecode(AcpCodec.instance.encode(decoded)),
        envelope,
        reason: golden['id'] as String,
      );
      expect(decoded.methodDescriptor?.method, golden['method']);
      coveredDefinitions.add(golden['definition']! as String);
    }

    final expectedDefinitions = <String>{
      for (final descriptor in acpMethodDescriptors)
        ...<String?>[
          descriptor.requestDefinition,
          descriptor.responseDefinition,
          descriptor.notificationDefinition,
        ].whereType<String>(),
    };
    expect(coveredDefinitions, expectedDefinitions);
  });

  test('validator registry accepts a generated sample for every definition',
      () {
    final samples = fixture['definitionSamples']! as Map<String, Object?>;

    expect(samples.keys.toSet(), AcpSchema.instance.definitionNames);
    for (final entry in samples.entries) {
      try {
        expect(
          AcpSchema.instance.validateDefinition(entry.key, entry.value),
          entry.value,
          reason: entry.key,
        );
      } on AcpSchemaException catch (error) {
        fail(
          '${entry.key} failed: ${error.code}; path=${error.instancePath}; '
          'sample=${entry.value}',
        );
      }
    }
  });
}
