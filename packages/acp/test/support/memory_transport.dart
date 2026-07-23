import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

final class MemoryTransportPair {
  MemoryTransportPair._(this.left, this.right);

  factory MemoryTransportPair.create() {
    final left = MemoryMessageTransport();
    final right = MemoryMessageTransport();
    left.remote = right;
    right.remote = left;
    return MemoryTransportPair._(left, right);
  }

  final MemoryMessageTransport left;
  final MemoryMessageTransport right;
}

final class MemoryMessageTransport
    implements ProtocolMessageTransport<JsonRpcMessage> {
  final StreamController<JsonRpcMessage> _incoming =
      StreamController<JsonRpcMessage>.broadcast(sync: true);
  late MemoryMessageTransport remote;
  bool _closed = false;

  @override
  Stream<JsonRpcMessage> get incomingMessages => _incoming.stream;

  @override
  Future<void> sendMessage(JsonRpcMessage message) async {
    if (_closed) {
      throw StateError('memory transport closed');
    }
    remote._incoming.add(message);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _incoming.close();
  }
}

final class ManualMessageTransport
    implements ProtocolMessageTransport<JsonRpcMessage> {
  final StreamController<JsonRpcMessage> _incoming =
      StreamController<JsonRpcMessage>.broadcast(sync: true);
  final List<JsonRpcMessage> sent = <JsonRpcMessage>[];
  final List<Completer<JsonRpcMessage>> _waiters =
      <Completer<JsonRpcMessage>>[];

  @override
  Stream<JsonRpcMessage> get incomingMessages => _incoming.stream;

  @override
  Future<void> sendMessage(JsonRpcMessage message) async {
    if (_waiters.isEmpty) {
      sent.add(message);
    } else {
      _waiters.removeAt(0).complete(message);
    }
  }

  Future<JsonRpcMessage> takeSent() {
    if (sent.isNotEmpty) {
      return Future<JsonRpcMessage>.value(sent.removeAt(0));
    }
    final completer = Completer<JsonRpcMessage>();
    _waiters.add(completer);
    return completer.future;
  }

  void inject(JsonRpcMessage message) {
    _incoming.add(message);
  }

  @override
  Future<void> close() => _incoming.close();
}
