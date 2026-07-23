import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('negotiates protocol version 1 exactly once', () async {
    final pair = MemoryTransportPair.create();
    final agent = AcpAgent(
      transport: pair.right,
      capabilities: AcpAgentCapabilities(),
      handlers: AcpHandlerSet(),
    );
    final client = AcpClient(
      transport: pair.left,
      capabilities: AcpClientCapabilities(),
      handlers: AcpHandlerSet(),
    );

    final snapshot = await client.initialize();

    expect(snapshot.protocolVersion, 1);
    expect(client.state, AcpConnectionState.initialized);
    expect(agent.state, AcpConnectionState.initialized);
    await expectLater(
      client.initialize(),
      throwsA(
        isA<AcpStateException>().having(
          (error) => error.code,
          'code',
          'acp_duplicate_initialize',
        ),
      ),
    );
    await client.close();
    await agent.close();
  });

  test('rejects operations before initialization', () async {
    final transport = ManualMessageTransport();
    final client = AcpClient(
      transport: transport,
      capabilities: AcpClientCapabilities(),
      handlers: AcpHandlerSet(),
    );

    await expectLater(
      client.request(
        'session/new',
        <String, Object?>{'cwd': '', 'mcpServers': <Object?>[]},
      ),
      throwsA(
        isA<AcpStateException>().having(
          (error) => error.code,
          'code',
          'acp_not_initialized',
        ),
      ),
    );
    await client.close();
  });

  test('closes on a mismatched initialize response version', () async {
    final transport = ManualMessageTransport();
    final client = AcpClient(
      transport: transport,
      capabilities: AcpClientCapabilities(),
      handlers: AcpHandlerSet(),
    );

    final result = client.initialize();
    final request = await transport.takeSent() as JsonRpcRequest;
    transport.inject(
      JsonRpcSuccessResponse(
        id: request.id,
        result: <String, Object?>{
          'protocolVersion': 2,
          'agentCapabilities': <String, Object?>{},
          'authMethods': <Object?>[],
        },
      ),
    );

    await expectLater(
      result,
      throwsA(
        isA<AcpVersionException>().having(
          (error) => error.code,
          'code',
          'acp_protocol_version_mismatch',
        ),
      ),
    );
    expect(client.state, AcpConnectionState.closed);
  });
}
