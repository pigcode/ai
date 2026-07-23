import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import '../support/chaos_transport.dart';

void main() {
  group('JsonRpcPeer', () {
    test('registers a request before send and correlates its response',
        () async {
      final transport = ChaosMessageTransport();
      late JsonRpcPeer peer;
      transport.onSend = (message) {
        expect(peer.pendingRequestCount, 1);
        final request = message as JsonRpcRequest;
        transport.inject(
          JsonRpcSuccessResponse(
            id: request.id,
            result: <String, Object?>{'ok': true},
          ),
        );
      };
      peer = JsonRpcPeer(transport: transport);

      await expectLater(
        peer.request('ping'),
        completion(<String, Object?>{'ok': true}),
      );
      expect(peer.pendingRequestCount, 0);
      await peer.close();
    });

    test('rolls registration back when send fails', () async {
      final transport = ChaosMessageTransport()
        ..onSend = (_) => throw StateError('synthetic send failure');
      final peer = JsonRpcPeer(transport: transport);

      await expectLater(
        peer.request('ping'),
        throwsA(
          isA<ProtocolTransportException>().having(
            (error) => error.code,
            'code',
            'transport_send_failed',
          ),
        ),
      );
      expect(peer.pendingRequestCount, 0);
      await peer.close();
    });

    test('preserves typed transport errors for pending requests', () async {
      final transport = ChaosMessageTransport();
      final peer = JsonRpcPeer(transport: transport);
      final pending = peer.request('ping');
      await transport.takeSent();

      transport.injectError(
        const ProtocolTransportException(
          'typed_transport_failure',
          'Synthetic typed transport failure.',
        ),
      );

      await expectLater(
        pending,
        throwsA(
          isA<ProtocolTransportException>().having(
            (error) => error.code,
            'code',
            'typed_transport_failure',
          ),
        ),
      );
      await peer.close();
    });

    test('dispatches reverse requests and converts handler errors', () async {
      final transport = ChaosMessageTransport();
      final peer = JsonRpcPeer(
        transport: transport,
        requestHandlers: <String, JsonRpcRequestHandler>{
          'roots/list': (request, cancellation) {
            expect(cancellation.isCancelled, isFalse);
            return <String, Object?>{'roots': <Object?>[]};
          },
          'explode': (request, cancellation) {
            throw StateError('private implementation detail');
          },
        },
      );

      transport.inject(
        JsonRpcRequest(
          id: JsonRpcIntegerId(40),
          method: 'roots/list',
        ),
      );
      final success = await transport.takeSent();
      expect(success, isA<JsonRpcSuccessResponse>());
      expect(
        (success as JsonRpcSuccessResponse).result,
        <String, Object?>{'roots': <Object?>[]},
      );

      transport.inject(
        JsonRpcRequest(
          id: JsonRpcIntegerId(41),
          method: 'explode',
        ),
      );
      final failure = await transport.takeSent();
      expect(failure, isA<JsonRpcErrorResponse>());
      final error = (failure as JsonRpcErrorResponse).error;
      expect(error.code, -32603);
      expect(error.message, 'Internal error');
      expect(error.toString(), isNot(contains('private implementation')));
      await peer.close();
    });

    test('converts non-JSON handler error data to an internal error', () async {
      final transport = ChaosMessageTransport();
      final diagnostics = BoundedProtocolDiagnostics(maxEntries: 4);
      final peer = JsonRpcPeer(
        transport: transport,
        diagnostics: diagnostics,
        requestHandlers: <String, JsonRpcRequestHandler>{
          'invalid-error': (request, cancellation) {
            throw JsonRpcHandlerException(
              code: -32000,
              message: 'Invalid data',
              hasData: true,
              data: Object(),
            );
          },
        },
      );

      transport.inject(
        JsonRpcRequest(
          id: JsonRpcIntegerId(42),
          method: 'invalid-error',
        ),
      );

      final failure = await transport.takeSent() as JsonRpcErrorResponse;
      expect(failure.error.code, -32603);
      expect(failure.error.message, 'Internal error');
      expect(failure.error.hasData, isFalse);
      expect(
        diagnostics.entries.single.code,
        'invalid_handler_error_data',
      );
      await peer.close();
    });

    test('notification handler failures are diagnostic-only', () async {
      final transport = ChaosMessageTransport();
      final diagnostics = BoundedProtocolDiagnostics(maxEntries: 4);
      final peer = JsonRpcPeer(
        transport: transport,
        diagnostics: diagnostics,
        notificationHandlers: <String, JsonRpcNotificationHandler>{
          'notifications/progress': (_) {
            throw StateError('synthetic handler failure');
          },
        },
      );

      transport.inject(
        JsonRpcNotification(method: 'notifications/progress'),
      );
      await diagnostics.next;

      expect(transport.sent, isEmpty);
      expect(
        diagnostics.entries.single.code,
        'notification_handler_failed',
      );
      await peer.close();
    });

    test('classifies duplicate, unknown, and late responses', () async {
      final transport = ChaosMessageTransport();
      final diagnostics = BoundedProtocolDiagnostics(maxEntries: 8);
      final peer = JsonRpcPeer(
        transport: transport,
        diagnostics: diagnostics,
      );

      final firstFuture = peer.request('first');
      final first = await transport.takeSent() as JsonRpcRequest;
      transport.inject(
        JsonRpcSuccessResponse(id: first.id, result: true),
      );
      expect(await firstFuture, isTrue);
      transport.inject(
        JsonRpcSuccessResponse(id: first.id, result: false),
      );
      transport.inject(
        JsonRpcSuccessResponse(
          id: JsonRpcIntegerId(999),
          result: false,
        ),
      );

      final cancellation = ProtocolCancellationSource();
      final cancelledFuture = peer.request(
        'cancelled',
        cancellation: cancellation.signal,
      );
      final cancelled = await transport.takeSent() as JsonRpcRequest;
      cancellation.cancel();
      await expectLater(
        cancelledFuture,
        throwsA(isA<ProtocolCancellationException>()),
      );
      transport.inject(
        JsonRpcSuccessResponse(id: cancelled.id, result: true),
      );

      await diagnostics.waitForEntries(3);
      expect(
        diagnostics.entries.map((entry) => entry.code),
        <String>[
          'duplicate_response',
          'unknown_response',
          'late_response',
        ],
      );
      await peer.close();
    });
  });
}
