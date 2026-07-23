import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// Wraps caller-owned bytes in ACP stable NDJSON framing.
ProtocolMessageTransport<JsonRpcMessage> createAcpNdjsonTransport({
  required ProtocolByteTransport byteTransport,
  ProtocolLimits? limits,
}) {
  final resolvedLimits = limits ?? ProtocolLimits.defaults;
  const codec = JsonRpcCodec();
  return FramedProtocolTransport<JsonRpcMessage>(
    byteTransport: byteTransport,
    inboundFramer: _AcpNdjsonMessageFramer(
      limits: resolvedLimits,
      codec: codec,
    ),
    encode: (message) => utf8.encode('${codec.encode(message)}\n'),
  );
}

final class _AcpNdjsonMessageFramer implements ProtocolFramer<JsonRpcMessage> {
  _AcpNdjsonMessageFramer({
    required ProtocolLimits limits,
    required this.codec,
  }) : _delegate = NdjsonFramer(limits: limits);

  final JsonRpcCodec codec;
  final NdjsonFramer _delegate;
  var _failed = false;

  @override
  int get bufferedByteCount => _delegate.bufferedByteCount;

  @override
  bool get isClosed => _delegate.isClosed;

  @override
  List<JsonRpcMessage> add(List<int> bytes) {
    _ensureUsable();
    try {
      return List<JsonRpcMessage>.unmodifiable(
        _delegate.add(bytes).map(codec.decode),
      );
    } on Object {
      _failed = true;
      rethrow;
    }
  }

  @override
  List<JsonRpcMessage> close() {
    _ensureUsable();
    try {
      return List<JsonRpcMessage>.unmodifiable(
        _delegate.close().map(codec.decode),
      );
    } on Object {
      _failed = true;
      rethrow;
    }
  }

  void _ensureUsable() {
    if (_failed) {
      throw const FramingException(
        'framer_unusable',
        'ACP NDJSON framer is unusable after a previous failure.',
      );
    }
  }
}
