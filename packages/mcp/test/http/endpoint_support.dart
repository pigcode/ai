import 'dart:convert';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';

McpHttpEndpointRequest endpointRequest({
  required String method,
  Map<String, String> headers = const <String, String>{},
  Object? json,
}) =>
    McpHttpEndpointRequest(
      method: method,
      uri: Uri.parse('/mcp'),
      headers: <String, String>{
        'host': 'mcp.test',
        ...headers,
      },
      body: json == null
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(jsonEncode(json))),
      remoteAddress: '127.0.0.1',
    );

Map<String, String> initializedHeaders(String sessionId) => <String, String>{
      'host': 'mcp.test',
      'accept': 'application/json, text/event-stream',
      'content-type': 'application/json',
      'mcp-protocol-version': '2025-11-25',
      'mcp-session-id': sessionId,
    };

Future<String> responseText(McpHttpEndpointResponse response) async =>
    utf8.decode(
      await response.body.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      ),
    );
