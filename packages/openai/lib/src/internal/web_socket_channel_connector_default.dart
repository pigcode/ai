import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocketChannel(
  Uri url, {
  Iterable<String>? protocols,
  Map<String, String>? headers,
}) {
  _throwIfUnsupportedHeaders(headers);
  return WebSocketChannel.connect(url, protocols: protocols);
}

void _throwIfUnsupportedHeaders(Map<String, String>? headers) {
  if (headers == null || headers.isEmpty) {
    return;
  }

  final unsupported = [
    for (final name in headers.keys)
      if (!_browserWebSocketCanRepresentHeader(name)) name,
  ];
  if (unsupported.isEmpty) {
    return;
  }

  throw UnsupportedError(
    'OpenAI realtime WebSocket headers are not supported on this platform: '
    '${unsupported.join(', ')}. Provide a custom OpenAiWebSocketConnector or '
    'run on a dart:io target to send these headers.',
  );
}

bool _browserWebSocketCanRepresentHeader(String name) {
  final normalized = name.toLowerCase();
  return normalized == 'authorization' ||
      normalized == 'openai-organization' ||
      normalized == 'openai-project' ||
      normalized == 'user-agent';
}

Iterable<String>? effectiveWebSocketProtocols(
  Iterable<String>? protocols, {
  Map<String, String>? headers,
}) =>
    protocols;
