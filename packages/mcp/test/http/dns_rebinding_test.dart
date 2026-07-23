import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:test/test.dart';

import 'endpoint_support.dart';

void main() {
  test('invalid Origin or Host is rejected with 403 before protocol work',
      () async {
    var factories = 0;
    final endpoint = McpHttpEndpoint(
      path: '/mcp',
      allowedHosts: const <String>['127.0.0.1:9000'],
      allowedOrigins: const <String>['https://trusted.test'],
      createSessionId: () => 'session',
      serverFactory: (transport) {
        factories++;
        return McpServer(
          transport: transport,
          capabilities: McpServerCapabilities(),
          handlers: McpHandlerSet(),
          serverInfo: const <String, Object?>{
            'name': 'secure',
            'version': '1.0.0',
          },
        );
      },
    );

    final badHost = await endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: const <String, String>{
          'host': 'attacker.test',
          'origin': 'https://trusted.test',
        },
      ),
    );
    expect(badHost.statusCode, 403);
    final badOrigin = await endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: const <String, String>{
          'host': '127.0.0.1:9000',
          'origin': 'https://attacker.test',
        },
      ),
    );
    expect(badOrigin.statusCode, 403);
    final absentOrigin = await endpoint.handle(
      endpointRequest(
        method: 'PATCH',
        headers: const <String, String>{'host': '127.0.0.1:9000'},
      ),
    );
    expect(absentOrigin.statusCode, 405);
    expect(factories, 0);
    await endpoint.close();
  });
}
