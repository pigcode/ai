import 'dart:convert';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:test/test.dart';

import 'endpoint_support.dart';

void main() {
  test('POST lifecycle, headers, DELETE, and session lookup', () async {
    final endpoint = McpHttpEndpoint(
      path: '/mcp',
      allowedHosts: const <String>['mcp.test'],
      allowedOrigins: const <String>['https://host.test'],
      acceptedProtocolVersions: const <String>[
        '2025-11-25',
        '2025-03-26',
      ],
      createSessionId: () => 'session::one',
      serverFactory: (transport) => McpServer(
        transport: transport,
        capabilities: McpServerCapabilities(),
        handlers: McpHandlerSet(),
        serverInfo: const <String, Object?>{
          'name': 'endpoint-server',
          'version': '1.0.0',
        },
      ),
    );
    final initialize = await endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: const <String, String>{
          'accept': 'application/json, text/event-stream',
          'content-type': 'application/json',
          'origin': 'https://host.test',
        },
        json: _initializeRequest,
      ),
    );
    expect(initialize.statusCode, 200);
    expect(initialize.headers['content-type'], 'application/json');
    expect(initialize.headers['mcp-session-id'], 'session::one');
    final initializeJson =
        jsonDecode(await responseText(initialize))! as Map<String, Object?>;
    expect(
      (initializeJson['result']! as Map<String, Object?>)['protocolVersion'],
      '2025-11-25',
    );

    final initialized = await endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: initializedHeaders('session::one'),
        json: const <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        },
      ),
    );
    expect(initialized.statusCode, 202);

    final ping = await endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: initializedHeaders('session::one'),
        json: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'ping',
          'params': <String, Object?>{},
        },
      ),
    );
    expect(ping.statusCode, 200);
    expect(
      jsonDecode(await responseText(ping)),
      const <String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'result': <String, Object?>{},
      },
    );

    final missingVersion = await endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: <String, String>{
          ...initializedHeaders('session::one')..remove('mcp-protocol-version'),
        },
        json: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'ping',
        },
      ),
    );
    expect(missingVersion.statusCode, 400);

    final compatibleVersion = await endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: <String, String>{
          ...initializedHeaders('session::one'),
          'mcp-protocol-version': '2025-03-26',
        },
        json: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'ping',
        },
      ),
    );
    expect(compatibleVersion.statusCode, 200);

    final deleted = await endpoint.handle(
      endpointRequest(
        method: 'DELETE',
        headers: initializedHeaders('session::one'),
      ),
    );
    expect(deleted.statusCode, 204);
    expect(endpoint.sessionCount, 0);
    final gone = await endpoint.handle(
      endpointRequest(
        method: 'GET',
        headers: <String, String>{
          ...initializedHeaders('session::one'),
          'accept': 'text/event-stream',
        },
      ),
    );
    expect(gone.statusCode, 404);
    await endpoint.close();
  });

  test('rejects unsupported method, accept, content type, and path', () async {
    final endpoint = _emptyEndpoint();
    expect(
      (await endpoint.handle(endpointRequest(method: 'PATCH'))).statusCode,
      405,
    );
    expect(
      (await endpoint.handle(
        endpointRequest(
          method: 'POST',
          headers: const <String, String>{
            'accept': 'application/json',
            'content-type': 'application/json',
          },
          json: _initializeRequest,
        ),
      ))
          .statusCode,
      406,
    );
    expect(
      (await endpoint.handle(
        endpointRequest(
          method: 'POST',
          headers: const <String, String>{
            'accept': 'application/json, text/event-stream',
            'content-type': 'text/plain',
          },
          json: _initializeRequest,
        ),
      ))
          .statusCode,
      415,
    );
    expect(
      (await endpoint.handle(
        McpHttpEndpointRequest(
          method: 'GET',
          uri: Uri.parse('/wrong'),
          headers: const <String, String>{'host': 'mcp.test'},
          body: const Stream<List<int>>.empty(),
        ),
      ))
          .statusCode,
      404,
    );
    await endpoint.close();
  });

  test('failed initialize does not retain or expose a session', () async {
    final endpoint = _emptyEndpoint();
    final response = await endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: const <String, String>{
          'accept': 'application/json, text/event-stream',
          'content-type': 'application/json',
        },
        json: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': <String, Object?>{},
        },
      ),
    );

    expect(response.statusCode, 200);
    expect(response.headers, isNot(contains('mcp-session-id')));
    expect(
      jsonDecode(await responseText(response)),
      containsPair('error', isNotNull),
    );
    expect(endpoint.sessionCount, 0);
    await endpoint.close();
  });
}

McpHttpEndpoint _emptyEndpoint() => McpHttpEndpoint(
      path: '/mcp',
      allowedHosts: const <String>['mcp.test'],
      createSessionId: () => 'empty-session',
      serverFactory: (transport) => McpServer(
        transport: transport,
        capabilities: McpServerCapabilities(),
        handlers: McpHandlerSet(),
        serverInfo: const <String, Object?>{
          'name': 'empty',
          'version': '1.0.0',
        },
      ),
    );

const _initializeRequest = <String, Object?>{
  'jsonrpc': '2.0',
  'id': 1,
  'method': 'initialize',
  'params': <String, Object?>{
    'protocolVersion': '2025-11-25',
    'capabilities': <String, Object?>{},
    'clientInfo': <String, Object?>{
      'name': 'endpoint-client',
      'version': '1.0.0',
    },
  },
};
