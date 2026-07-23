import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_io.dart';
import 'package:test/test.dart';

void main() {
  test('dart:io adapter serves a caller-owned loopback socket', () async {
    final socket = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final endpoint = McpHttpEndpoint(
      path: '/mcp',
      allowedHosts: <String>['127.0.0.1:${socket.port}'],
      createSessionId: () => 'io-session',
      serverFactory: (transport) => McpServer(
        transport: transport,
        capabilities: McpServerCapabilities(),
        handlers: McpHandlerSet(),
        serverInfo: const <String, Object?>{
          'name': 'io-server',
          'version': '1.0.0',
        },
      ),
    );
    final adapter = McpIoHttpServerAdapter(endpoint);
    final subscription = socket.listen(adapter.handle);
    final http = HttpClient();
    try {
      final request = await http.post(
        '127.0.0.1',
        socket.port,
        '/mcp',
      );
      request.headers
        ..set('accept', 'application/json, text/event-stream')
        ..set('content-type', 'application/json');
      request.write(
        jsonEncode(
          const <String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'initialize',
            'params': <String, Object?>{
              'protocolVersion': '2025-11-25',
              'capabilities': <String, Object?>{},
              'clientInfo': <String, Object?>{
                'name': 'io-client',
                'version': '1.0.0',
              },
            },
          },
        ),
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(response.headers.value('mcp-session-id'), 'io-session');
      final body = await utf8.decodeStream(response);
      expect(jsonDecode(body), containsPair('result', isNotNull));
    } finally {
      http.close(force: true);
      await endpoint.close();
      await subscription.cancel();
      await socket.close(force: true);
    }
  });

  test('portable barrels have no transitive dart:io import', () {
    final roots = <String>[
      'lib/pigcode_ai_mcp.dart',
      'lib/pigcode_ai_mcp_http.dart',
    ];
    final visited = <String>{};

    void scan(String path) {
      if (!visited.add(path)) {
        return;
      }
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains("import 'dart:io'")), reason: path);
      final directory = File(path).parent.path;
      for (final match
          in RegExp(r"(?:import|export) '([^']+)'").allMatches(source)) {
        final target = match.group(1)!;
        if (!target.startsWith('src/')) {
          continue;
        }
        scan('$directory/$target');
      }
    }

    for (final root in roots) {
      scan(root);
    }
  });
}
