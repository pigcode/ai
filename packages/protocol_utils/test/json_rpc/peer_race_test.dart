import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import '../support/chaos_transport.dart';

void main() {
  group('JsonRpcPeer races', () {
    test('cancellation wins once and a later response is diagnostic', () async {
      final transport = ChaosMessageTransport();
      final diagnostics = BoundedProtocolDiagnostics(maxEntries: 4);
      final peer = JsonRpcPeer(
        transport: transport,
        diagnostics: diagnostics,
      );
      final cancellation = ProtocolCancellationSource();

      final result = peer.request(
        'work',
        cancellation: cancellation.signal,
      );
      final request = await transport.takeSent() as JsonRpcRequest;
      expect(cancellation.cancel('caller cancelled'), isTrue);
      expect(cancellation.cancel('again'), isFalse);
      transport.inject(
        JsonRpcSuccessResponse(id: request.id, result: true),
      );

      await expectLater(
        result,
        throwsA(
          isA<ProtocolCancellationException>().having(
            (error) => error.code,
            'code',
            'protocol_cancelled',
          ),
        ),
      );
      await diagnostics.waitForEntries(1);
      expect(diagnostics.entries.single.code, 'late_response');
      expect(peer.pendingRequestCount, 0);
      await peer.close();
    });

    test('zero-duration timeout cleans pending state deterministically',
        () async {
      final transport = ChaosMessageTransport();
      final peer = JsonRpcPeer(transport: transport);

      final result = peer.request('work', timeout: Duration.zero);
      await transport.takeSent();
      await expectLater(
        result,
        throwsA(
          isA<ProtocolTimeoutException>().having(
            (error) => error.code,
            'code',
            'protocol_timeout',
          ),
        ),
      );
      expect(peer.pendingRequestCount, 0);
      await peer.close();
    });

    test('transport close fails every pending request exactly once', () async {
      final transport = ChaosMessageTransport();
      final peer = JsonRpcPeer(transport: transport);
      final first = peer.request('first');
      final second = peer.request('second');
      await transport.takeSent();
      await transport.takeSent();
      final firstExpectation = expectLater(
        first,
        throwsA(isA<ProtocolTransportException>()),
      );
      final secondExpectation = expectLater(
        second,
        throwsA(isA<ProtocolTransportException>()),
      );

      await transport.closeIncoming();

      await firstExpectation;
      await secondExpectation;
      expect(peer.pendingRequestCount, 0);
      await peer.close();
    });

    test('local close is idempotent and interrupts pending requests', () async {
      final transport = ChaosMessageTransport();
      final peer = JsonRpcPeer(transport: transport);
      final result = peer.request('work');
      await transport.takeSent();
      final resultExpectation = expectLater(
        result,
        throwsA(isA<ProtocolTransportException>()),
      );

      await Future.wait<void>(<Future<void>>[peer.close(), peer.close()]);

      await resultExpectation;
      expect(transport.closeCalled, isTrue);
      expect(peer.pendingRequestCount, 0);
    });
  });
}
