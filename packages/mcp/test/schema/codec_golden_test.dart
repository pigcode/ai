import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/golden/stable_messages.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('round-trips every stable role and method family', () {
    final cases =
        (fixture['cases']! as List<Object?>).cast<Map<String, Object?>>();

    expect(cases, hasLength(64));
    for (final golden in cases) {
      final source = jsonEncode(golden['envelope']);
      final method = golden['responseMethod'] as String?;
      late final McpDecodedMessage decoded;
      try {
        decoded = switch (golden['role']) {
          'clientRequest' => McpCodec.instance.decodeClientRequest(source),
          'serverRequest' => McpCodec.instance.decodeServerRequest(source),
          'clientNotification' =>
            McpCodec.instance.decodeClientNotification(source),
          'serverNotification' =>
            McpCodec.instance.decodeServerNotification(source),
          'clientResult' => McpCodec.instance.decodeClientResult(
              source,
              responseMethod: method!,
            ),
          'serverResult' => McpCodec.instance.decodeServerResult(
              source,
              responseMethod: method!,
            ),
          final Object? role => throw StateError('Unknown role: $role'),
        };
      } on McpCodecException catch (error) {
        final schemaError = error.cause;
        fail(
          '${golden['id']} failed: ${error.code}; '
          'schema=${schemaError is McpSchemaException ? schemaError.code : schemaError}; '
          'path=${schemaError is McpSchemaException ? schemaError.instancePath : null}',
        );
      }
      expect(
        jsonDecode(McpCodec.instance.encode(decoded)),
        golden['envelope'],
        reason: golden['id'] as String,
      );
      expect(decoded.methodBinding.method, golden['method']);
    }
  });

  test('validator accepts a generated sample for all 145 definitions', () {
    final samples = fixture['definitionSamples']! as Map<String, Object?>;

    expect(samples.keys.toSet(), McpSchema.instance.definitionNames);
    for (final entry in samples.entries) {
      try {
        expect(
          McpSchema.instance.validateDefinition(entry.key, entry.value),
          entry.value,
          reason: entry.key,
        );
      } on McpSchemaException catch (error) {
        fail(
          '${entry.key} failed: ${error.code}; '
          'path=${error.instancePath}; sample=${entry.value}',
        );
      }
    }
  });
}
