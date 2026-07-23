import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support/chaos_transport.dart';

void main() {
  test('pending and outbound queues fail before exceeding their bounds',
      () async {
    final sendBarrier = Completer<void>();
    final transport = ChaosMessageTransport()
      ..onSend = (_) => sendBarrier.future;
    final peer = JsonRpcPeer(
      transport: transport,
      limits: ProtocolLimits(
        maxPendingRequests: 1,
        maxOutboundMessages: 1,
      ),
    );

    final first = peer.request('first');
    await transport.takeSent();
    await expectLater(
      peer.request('second'),
      throwsA(
        isA<JsonRpcPeerException>().having(
          (error) => error.code,
          'code',
          'json_rpc_pending_limit',
        ),
      ),
    );
    await expectLater(
      peer.notify('notification'),
      throwsA(
        isA<JsonRpcPeerException>().having(
          (error) => error.code,
          'code',
          'json_rpc_outbound_backpressure',
        ),
      ),
    );

    final firstExpectation = expectLater(
      first,
      throwsA(isA<ProtocolTransportException>()),
    );
    await peer.close();
    sendBarrier.complete();
    await firstExpectation;
  });

  test('diagnostics and tombstones remain bounded', () async {
    final transport = ChaosMessageTransport();
    final diagnostics = BoundedProtocolDiagnostics(maxEntries: 2);
    final peer = JsonRpcPeer(
      transport: transport,
      diagnostics: diagnostics,
      limits: ProtocolLimits(
        maxDiagnostics: 2,
        maxTombstones: 1,
      ),
    );

    for (var id = 100; id < 103; id += 1) {
      transport.inject(
        JsonRpcSuccessResponse(
          id: JsonRpcIntegerId(id),
          result: true,
        ),
      );
    }
    await diagnostics.waitForEntries(2);
    expect(diagnostics.entries, hasLength(2));
    expect(diagnostics.droppedCount, 1);

    for (var index = 0; index < 2; index += 1) {
      final result = peer.request('request-$index');
      final request = await transport.takeSent() as JsonRpcRequest;
      transport.inject(
        JsonRpcSuccessResponse(id: request.id, result: index),
      );
      expect(await result, index);
    }
    expect(peer.tombstoneCount, 1);
    await peer.close();
  });

  test('framed transport pauses caller bytes for a slow subscriber', () async {
    final bytes = ChaosByteTransport();
    final framer = NdjsonFramer();
    final transport = FramedProtocolTransport<String>(
      byteTransport: bytes,
      inboundFramer: framer,
      encode: (message) => utf8.encode('$message\n'),
    );
    final received = <String>[];
    final subscription = transport.incomingMessages.listen(received.add);

    subscription.pause();
    expect(bytes.incomingController.isPaused, isTrue);
    bytes.incomingController.add(utf8.encode('one\n'));
    expect(framer.bufferedByteCount, 0);

    subscription.resume();
    await Future<void>.delayed(Duration.zero);
    expect(received, <String>['one']);

    await subscription.cancel();
    await transport.close();
  });

  test('framed transport preserves typed receive errors', () async {
    final bytes = ChaosByteTransport();
    final transport = FramedProtocolTransport<String>(
      byteTransport: bytes,
      inboundFramer: NdjsonFramer(),
      encode: (message) => utf8.encode('$message\n'),
    );
    final receivedError = Completer<Object>();
    transport.incomingMessages.listen(
      (_) {},
      onError: receivedError.complete,
    );

    bytes.incomingController.addError(
      const ProtocolTransportException(
        'typed_receive_failure',
        'Synthetic typed receive failure.',
      ),
    );

    await expectLater(
      receivedError.future,
      completion(
        isA<ProtocolTransportException>().having(
          (error) => error.code,
          'code',
          'typed_receive_failure',
        ),
      ),
    );
    await transport.close();
  });
}
