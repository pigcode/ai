import 'dart:async';

import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

Future<void> main() async {
  final pair = _MemoryTransportPair.create();
  final agent = AcpAgent(
    transport: pair.agent,
    capabilities: AcpAgentCapabilities(),
    handlers: AcpHandlerSet(
      requests: <String, AcpRequestHandler>{
        'session/new': (_) => const <String, Object?>{
              'sessionId': 'example-session',
            },
      },
    ),
  );
  final client = AcpClient(
    transport: pair.client,
    capabilities: AcpClientCapabilities(),
    handlers: AcpHandlerSet(),
  );

  await client.initialize();
  final session = await client.createSession(
    AcpNewSessionRequest.fromJson(
      const <String, Object?>{
        'cwd': '/workspace',
        'mcpServers': <Object?>[],
      },
    ),
  );
  print(session.toJson());

  await client.close();
  await agent.close();
}

final class _MemoryTransportPair {
  const _MemoryTransportPair({
    required this.client,
    required this.agent,
  });

  final _MemoryMessageTransport client;
  final _MemoryMessageTransport agent;

  static _MemoryTransportPair create() {
    final client = _MemoryMessageTransport();
    final agent = _MemoryMessageTransport();
    client.peer = agent;
    agent.peer = client;
    return _MemoryTransportPair(client: client, agent: agent);
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
