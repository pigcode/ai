import 'dart:convert';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('POST JSON/SSE supports headers and server request correlation',
      () async {
    final http = ScriptedHttpClient(<McpHttpResponder>[
      (request) {
        final message = requestJson(request);
        expect(message['method'], 'initialize');
        expect(request.headers['accept'], contains('application/json'));
        expect(request.headers['accept'], contains('text/event-stream'));
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers, isNot(contains('mcp-protocol-version')));
        expect(request.headers, isNot(contains('mcp-session-id')));
        return jsonResponse(
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': <String, Object?>{
              'protocolVersion': '2025-11-25',
              'capabilities': <String, Object?>{
                'tools': <String, Object?>{},
              },
              'serverInfo': <String, Object?>{
                'name': 'http-server',
                'version': '1.0.0',
              },
            },
          },
          headers: const <String, String>{
            'MCP-Session-Id': 'session::opaque',
          },
        );
      },
      (request) {
        expect(requestJson(request)['method'], 'notifications/initialized');
        _expectSessionHeaders(request);
        return byteResponse(202);
      },
      (request) {
        final message = requestJson(request);
        expect(message['method'], 'tools/list');
        _expectSessionHeaders(request);
        return sseResponse(
          'id: stream:1\n'
          'data: {"jsonrpc":"2.0","id":"server:1",'
          '"method":"roots/list","params":{}}\n'
          '\n'
          'id: stream:2\n'
          'data: {"jsonrpc":"2.0","id":${message['id']},'
          '"result":{"tools":[]}}\n'
          '\n',
        );
      },
      (request) {
        final message = requestJson(request);
        expect(message['id'], 'server:1');
        expect(message['result'], containsPair('roots', isNotEmpty));
        _expectSessionHeaders(request);
        return byteResponse(202);
      },
      (request) {
        expect(requestJson(request)['method'], 'notifications/progress');
        _expectSessionHeaders(request);
        return byteResponse(204);
      },
      (request) {
        expect(request.method, 'DELETE');
        _expectSessionHeaders(request);
        return byteResponse(204);
      },
    ]);
    final transport = McpHttpClientTransport(
      httpClient: http,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
    );
    final client = McpClient(
      transport: transport,
      capabilities: McpClientCapabilities(roots: true),
      handlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'roots/list': (_) => const <String, Object?>{
                'roots': <Object?>[
                  <String, Object?>{'uri': 'file:///workspace'},
                ],
              },
        },
      ),
      clientInfo: const <String, Object?>{
        'name': 'http-client',
        'version': '1.0.0',
      },
    );

    await client.initialize();
    final tools = await client.listTools(mcpPageRequest());
    expect(tools.toJson(), const <String, Object?>{'tools': <Object?>[]});
    await client.notifyServer(
      'notifications/progress',
      const <String, Object?>{'progressToken': 'p', 'progress': 1},
    );
    await client.close();
    expect(http.requests, hasLength(6));
  });

  test('rejects unsupported POST content type', () async {
    final http = ScriptedHttpClient(<McpHttpResponder>[
      (_) => byteResponse(
            200,
            headers: const <String, String>{'content-type': 'text/plain'},
            body: utf8.encode('{}'),
          ),
    ]);
    final transport = McpHttpClientTransport(
      httpClient: http,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
    );

    await expectLater(
      transport.sendMessage(
        JsonRpcRequest(
          id: JsonRpcIntegerId(1),
          method: 'initialize',
          params: const <String, Object?>{},
        ),
      ),
      throwsA(
        isA<ProtocolTransportException>().having(
          (error) => error.code,
          'code',
          'mcp_http_unsupported_content_type',
        ),
      ),
    );
  });

  test('tolerates bounded 2xx JSON acknowledgement for a notification',
      () async {
    final http = ScriptedHttpClient(<McpHttpResponder>[
      (_) => jsonResponse(
            const <String, Object?>{
              'jsonrpc': '2.0',
              'result': <String, Object?>{},
            },
          ),
    ]);
    final transport = McpHttpClientTransport(
      httpClient: http,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
    );

    await transport.sendMessage(
      JsonRpcNotification(
        method: 'notifications/initialized',
        params: const <String, Object?>{},
      ),
    );
  });
}

void _expectSessionHeaders(McpHttpRequest request) {
  expect(request.headers['mcp-protocol-version'], '2025-11-25');
  expect(request.headers['mcp-session-id'], 'session::opaque');
}
