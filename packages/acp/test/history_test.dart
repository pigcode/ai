import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('load marks replay historical while resume never claims active attach',
      () async {
    final pair = MemoryTransportPair.create();
    late AcpAgent agent;
    agent = AcpAgent(
      transport: pair.right,
      capabilities: AcpAgentCapabilities(
        loadSession: true,
        sessionResume: true,
      ),
      handlers: AcpHandlerSet(
        requests: <String, AcpRequestHandler>{
          'session/load': (_) async {
            await agent.updateSession(
              AcpSessionNotification.fromJson(
                <String, Object?>{
                  'sessionId': 'session-1',
                  'update': <String, Object?>{
                    'sessionUpdate': 'user_message_chunk',
                    'content': <String, Object?>{
                      'type': 'text',
                      'text': 'historical',
                    },
                  },
                },
              ),
            );
            return <String, Object?>{};
          },
          'session/resume': (_) => <String, Object?>{},
        },
      ),
    );
    final client = AcpClient(
      transport: pair.left,
      capabilities: AcpClientCapabilities(),
      handlers: AcpHandlerSet(),
    );
    await client.initialize();

    final loaded = await client.loadSession(
      AcpLoadSessionRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'cwd': '/workspace',
          'mcpServers': <Object?>[],
        },
      ),
    );
    final resumed = await client.resumeSession(
      AcpResumeSessionRequest.fromJson(
        <String, Object?>{'sessionId': 'session-1', 'cwd': '/workspace'},
      ),
    );

    expect(loaded.kind, AcpSessionRestoreKind.load);
    expect(loaded.historicalUpdates, hasLength(1));
    expect(
      loaded.historicalUpdates.single.provenance,
      AcpUpdateProvenance.historicalReplay,
    );
    expect(loaded.attachesToActivePrompt, isFalse);
    expect(resumed.kind, AcpSessionRestoreKind.resume);
    expect(resumed.historicalUpdates, isEmpty);
    expect(resumed.attachesToActivePrompt, isFalse);
    expect(client.hasActivePrompt('session-1'), isFalse);

    await client.close();
    await agent.close();
  });
}
