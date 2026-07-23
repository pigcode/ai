import 'dart:async';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

Future<void> main() async {
  final pair = _MemoryTransportPair.create();
  final server = McpServer(
    transport: pair.server,
    capabilities: McpServerCapabilities(tools: true),
    handlers: McpHandlerSet(
      requests: <String, McpRequestHandler>{
        'tools/list': (_) => const <String, Object?>{
              'tools': <Object?>[
                <String, Object?>{
                  'name': 'echo',
                  'inputSchema': <String, Object?>{'type': 'object'},
                },
              ],
            },
        'tools/call': (invocation) => <String, Object?>{
              'content': <Object?>[
                <String, Object?>{
                  'type': 'text',
                  'text': 'called ${invocation.params}',
                },
              ],
            },
      },
    ),
    serverInfo: const <String, Object?>{
      'name': 'example-server',
      'version': '1.0.0',
    },
  );
  final client = McpClient(
    transport: pair.client,
    capabilities: McpClientCapabilities(),
    handlers: McpHandlerSet(),
    clientInfo: const <String, Object?>{
      'name': 'example-client',
      'version': '1.0.0',
    },
  );

  await client.initialize();
  print((await client.listTools(mcpPageRequest())).toJson());

  await client.close();
  await server.close();
}

final class _MemoryTransportPair {
  const _MemoryTransportPair({
    required this.client,
    required this.server,
  });

  final _MemoryMessageTransport client;
  final _MemoryMessageTransport server;

  static _MemoryTransportPair create() {
    final client = _MemoryMessageTransport();
    final server = _MemoryMessageTransport();
    client.peer = server;
    server.peer = client;
    return _MemoryTransportPair(client: client, server: server);
  }
}

final class _MemoryMessageTransport
    implements ProtocolMessageTransport<JsonRpcMessage> {
  final StreamController<JsonRpcMessage> _incoming =
      StreamController<JsonRpcMessage>(sync: true);
  late final _MemoryMessageTransport peer;

  @override
  Stream<JsonRpcMessage> get incomingMessages => _incoming.stream;

  @override
  Future<void> sendMessage(JsonRpcMessage message) async {
    peer._incoming.add(message);
  }

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}
