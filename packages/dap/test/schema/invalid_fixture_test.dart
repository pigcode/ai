import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('rejects unknown envelope types and invalid sequences', () {
    expect(
      () => DapCodec.instance.decode('{"seq":1,"type":"future"}'),
      throwsA(isA<DapCodecException>()),
    );
    expect(
      () => DapCodec.instance.decode(
        '{"seq":0,"type":"event","event":"initialized"}',
      ),
      throwsA(isA<DapCodecException>()),
    );
  });

  test('rejects missing allOf fields and response correlation mismatches', () {
    expect(
      () => DapCodec.instance.decode(
        '{"seq":1,"type":"request","command":"initialize"}',
      ),
      throwsA(isA<DapSchemaException>()),
    );
    expect(
      () => DapCodec.instance.decode(
        '{"seq":2,"type":"response","request_seq":1,"success":true,'
        '"command":"launch"}',
        requestCommand: 'initialize',
      ),
      throwsA(
        isA<DapCodecException>().having(
          (error) => error.code,
          'code',
          'dap_response_command_mismatch',
        ),
      ),
    );
    expect(
      () => DapCodec.instance.decode(
        '{"seq":2,"type":"response","request_seq":0,"success":true,'
        '"command":"initialize"}',
        requestCommand: 'initialize',
      ),
      throwsA(isA<DapCodecException>()),
    );
  });

  test('rejects unknown closed enumeration values', () {
    expect(
      () => DapCompletionItemType.fromJson('future'),
      throwsA(isA<DapSchemaException>()),
    );
  });
}
