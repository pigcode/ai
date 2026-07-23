import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('orders content, tool, plan, and usage before the terminal response',
      () async {
    final pair = MemoryTransportPair.create();
    late AcpAgent agent;
    agent = AcpAgent(
      transport: pair.right,
      capabilities: AcpAgentCapabilities(),
      handlers: AcpHandlerSet(
        requests: <String, AcpRequestHandler>{
          'session/prompt': (invocation) async {
            for (final update in <Map<String, Object?>>[
              <String, Object?>{
                'sessionUpdate': 'agent_message_chunk',
                'content': <String, Object?>{'type': 'text', 'text': 'hello'},
              },
              <String, Object?>{
                'sessionUpdate': 'tool_call',
                'toolCallId': 'tool-1',
                'title': 'Read file',
              },
              <String, Object?>{
                'sessionUpdate': 'plan',
                'entries': <Object?>[],
              },
              <String, Object?>{
                'sessionUpdate': 'usage_update',
                'used': 10,
                'size': 100,
              },
            ]) {
              await agent.updateSession(
                AcpSessionNotification.fromJson(
                  <String, Object?>{
                    'sessionId': 'session-1',
                    'update': update,
                  },
                ),
              );
            }
            return <String, Object?>{'stopReason': 'end_turn'};
          },
        },
      ),
    );
    final client = AcpClient(
      transport: pair.left,
      capabilities: AcpClientCapabilities(),
      handlers: AcpHandlerSet(),
    );
    await client.initialize();

    final result = await client.prompt(
      AcpPromptRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'prompt': <Object?>[],
        },
      ),
    );

    expect(result.stopReason, 'end_turn');
    expect(
      result.updates.map((event) => event.kind),
      <String>[
        'agent_message_chunk',
        'tool_call',
        'plan',
        'usage_update',
      ],
    );
    expect(result.updates.map((event) => event.sequence), <int>[0, 1, 2, 3]);
    expect(result.updates.every((event) => !event.isLate), isTrue);

    final lateUpdate = client.updates.firstWhere((event) => event.isLate);
    await agent.updateSession(
      AcpSessionNotification.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'update': <String, Object?>{
            'sessionUpdate': 'agent_message_chunk',
            'content': <String, Object?>{'type': 'text', 'text': 'late'},
          },
        },
      ),
    );
    expect((await lateUpdate).sequence, 4);

    await client.close();
    await agent.close();
  });
}
