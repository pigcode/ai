import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';
import 'package:test/test.dart';

void main() {
  test('listen, notify, post, and cancel preserve stream state', () {
    final client = DtdClient(maxStreamEvents: 2);
    final listen = client.streams.listen('Example');
    expect(listen.method, 'streamListen');
    expect(
      () => client.streams.listen('Example'),
      throwsA(isA<ToolingProtocolStateError>()),
    );
    client.complete(
      id: listen.id,
      method: listen.method,
      result: const <String, Object?>{'type': 'Success'},
    );
    expect(client.streams.isListening('Example'), isTrue);

    final event = client.streams.acceptNotification(
      const <String, Object?>{
        'streamId': 'Example',
        'eventKind': 'changed',
        'eventData': <String, Object?>{'value': 1},
      },
    );
    expect(event.sequence, 1);
    expect(event.eventKind, 'changed');

    final post = client.streams.post(
      streamId: 'Example',
      eventKind: 'outbound',
      eventData: const <String, Object?>{'value': 2},
    );
    expect(post.method, 'postEvent');

    final cancel = client.streams.cancel('Example');
    client.complete(
      id: cancel.id,
      method: cancel.method,
      result: const <String, Object?>{'type': 'Success'},
    );
    expect(client.streams.isListening('Example'), isFalse);
  });

  test('stream event queue is bounded', () {
    final client = DtdClient(maxStreamEvents: 1);
    final listen = client.streams.listen('Example');
    client.complete(
      id: listen.id,
      method: listen.method,
      result: const <String, Object?>{'type': 'Success'},
    );
    const notification = <String, Object?>{
      'streamId': 'Example',
      'eventKind': 'changed',
      'eventData': <String, Object?>{},
    };
    client.streams.acceptNotification(notification);
    expect(
      () => client.streams.acceptNotification(notification),
      throwsA(isA<ToolingResourceLimitError>()),
    );
  });
}
