import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';
import 'package:test/test.dart';

void main() {
  test('RPC, result, error, event, and Sentinel goldens decode', () {
    final request = VmServiceCodec.instance.decode(
      '{"jsonrpc":"2.0","id":"1","method":"getVersion","params":{}}',
    );
    expect(request.kind, VmServiceMessageKind.request);

    final result = VmServiceCodec.instance.decode(
      '{"jsonrpc":"2.0","id":"1","result":'
      '{"type":"Version","major":4,"minor":21}}',
      requestMethod: 'getVersion',
    );
    expect(result.kind, VmServiceMessageKind.response);

    final error = VmServiceCodec.instance.decode(
      '{"jsonrpc":"2.0","id":"2","error":'
      '{"code":105,"message":"Isolate must be runnable","data":{}}}',
      requestMethod: 'resume',
    );
    expect(error.kind, VmServiceMessageKind.response);

    final event = VmServiceCodec.instance.decode(
      '{"jsonrpc":"2.0","method":"streamNotify","params":'
      '{"streamId":"Isolate","event":{"type":"Event",'
      '"kind":"TimerSignificantlyOverdue","timestamp":1}}}',
    );
    expect(event.kind, VmServiceMessageKind.event);

    final sentinel = VmServiceCodec.instance.decode(
      '{"jsonrpc":"2.0","id":"3","result":'
      '{"type":"Sentinel","kind":"Expired","valueAsString":"<expired>"}}',
      requestMethod: 'getObject',
    );
    expect(sentinel.result, isA<VmServiceSentinel>());
  });

  test('rejects malformed fixed envelopes', () {
    expect(
      () => VmServiceCodec.instance.decode(
        '{"jsonrpc":"2.0","id":"1","method":"getVersion","params":[]}',
      ),
      throwsA(isA<ToolingSchemaError>()),
    );
    expect(
      () => VmServiceCodec.instance.decode(
        '{"jsonrpc":"2.0","id":"1","result":'
        '{"type":"Version","major":4,"minor":21}}',
      ),
      throwsA(isA<ToolingCodecError>()),
    );
  });
}
