import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('reconnect creates a fresh identity and resets negotiated capability',
      () async {
    final firstPair = MemoryTransportPair.create();
    final firstServer = McpServer(
      transport: firstPair.right,
      capabilities: McpServerCapabilities(tools: true),
      handlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'tools/list': (_) => <String, Object?>{'tools': <Object?>[]},
          'tools/call': (_) => <String, Object?>{'content': <Object?>[]},
        },
      ),
      serverInfo: const <String, Object?>{
        'name': 'first',
        'version': '1.0.0',
      },
    );
    final client = McpClient(
      transport: firstPair.left,
      capabilities: McpClientCapabilities(),
      handlers: McpHandlerSet(),
      clientInfo: const <String, Object?>{
        'name': 'client',
        'version': '1.0.0',
      },
    );
    await client.initialize();
    expect(client.negotiatedCapabilities!.server.tools, isTrue);

    final secondPair = MemoryTransportPair.create();
    final secondServer = McpServer(
      transport: secondPair.right,
      capabilities: McpServerCapabilities(),
      handlers: McpHandlerSet(),
      serverInfo: const <String, Object?>{
        'name': 'second',
        'version': '1.0.0',
      },
    );
    final reconnected = await client.reconnect(transport: secondPair.left);

    expect(reconnected, isNot(same(client)));
    expect(reconnected.state, McpConnectionState.disconnected);
    expect(reconnected.negotiatedCapabilities, isNull);
    await reconnected.initialize();
    expect(reconnected.negotiatedCapabilities!.server.tools, isFalse);

    await reconnected.close();
    await firstServer.close();
    await secondServer.close();
  });
}
