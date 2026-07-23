import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('dispatches server methods and reverse client methods by role',
      () async {
    final pair = MemoryTransportPair.create();
    final server = McpServer(
      transport: pair.right,
      capabilities: McpServerCapabilities(tools: true),
      handlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'tools/list': (invocation) {
            expect(invocation.binding.role, McpMessageRole.clientRequest);
            return <String, Object?>{'tools': <Object?>[]};
          },
          'tools/call': (_) => <String, Object?>{'content': <Object?>[]},
        },
      ),
      serverInfo: const <String, Object?>{
        'name': 'server',
        'version': '1.0.0',
      },
    );
    final client = McpClient(
      transport: pair.left,
      capabilities: McpClientCapabilities(roots: true),
      handlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'roots/list': (_) => <String, Object?>{
                'roots': <Object?>[
                  <String, Object?>{
                    'uri': 'file:///workspace',
                    'name': 'workspace',
                  },
                ],
              },
        },
      ),
      clientInfo: const <String, Object?>{
        'name': 'client',
        'version': '1.0.0',
      },
    );
    await client.initialize();

    expect(
      await client.requestServer('tools/list', const <String, Object?>{}),
      <String, Object?>{'tools': <Object?>[]},
    );
    expect(
      await server.requestClient('roots/list', const <String, Object?>{}),
      containsPair('roots', isNotEmpty),
    );
    await expectLater(
      client.requestServer('prompts/list', const <String, Object?>{}),
      throwsA(isA<McpCapabilityException>()),
    );
    await client.close();
    await server.close();
  });
}
