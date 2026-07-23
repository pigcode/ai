import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('same-origin GET redirects can be followed without replaying POST',
      () async {
    final http = ScriptedHttpClient(<McpHttpResponder>[
      (_) => byteResponse(
            307,
            headers: const <String, String>{'location': '/other'},
          ),
      (request) {
        expect(request.uri, Uri.parse('https://mcp.example.test/other'));
        return byteResponse(405);
      },
    ]);
    final transport = McpHttpClientTransport(
      httpClient: http,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
    );

    expect(await transport.openServerStream(), isFalse);
    expect(http.requests, hasLength(2));
    await transport.close();
  });

  test('credential-bearing cross-origin redirect is rejected', () async {
    final http = ScriptedHttpClient(<McpHttpResponder>[
      (_) => byteResponse(
            307,
            headers: const <String, String>{
              'location': 'https://attacker.example/rpc',
            },
          ),
    ]);
    final transport = McpHttpClientTransport(
      httpClient: http,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
      authorizationProvider: const FixedAuthorizationProvider(
        <String, String>{'authorization': 'Bearer secret'},
      ),
    );

    await expectLater(
      transport.openServerStream(),
      throwsA(
        isA<ProtocolTransportException>().having(
          (error) => error.code,
          'code',
          'mcp_http_cross_origin_credentials',
        ),
      ),
    );
    expect(http.requests, hasLength(1));
    expect(
      http.requests.single.headers['authorization'],
      'Bearer secret',
    );
  });

  test('authorization provider cannot override transport headers', () async {
    final http = ScriptedHttpClient(<McpHttpResponder>[
      (_) => byteResponse(405),
    ]);
    final transport = McpHttpClientTransport(
      httpClient: http,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
      authorizationProvider: const FixedAuthorizationProvider(
        <String, String>{'Accept': '*/*'},
      ),
    );

    await expectLater(
      transport.openServerStream(),
      throwsA(
        isA<ProtocolTransportException>().having(
          (error) => error.code,
          'code',
          'mcp_http_invalid_authorization_headers',
        ),
      ),
    );
    expect(http.requests, isEmpty);
  });

  test('side-effecting redirect and unknown outcome are never replayed',
      () async {
    final redirecting = ScriptedHttpClient(<McpHttpResponder>[
      (_) => byteResponse(
            307,
            headers: const <String, String>{'location': '/other'},
          ),
    ]);
    final redirectedTransport = McpHttpClientTransport(
      httpClient: redirecting,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
    );
    await expectLater(
      redirectedTransport.sendMessage(
        JsonRpcNotification(
          method: 'notifications/initialized',
          params: const <String, Object?>{},
        ),
      ),
      throwsA(
        isA<ProtocolTransportException>().having(
          (error) => error.code,
          'code',
          'mcp_http_redirect_replay_refused',
        ),
      ),
    );
    expect(redirecting.requests, hasLength(1));

    var attempts = 0;
    final failing = ScriptedHttpClient(<McpHttpResponder>[
      (_) {
        attempts++;
        throw StateError('connection lost after write');
      },
    ]);
    final failingTransport = McpHttpClientTransport(
      httpClient: failing,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
    );
    await expectLater(
      failingTransport.sendMessage(
        JsonRpcRequest(
          id: JsonRpcIntegerId(1),
          method: 'tools/call',
          params: const <String, Object?>{'name': 'side-effect'},
        ),
      ),
      throwsA(
        isA<ProtocolTransportException>().having(
          (error) => error.code,
          'code',
          'mcp_http_unknown_outcome',
        ),
      ),
    );
    expect(attempts, 1);
  });
}
