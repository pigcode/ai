import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

void main() {
  test('portable stdio transport frames fragmented inbound and outbound JSON',
      () async {
    final bytes = _ScriptedByteTransport();
    final transport = createMcpStdioTransport(byteTransport: bytes);
    final received = transport.incomingMessages.first;
    final encoded = utf8.encode(
      '{"jsonrpc":"2.0","method":"notifications/progress",'
      '"params":{"progressToken":"opaque","progress":1}}\n',
    );

    bytes.add(encoded.sublist(0, 7));
    bytes.add(encoded.sublist(7, 31));
    bytes.add(encoded.sublist(31));
    final notification = await received as JsonRpcNotification;
    expect(notification.method, 'notifications/progress');

    await transport.sendMessage(
      JsonRpcNotification(
        method: 'notifications/initialized',
        params: <String, Object?>{},
      ),
    );
    expect(bytes.sent, hasLength(1));
    expect(bytes.sent.single.last, 0x0a);
    expect(
      const JsonRpcCodec().decode(utf8.decode(bytes.sent.single).trim()),
      isA<JsonRpcNotification>(),
    );
    await transport.close();
  });

  test('portable stdio transport rejects malformed and truncated input',
      () async {
    final malformedBytes = _ScriptedByteTransport();
    final malformed = createMcpStdioTransport(byteTransport: malformedBytes);
    final malformedError = expectLater(
      malformed.incomingMessages.first,
      throwsA(isA<JsonRpcException>()),
    );
    malformedBytes.add(utf8.encode('not-json\n'));
    await malformedError;

    final truncatedBytes = _ScriptedByteTransport();
    final truncated = createMcpStdioTransport(byteTransport: truncatedBytes);
    final truncatedError = expectLater(
      truncated.incomingMessages.first,
      throwsA(
        isA<FramingException>().having(
          (error) => error.code,
          'code',
          'ndjson_truncated_frame',
        ),
      ),
    );
    truncatedBytes.add(utf8.encode('{"jsonrpc":"2.0"'));
    await truncatedBytes.endInput();
    await truncatedError;
  });
}

final class _ScriptedByteTransport implements ProtocolByteTransport {
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>(sync: true);
  final List<List<int>> sent = <List<int>>[];
  var _closed = false;

  @override
  Stream<List<int>> get incomingBytes => _incoming.stream;

  void add(List<int> bytes) => _incoming.add(bytes);

  Future<void> endInput() => _incoming.close();

  @override
  Future<void> sendBytes(List<int> bytes) async {
    sent.add(List<int>.unmodifiable(bytes));
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}
