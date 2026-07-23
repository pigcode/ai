import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'memory_transport.dart';

final class InitializedMcpPair {
  const InitializedMcpPair({
    required this.client,
    required this.server,
  });

  final McpClient client;
  final McpServer server;

  Future<void> close() async {
    await client.close();
    await server.close();
  }
}

Future<InitializedMcpPair> createInitializedMcpPair({
  McpClientCapabilities? clientCapabilities,
  McpServerCapabilities? serverCapabilities,
  McpHandlerSet? clientHandlers,
  McpHandlerSet? serverHandlers,
  ProtocolDiagnosticSink? clientDiagnostics,
  ProtocolDiagnosticSink? serverDiagnostics,
}) async {
  final transport = MemoryTransportPair.create();
  final server = McpServer(
    transport: transport.right,
    capabilities: serverCapabilities ?? McpServerCapabilities(),
    handlers: serverHandlers ?? McpHandlerSet(),
    serverInfo: const <String, Object?>{
      'name': 'test-server',
      'version': '1.0.0',
    },
    diagnostics: serverDiagnostics,
  );
  final client = McpClient(
    transport: transport.left,
    capabilities: clientCapabilities ?? McpClientCapabilities(),
    handlers: clientHandlers ?? McpHandlerSet(),
    clientInfo: const <String, Object?>{
      'name': 'test-client',
      'version': '1.0.0',
    },
    diagnostics: clientDiagnostics,
  );
  await client.initialize();
  return InitializedMcpPair(client: client, server: server);
}
