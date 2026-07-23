import 'dart:async';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support/initialized_pair.dart';

void main() {
  test('cancel notification cancels work but still awaits original response',
      () async {
    final started = Completer<void>();
    final cancelled = Completer<void>();
    final finish = Completer<void>();
    final pair = await createInitializedMcpPair(
      serverCapabilities: McpServerCapabilities(tools: true),
      serverHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'tools/list': (_) => const <String, Object?>{'tools': <Object?>[]},
          'tools/call': (invocation) async {
            invocation.cancellation.onCancel((_) {
              if (!cancelled.isCompleted) {
                cancelled.complete();
              }
            });
            started.complete();
            await finish.future;
            return const <String, Object?>{
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': 'late success'},
              ],
            };
          },
        },
      ),
    );
    final source = ProtocolCancellationSource();
    var completed = false;
    final response = pair.client
        .callTool(
          McpCallToolRequestParams.fromJson(
            const <String, Object?>{'name': 'slow'},
          ),
          cancellation: source.signal,
        )
        .whenComplete(() => completed = true);

    await started.future;
    expect(source.cancel('no longer needed'), isTrue);
    await cancelled.future;
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    finish.complete();
    expect(
      (await response).toJson(),
      containsPair('content', isNotEmpty),
    );
    expect(completed, isTrue);
    await pair.close();
  });

  test('unknown and duplicate request IDs diagnose without cross-cancelling',
      () async {
    final diagnostics = BoundedProtocolDiagnostics(maxEntries: 16);
    final started = Completer<void>();
    final finish = Completer<void>();
    var actualCancelled = false;
    final pair = await createInitializedMcpPair(
      serverCapabilities: McpServerCapabilities(tools: true),
      serverDiagnostics: diagnostics,
      serverHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'tools/list': (_) => const <String, Object?>{'tools': <Object?>[]},
          'tools/call': (invocation) async {
            invocation.cancellation.onCancel((_) => actualCancelled = true);
            started.complete();
            await finish.future;
            return const <String, Object?>{'content': <Object?>[]};
          },
        },
      ),
    );
    final pending = pair.client.connection.startRequestRemote(
      'tools/call',
      const <String, Object?>{'name': 'slow'},
    );
    await started.future;

    await pair.client.notifyServer(
      'notifications/cancelled',
      const <String, Object?>{'requestId': 999999},
    );
    await pair.client.notifyServer(
      'notifications/cancelled',
      const <String, Object?>{'requestId': 999999},
    );
    expect(actualCancelled, isFalse);
    expect(pending.id, isA<JsonRpcIntegerId>());

    await pair.client.notifyServer(
      'notifications/cancelled',
      <String, Object?>{'requestId': pending.id.toJson()},
    );
    expect(actualCancelled, isTrue);
    await pair.client.notifyServer(
      'notifications/cancelled',
      <String, Object?>{'requestId': pending.id.toJson()},
    );
    finish.complete();
    await pending.response;

    expect(
      diagnostics.entries
          .where(
            (entry) => entry.code == 'mcp_cancel_unknown_or_duplicate_request',
          )
          .length,
      3,
    );
    await pair.close();
    await diagnostics.dispose();
  });
}
