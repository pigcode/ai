import 'dart:async';

import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

final class ScriptedPeerPair {
  ScriptedPeerPair._(this.left, this.right);

  factory ScriptedPeerPair.chaotic({
    List<int> chunkPattern = const <int>[1, 2, 5, 3, 8],
  }) {
    final leftBytes = _ScriptedByteTransport(chunkPattern);
    final rightBytes = _ScriptedByteTransport(chunkPattern.reversed.toList());
    leftBytes.remote = rightBytes;
    rightBytes.remote = leftBytes;
    ProtocolMessageTransport<JsonRpcMessage> wrap(
      _ScriptedByteTransport bytes,
    ) =>
        createAcpNdjsonTransport(
          byteTransport: bytes,
        );

    return ScriptedPeerPair._(wrap(leftBytes), wrap(rightBytes));
  }

  final ProtocolMessageTransport<JsonRpcMessage> left;
  final ProtocolMessageTransport<JsonRpcMessage> right;
}

final class _ScriptedByteTransport implements ProtocolByteTransport {
  _ScriptedByteTransport(this.chunkPattern);

  final List<int> chunkPattern;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast(sync: true);
  late _ScriptedByteTransport remote;
  var _nextChunk = 0;
  var _closed = false;

  @override
  Stream<List<int>> get incomingBytes => _incoming.stream;

  @override
  Future<void> sendBytes(List<int> bytes) async {
    if (_closed) {
      throw StateError('scripted byte transport closed');
    }
    var offset = 0;
    while (offset < bytes.length) {
      final requested = chunkPattern[_nextChunk++ % chunkPattern.length];
      final end = (offset + requested).clamp(0, bytes.length);
      remote._incoming.add(
        List<int>.unmodifiable(bytes.sublist(offset, end)),
      );
      offset = end;
    }
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
