import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('enters operation phase only after exact initialize and notification',
      () async {
    final pair = MemoryTransportPair.create();
    final server = McpServer(
      transport: pair.right,
      capabilities: McpServerCapabilities(),
      handlers: McpHandlerSet(),
      serverInfo: const <String, Object?>{
        'name': 'server',
        'version': '1.0.0',
      },
    );
    final client = McpClient(
      transport: pair.left,
      capabilities: McpClientCapabilities(),
      handlers: McpHandlerSet(),
      clientInfo: const <String, Object?>{
        'name': 'client',
        'version': '1.0.0',
      },
    );

    final snapshot = await client.initialize();

    expect(snapshot.protocolVersion, '2025-11-25');
    expect(client.state, McpConnectionState.initialized);
    expect(server.state, McpConnectionState.initialized);
    await expectLater(
      client.initialize(),
      throwsA(
        isA<McpStateException>().having(
          (error) => error.code,
          'code',
          'mcp_duplicate_initialize',
        ),
      ),
    );
    await client.close();
    await server.close();
  });

  test('rejects operation before initialization', () async {
    final transport = ManualMessageTransport();
    final client = McpClient(
      transport: transport,
      capabilities: McpClientCapabilities(),
      handlers: McpHandlerSet(),
      clientInfo: const <String, Object?>{
        'name': 'client',
        'version': '1.0.0',
      },
    );

    await expectLater(
      client.requestServer('ping', const <String, Object?>{}),
      throwsA(isA<McpStateException>()),
    );
    await client.close();
  });

  test('diagnoses initialized notification before initialize response',
      () async {
    final transport = ManualMessageTransport();
    final diagnostics = BoundedProtocolDiagnostics(maxEntries: 4);
    final server = McpServer(
      transport: transport,
      capabilities: McpServerCapabilities(),
      handlers: McpHandlerSet(),
      serverInfo: const <String, Object?>{
        'name': 'server',
        'version': '1.0.0',
      },
      diagnostics: diagnostics,
    );

    transport.inject(
      JsonRpcNotification(
        method: 'notifications/initialized',
        params: const <String, Object?>{},
      ),
    );
    await diagnostics.next;

    expect(server.state, McpConnectionState.disconnected);
    expect(diagnostics.entries.single.code, 'notification_handler_failed');
    await server.close();
  });

  test('closes client on mismatched server version', () async {
    final transport = ManualMessageTransport();
    final client = McpClient(
      transport: transport,
      capabilities: McpClientCapabilities(),
      handlers: McpHandlerSet(),
      clientInfo: const <String, Object?>{
        'name': 'client',
        'version': '1.0.0',
      },
    );

    final result = client.initialize();
    final request = await transport.takeSent() as JsonRpcRequest;
    transport.inject(
      JsonRpcSuccessResponse(
        id: request.id,
        result: <String, Object?>{
          'protocolVersion': '2025-06-18',
          'capabilities': <String, Object?>{},
          'serverInfo': <String, Object?>{
            'name': 'old',
            'version': '1.0.0',
          },
        },
      ),
    );

    await expectLater(result, throwsA(isA<McpVersionException>()));
    expect(client.state, McpConnectionState.closed);
  });
}
