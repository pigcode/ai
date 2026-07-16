import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWebSocketChannel(
  Uri url, {
  Iterable<String>? protocols,
  Map<String, String>? headers,
}) =>
    IOWebSocketChannel.connect(
      url,
      protocols: protocols,
      headers: headers,
    );

Iterable<String>? effectiveWebSocketProtocols(
  Iterable<String>? protocols, {
  Map<String, String>? headers,
}) {
  if (protocols == null || headers == null || headers.isEmpty) {
    return protocols;
  }
  final hasAuthorization = _hasHeaderValue(
    headers,
    'authorization',
    valueStartsWith: 'Bearer ',
  );
  final hasOrganization = _hasHeaderValue(headers, 'openai-organization');
  final hasProject = _hasHeaderValue(headers, 'openai-project');
  return [
    for (final protocol in protocols)
      if (!(hasAuthorization &&
              protocol.startsWith('openai-insecure-api-key.')) &&
          !(hasOrganization && protocol.startsWith('openai-organization.')) &&
          !(hasProject && protocol.startsWith('openai-project.')))
        protocol,
  ];
}

bool _hasHeaderValue(
  Map<String, String> headers,
  String name, {
  String? valueStartsWith,
}) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name &&
        (valueStartsWith == null || entry.value.startsWith(valueStartsWith))) {
      return true;
    }
  }
  return false;
}
