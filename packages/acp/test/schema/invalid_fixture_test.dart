import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:test/test.dart';

void main() {
  test('preserves unknown optional fields in immutable typed values', () {
    final source = <String, Object?>{
      'protocolVersion': 1,
      'futureOptional': <String, Object?>{'enabled': true},
    };

    final value = AcpInitializeRequest.fromJson(source);
    (source['futureOptional']! as Map<String, Object?>)['enabled'] = false;

    expect(value.toJson(), <String, Object?>{
      'protocolVersion': 1,
      'futureOptional': <String, Object?>{'enabled': true},
    });
    expect(
      () => (value.toJson()! as Map<String, Object?>)['new'] = true,
      throwsUnsupportedError,
    );
  });

  test('keeps unknown values for schema-defined open enums', () {
    final value = AcpErrorCode.fromJson(-31999);

    expect(value.toJson(), -31999);
  });

  test('rejects missing required fields', () {
    expect(
      () => AcpInitializeRequest.fromJson(<String, Object?>{}),
      throwsA(
        isA<AcpSchemaException>().having(
          (error) => error.code,
          'code',
          'acp_schema_invalid',
        ),
      ),
    );
  });

  test('rejects stable methods on the wrong role', () {
    const initialize = '{"jsonrpc":"2.0","id":1,"method":"initialize",'
        '"params":{"protocolVersion":1}}';
    const reverse = '{"jsonrpc":"2.0","id":2,"method":"fs/read_text_file",'
        '"params":{"sessionId":"s","path":"README.md"}}';
    const unstable = '{"jsonrpc":"2.0","id":3,"method":"session/unstable_fork",'
        '"params":{}}';

    expect(AcpCodec.instance.decodeClientMessage(initialize),
        isA<AcpDecodedMessage>());
    expect(AcpCodec.instance.decodeAgentMessage(reverse),
        isA<AcpDecodedMessage>());
    expect(
      () => AcpCodec.instance.decodeAgentMessage(initialize),
      throwsA(
        isA<AcpCodecException>().having(
          (error) => error.code,
          'code',
          'acp_wrong_role',
        ),
      ),
    );
    expect(
      () => AcpCodec.instance.decodeClientMessage(unstable),
      throwsA(
        isA<AcpCodecException>().having(
          (error) => error.code,
          'code',
          'acp_unknown_stable_method',
        ),
      ),
    );
  });
}
