import 'package:web_socket_channel/web_socket_channel.dart';

import 'web_socket_channel_connector_default.dart'
    if (dart.library.io) 'web_socket_channel_connector_io.dart' as impl;

WebSocketChannel connectWebSocketChannel(
  Uri url, {
  Iterable<String>? protocols,
  Map<String, String>? headers,
}) =>
    impl.connectWebSocketChannel(
      url,
      protocols: protocols,
      headers: headers,
    );

Iterable<String>? effectiveWebSocketProtocols(
  Iterable<String>? protocols, {
  Map<String, String>? headers,
}) =>
    impl.effectiveWebSocketProtocols(protocols, headers: headers);
