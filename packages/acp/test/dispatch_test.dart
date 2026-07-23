import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('dispatches agent methods and client reverse requests by descriptor',
      () async {
    final pair = MemoryTransportPair.create();
    final agent = AcpAgent(
      transport: pair.right,
      capabilities: AcpAgentCapabilities(),
      handlers: AcpHandlerSet(
        requests: <String, AcpRequestHandler>{
          'session/new': (invocation) {
            expect(
                invocation.descriptor.requestDefinition, 'NewSessionRequest');
            return <String, Object?>{'sessionId': 'session-1'};
          },
        },
      ),
    );
    final client = AcpClient(
      transport: pair.left,
      capabilities: AcpClientCapabilities(readTextFile: true),
      handlers: AcpHandlerSet(
        requests: <String, AcpRequestHandler>{
          'fs/read_text_file': (invocation) {
            expect(invocation.params, containsPair('path', 'README.md'));
            return <String, Object?>{'content': 'readme'};
          },
        },
      ),
    );
    await client.initialize();

    expect(
      await client.request(
        'session/new',
        <String, Object?>{'cwd': '', 'mcpServers': <Object?>[]},
      ),
      <String, Object?>{'sessionId': 'session-1'},
    );
    expect(
      await agent.requestClient(
        'fs/read_text_file',
        <String, Object?>{
          'sessionId': 'session-1',
          'path': 'README.md',
        },
      ),
      <String, Object?>{'content': 'readme'},
    );
    await expectLater(
      client.request('session/list', <String, Object?>{}),
      throwsA(
        isA<AcpCapabilityException>().having(
          (error) => error.code,
          'code',
          'acp_capability_not_negotiated',
        ),
      ),
    );
    await client.close();
    await agent.close();
  });
}
