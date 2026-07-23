import 'dart:async';

import 'errors.dart';
import 'framing/framer.dart';

/// A caller-owned source and sink of protocol bytes.
abstract interface class ProtocolByteTransport {
  Stream<List<int>> get incomingBytes;
  Future<void> sendBytes(List<int> bytes);
  Future<void> close();
}

/// A caller-owned source and sink of already-framed protocol messages.
abstract interface class ProtocolMessageTransport<T> {
  Stream<T> get incomingMessages;
  Future<void> sendMessage(T message);
  Future<void> close();
}

/// Bridges a caller-owned byte transport through one incremental framer.
final class FramedProtocolTransport<T> implements ProtocolMessageTransport<T> {
  FramedProtocolTransport({
    required this.byteTransport,
    required this.inboundFramer,
    required this.encode,
  }) {
    _messages = StreamController<T>(
      sync: true,
      onPause: () => _byteSubscription.pause(),
      onResume: () => _byteSubscription.resume(),
    );
    _byteSubscription = byteTransport.incomingBytes.listen(
      _handleBytes,
      onError: _handleError,
      onDone: _handleDone,
    );
  }

  final ProtocolByteTransport byteTransport;
  final ProtocolFramer<T> inboundFramer;
  final List<int> Function(T message) encode;
  late final StreamController<T> _messages;
  late final StreamSubscription<List<int>> _byteSubscription;
  bool _closed = false;

  @override
  Stream<T> get incomingMessages => _messages.stream;

  @override
  Future<void> sendMessage(T message) async {
    if (_closed) {
      throw const ProtocolTransportException(
        'transport_closed',
        'Protocol transport is closed.',
      );
    }
    try {
      await byteTransport.sendBytes(
        List<int>.unmodifiable(encode(message)),
      );
    } on ProtocolException {
      rethrow;
    } on Object catch (error) {
      throw ProtocolTransportException(
        'transport_send_failed',
        'Caller-supplied byte transport failed to send.',
        cause: error,
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _byteSubscription.cancel();
    await byteTransport.close();
    if (!_messages.isClosed) {
      // A single-subscription controller's close future waits for a listener
      // that may never attach. Transport shutdown must not depend on one.
      unawaited(_messages.close());
    }
  }

  void _handleBytes(List<int> bytes) {
    if (_closed) {
      return;
    }
    try {
      for (final message in inboundFramer.add(bytes)) {
        _messages.add(message);
      }
    } on Object catch (error, stackTrace) {
      _messages.addError(error, stackTrace);
      unawaited(close());
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    if (_closed) {
      return;
    }
    _messages.addError(
      error is ProtocolException
          ? error
          : ProtocolTransportException(
              'transport_receive_failed',
              'Caller-supplied byte transport failed while receiving.',
              cause: error,
            ),
      stackTrace,
    );
    unawaited(close());
  }

  void _handleDone() {
    if (_closed) {
      return;
    }
    try {
      for (final message in inboundFramer.close()) {
        _messages.add(message);
      }
    } on Object catch (error, stackTrace) {
      _messages.addError(error, stackTrace);
    }
    _closed = true;
    unawaited(_messages.close());
  }
}
