import 'dart:async';

import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('session cancellation is independent from request-id cancellation',
      () async {
    final pair = MemoryTransportPair.create();
    final promptStarted = Completer<ProtocolCancellationSignal>();
    final sessionCancelled = Completer<void>();
    final promptResult = Completer<JsonValue>();
    final agent = AcpAgent(
      transport: pair.right,
      capabilities: AcpAgentCapabilities(),
      handlers: AcpHandlerSet(
        requests: <String, AcpRequestHandler>{
          'session/prompt': (invocation) {
            promptStarted.complete(invocation.cancellation);
            return promptResult.future;
          },
        },
        notifications: <String, AcpNotificationHandler>{
          'session/cancel': (_) => sessionCancelled.complete(),
        },
      ),
    );
    final diagnostics = BoundedProtocolDiagnostics(maxEntries: 8);
    final client = AcpClient(
      transport: pair.left,
      capabilities: AcpClientCapabilities(),
      handlers: AcpHandlerSet(),
      diagnostics: diagnostics,
    );
    await client.initialize();

    final requestCancellation = ProtocolCancellationSource();
    final pending = client.prompt(
      AcpPromptRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'prompt': <Object?>[],
        },
      ),
      requestCancellation: requestCancellation.signal,
    );
    final inboundSignal = await promptStarted.future;

    await client.cancelSession('session-1');
    await sessionCancelled.future;
    expect(inboundSignal.isCancelled, isFalse);

    requestCancellation.cancel('request-id cancellation');
    await expectLater(
      pending,
      throwsA(isA<ProtocolCancellationException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(inboundSignal.isCancelled, isTrue);
    expect(
      diagnostics.entries
          .where((entry) => entry.code == 'acp_unmatched_cancelled_prompt'),
      isEmpty,
    );

    promptResult.complete(<String, Object?>{'stopReason': 'cancelled'});
    await client.close();
    await agent.close();
  });

  test('diagnoses cancelled wire fact without a local session intent',
      () async {
    final pair = MemoryTransportPair.create();
    final diagnostics = BoundedProtocolDiagnostics(maxEntries: 8);
    final agent = AcpAgent(
      transport: pair.right,
      capabilities: AcpAgentCapabilities(),
      handlers: AcpHandlerSet(
        requests: <String, AcpRequestHandler>{
          'session/prompt': (_) => <String, Object?>{'stopReason': 'cancelled'},
        },
      ),
    );
    final client = AcpClient(
      transport: pair.left,
      capabilities: AcpClientCapabilities(),
      handlers: AcpHandlerSet(),
      diagnostics: diagnostics,
    );
    await client.initialize();

    final result = await client.prompt(
      AcpPromptRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'prompt': <Object?>[],
        },
      ),
    );

    expect(result.stopReason, 'cancelled');
    expect(
      diagnostics.entries.single.code,
      'acp_unmatched_cancelled_prompt',
    );
    await client.close();
    await agent.close();
  });
}
