import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';
import 'package:test/test.dart';

void main() {
  test('stream listen, cancel, ordering, duplicate, and late event gates', () {
    final client = _readyClient(maxEvents: 2);
    final listen = client.streams.listen('Isolate');
    expect(
      () => client.streams.listen('Isolate'),
      throwsA(isA<ToolingProtocolStateError>()),
    );
    client.complete(
      id: listen.id,
      method: listen.method,
      result: const <String, Object?>{'type': 'Success'},
    );
    final first = client.streams.accept(
      streamId: 'Isolate',
      event: const <String, Object?>{
        'type': 'Event',
        'kind': 'IsolateStart',
        'timestamp': 1,
      },
    );
    final second = client.streams.accept(
      streamId: 'Isolate',
      event: const <String, Object?>{
        'type': 'Event',
        'kind': 'IsolateExit',
        'timestamp': 2,
      },
    );
    expect([first.sequence, second.sequence], [1, 2]);

    final cancel = client.streams.cancel('Isolate');
    client.complete(
      id: cancel.id,
      method: cancel.method,
      result: const <String, Object?>{'type': 'Success'},
    );
    expect(
      () => client.streams.accept(
        streamId: 'Isolate',
        event: const <String, Object?>{
          'type': 'Event',
          'kind': 'IsolateExit',
          'timestamp': 3,
        },
      ),
      throwsA(isA<ToolingProtocolStateError>()),
    );
  });
}

VmServiceClient _readyClient({required int maxEvents}) {
  final client = VmServiceClient(maxStreamEvents: maxEvents);
  final version = client.connection.beginVersionQuery();
  client.connection.completeVersionQuery(
    version.id,
    const <String, Object?>{'type': 'Version', 'major': 4, 'minor': 21},
  );
  final protocols = client.connection.beginSupportedProtocolsQuery();
  client.connection.completeSupportedProtocolsQuery(
    protocols.id,
    const <String, Object?>{
      'type': 'ProtocolList',
      'protocols': <Object?>[],
    },
  );
  return client;
}
