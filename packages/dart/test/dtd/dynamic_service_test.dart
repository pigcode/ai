import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';
import 'package:test/test.dart';

void main() {
  test('dynamic service envelope preserves validated JSON extensions', () {
    final request = DtdCodec.instance.decode(
      '{"jsonrpc":"2.0","id":"9","method":"Example.deep.method",'
      '"params":{"value":3,"future":{"enabled":true}}}',
    );

    expect(request.kind, DtdMessageKind.request);
    expect(request.method, 'Example.deep.method');
    expect(request.envelope['params'], const <String, Object?>{
      'value': 3,
      'future': <String, Object?>{'enabled': true},
    });
    expect(
      () => DtdCodec.instance.decode(
        '{"jsonrpc":"2.0","id":"9","method":"NoDot","params":{}}',
      ),
      throwsA(isA<ToolingCodecError>()),
    );
  });
}
