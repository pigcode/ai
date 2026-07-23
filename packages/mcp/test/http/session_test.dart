import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('session validates IDs and emits protocol/session headers', () {
    final session = McpHttpSession(
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
    );
    expect(session.protocolHeaders(), isEmpty);
    session.acceptInitializeResponse(
      const <String, String>{'mcp-session-id': 'opaque::session'},
    );
    expect(
      session.protocolHeaders(),
      <String, String>{
        'mcp-protocol-version': '2025-11-25',
        'mcp-session-id': 'opaque::session',
      },
    );

    expect(
      () => McpHttpSession(
        endpoint: Uri.parse('https://user:secret@mcp.example.test/rpc'),
      ),
      throwsArgumentError,
    );
    expect(
      () => McpHttpSession(
        endpoint: Uri.parse('https://mcp.example.test/rpc'),
      ).acceptInitializeResponse(
        const <String, String>{'mcp-session-id': 'bad session'},
      ),
      throwsFormatException,
    );
  });

  test('GET 405 is optional and DELETE accepts 200/202/204', () async {
    final http = ScriptedHttpClient(<McpHttpResponder>[
      (request) {
        expect(request.method, 'GET');
        expect(request.headers['accept'], 'text/event-stream');
        return byteResponse(405);
      },
      (request) {
        expect(request.method, 'DELETE');
        expect(request.headers['mcp-session-id'], 'session');
        return byteResponse(202);
      },
    ]);
    final transport = McpHttpClientTransport(
      httpClient: http,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
    );
    transport.session.acceptInitializeResponse(
      const <String, String>{'mcp-session-id': 'session'},
    );

    expect(await transport.openServerStream(), isFalse);
    expect(await transport.terminateSession(), isTrue);
    expect(transport.session.sessionId, isNull);
    await transport.close();
  });

  test('404 expires session without replay or automatic reinitialize',
      () async {
    final http = ScriptedHttpClient(<McpHttpResponder>[
      (_) => byteResponse(404),
    ]);
    final transport = McpHttpClientTransport(
      httpClient: http,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
    );
    transport.session.acceptInitializeResponse(
      const <String, String>{'mcp-session-id': 'expired'},
    );

    await expectLater(
      transport.sendMessage(
        JsonRpcRequest(
          id: JsonRpcIntegerId(7),
          method: 'tools/list',
          params: const <String, Object?>{},
        ),
      ),
      throwsA(
        isA<ProtocolTransportException>().having(
          (error) => error.code,
          'code',
          'mcp_http_session_expired',
        ),
      ),
    );
    expect(transport.session.isExpired, isTrue);
    expect(http.requests, hasLength(1));
  });
}
