import 'dart:convert';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('rejects empty and invalid role validation roots', () {
    expect(
      () => McpSchema.instance.validateRole('', <String, Object?>{}),
      throwsA(
        isA<McpSchemaException>().having(
          (error) => error.code,
          'code',
          'mcp_unknown_role',
        ),
      ),
    );
    expect(
      () => McpSchema.instance.validateRole(
        'ClientRequest',
        <String, Object?>{},
      ),
      throwsA(isA<McpSchemaException>()),
    );
  });

  test('rejects wrong roles and draft or RC initialize versions', () {
    Map<String, Object?> initialize(String version) => <String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': <String, Object?>{
            'protocolVersion': version,
            'capabilities': <String, Object?>{},
            'clientInfo': <String, Object?>{
              'name': 'test',
              'version': '1.0.0',
            },
          },
        };
    final stable = jsonEncode(initialize('2025-11-25'));

    expect(
      McpCodec.instance.decodeClientRequest(stable),
      isA<McpDecodedMessage>(),
    );
    expect(
      () => McpCodec.instance.decodeServerRequest(stable),
      throwsA(
        isA<McpCodecException>().having(
          (error) => error.code,
          'code',
          'mcp_wrong_role',
        ),
      ),
    );
    for (final version in <String>['2025-06-18', '2025-11-25-rc.1']) {
      expect(
        () => McpCodec.instance.decodeClientRequest(
          jsonEncode(initialize(version)),
        ),
        throwsA(
          isA<McpCodecException>().having(
            (error) => error.code,
            'code',
            'mcp_protocol_version_mismatch',
          ),
        ),
      );
    }
  });

  test('preserves unknown values in schema-defined open string fields', () {
    final value = McpCreateMessageResult.fromJson(
      <String, Object?>{
        'content': <String, Object?>{'type': 'text', 'text': 'done'},
        'model': 'fixed',
        'role': 'assistant',
        'stopReason': 'provider_future_reason',
      },
    );

    expect(
      (value.toJson()! as Map<String, Object?>)['stopReason'],
      'provider_future_reason',
    );
  });
}
