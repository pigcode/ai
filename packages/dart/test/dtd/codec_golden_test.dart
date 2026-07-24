import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';
import 'package:test/test.dart';

void main() {
  test('JSON-RPC request, result, error, and notification round-trip', () {
    final request = DtdCodec.instance.decode(
      '{"jsonrpc":"2.0","id":"1","method":"streamListen",'
      '"params":{"streamId":"Service"}}',
    );
    expect(request.kind, DtdMessageKind.request);
    expect(request.method, 'streamListen');

    final response = DtdCodec.instance.decode(
      '{"jsonrpc":"2.0","id":"1","result":{"type":"Success"}}',
      requestMethod: 'streamListen',
    );
    expect(response.kind, DtdMessageKind.response);

    final error = DtdCodec.instance.decode(
      '{"jsonrpc":"2.0","id":"2","error":'
      '{"code":103,"message":"already subscribed","data":{}}}',
      requestMethod: 'streamListen',
    );
    expect(error.kind, DtdMessageKind.response);

    final notification = DtdCodec.instance.decode(
      '{"jsonrpc":"2.0","method":"streamNotify","params":'
      '{"streamId":"Service","eventKind":"registered","eventData":{}}}',
    );
    expect(notification.kind, DtdMessageKind.notification);
  });

  test('rejects malformed envelopes and payloads', () {
    expect(
      () => DtdCodec.instance.decode(
        '{"jsonrpc":"1.0","id":"1","method":"streamListen",'
        '"params":{"streamId":"Service"}}',
      ),
      throwsA(isA<ToolingCodecError>()),
    );
    expect(
      () => DtdCodec.instance.decode(
        '{"jsonrpc":"2.0","id":"1","method":"streamListen","params":{}}',
      ),
      throwsA(isA<ToolingSchemaError>()),
    );
    expect(
      () => DtdCodec.instance.decode(
        '{"jsonrpc":"2.0","id":"1","result":{"type":"Success"}}',
      ),
      throwsA(isA<ToolingCodecError>()),
    );
  });
}
