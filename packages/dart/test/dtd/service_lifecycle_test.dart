import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';
import 'package:test/test.dart';

void main() {
  test('service registration owns forwarded calls until disconnect', () {
    final client = DtdClient();
    final registration = client.services.register(
      service: 'Example',
      method: 'ping',
      capabilities: const <String, Object?>{'structured': true},
    );
    client.complete(
      id: registration.request.id,
      method: registration.request.method,
      result: const <String, Object?>{'type': 'Success'},
    );
    expect(registration.active, isTrue);

    final call = client.services.acceptForwarded(
      id: 'remote-1',
      method: 'Example.ping',
      params: const <String, Object?>{'value': 1},
    );
    final response = client.services.completeForwarded(
      call,
      const <String, Object?>{'value': 2},
    );
    expect(response['id'], 'remote-1');
    expect(response['result'], const <String, Object?>{'value': 2});
  });

  test('late forwarded response cannot cross to a replacement owner', () {
    final client = DtdClient();
    final registration = client.services.register(
      service: 'Example',
      method: 'ping',
    );
    client.complete(
      id: registration.request.id,
      method: registration.request.method,
      result: const <String, Object?>{'type': 'Success'},
    );
    final stale = client.services.acceptForwarded(
      id: 'remote-1',
      method: 'Example.ping',
      params: const <String, Object?>{},
    );

    final replacement = client.reconnect();
    final nextRegistration = replacement.services.register(
      service: 'Example',
      method: 'ping',
    );
    replacement.complete(
      id: nextRegistration.request.id,
      method: nextRegistration.request.method,
      result: const <String, Object?>{'type': 'Success'},
    );

    expect(registration.active, isFalse);
    expect(
      () => client.services.completeForwarded(
        stale,
        const <String, Object?>{},
      ),
      throwsA(isA<ToolingProtocolStateError>()),
    );
    expect(nextRegistration.active, isTrue);
  });
}
