import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

Future<void> main() async {
  final pair = _MemoryTransportPair.create();
  final server = JsonRpcPeer(
    transport: pair.server,
    requestHandlers: <String, JsonRpcRequestHandler>{
      'echo': (request, _) => request.params,
    },
  );
  final client = JsonRpcPeer(transport: pair.client);

  final result = await client.request(
    'echo',
    params: const <String, Object?>{'text': 'hello'},
  );
  print(result);

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
