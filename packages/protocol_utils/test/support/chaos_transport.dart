import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

final class ChaosMessageTransport
    implements ProtocolMessageTransport<JsonRpcMessage> {
  final StreamController<JsonRpcMessage> _incoming =
      StreamController<JsonRpcMessage>(sync: true);
  final List<JsonRpcMessage> sent = <JsonRpcMessage>[];
  final List<Completer<JsonRpcMessage>> _sentWaiters =
      <Completer<JsonRpcMessage>>[];
  FutureOr<void> Function(JsonRpcMessage message)? onSend;
  bool closeCalled = false;

  @override
  Stream<JsonRpcMessage> get incomingMessages => _incoming.stream;

  @override
  Future<void> sendMessage(JsonRpcMessage message) async {
    if (_sentWaiters.isNotEmpty) {
      _sentWaiters.removeAt(0).complete(message);
    } else {
      sent.add(message);
    }
    await onSend?.call(message);
  }

  Future<JsonRpcMessage> takeSent() {
    if (sent.isNotEmpty) {
      return Future<JsonRpcMessage>.value(sent.removeAt(0));
    }
    final completer = Completer<JsonRpcMessage>();
    _sentWaiters.add(completer);
    return completer.future;
  }

  void inject(JsonRpcMessage message) {
    _incoming.add(message);
  }

  void injectError(Object error) {
    _incoming.addError(error);
  }

  Future<void> closeIncoming() => _incoming.close();

  @override
  Future<void> close() async {
    closeCalled = true;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}

final class ChaosByteTransport implements ProtocolByteTransport {
  final StreamController<List<int>> incomingController =
      StreamController<List<int>>(sync: true);
  final List<List<int>> sent = <List<int>>[];
  bool closeCalled = false;

  @override
  Stream<List<int>> get incomingBytes => incomingController.stream;

  @override
  Future<void> sendBytes(List<int> bytes) async {
    sent.add(List<int>.unmodifiable(bytes));
  }

  @override
  Future<void> close() async {
    closeCalled = true;
    if (!incomingController.isClosed) {
      await incomingController.close();
    }
  }
}
