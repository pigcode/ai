import 'dart:async';

import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support/scripted_peer.dart';

void main() {
  test('scripted byte peer covers lifecycle, reverse calls, and chaos chunks',
      () async {
    final pair = ScriptedPeerPair.chaotic();
    late AcpAgent agent;
    final sessionCancel = Completer<void>();
    agent = AcpAgent(
      transport: pair.right,
      capabilities: AcpAgentCapabilities(
        loadSession: true,
        sessionResume: true,
      ),
      handlers: AcpHandlerSet(
        requests: <String, AcpRequestHandler>{
          'session/new': (_) => <String, Object?>{'sessionId': 'session-chaos'},
          'session/load': (_) async {
            await agent.updateSession(
              AcpSessionNotification.fromJson(
                <String, Object?>{
                  'sessionId': 'session-chaos',
                  'update': <String, Object?>{
                    'sessionUpdate': 'user_message_chunk',
                    'content': <String, Object?>{
                      'type': 'text',
                      'text': '历史 🐷',
                    },
                  },
                },
              ),
            );
            return <String, Object?>{};
          },
          'session/resume': (_) => <String, Object?>{},
          'session/prompt': (_) async {
            final read = await agent.readTextFile(
              AcpReadTextFileRequest.fromJson(
                <String, Object?>{
                  'sessionId': 'session-chaos',
                  'path': 'README.md',
                },
              ),
            );
            await agent.updateSession(
              AcpSessionNotification.fromJson(
                <String, Object?>{
                  'sessionId': 'session-chaos',
                  'update': <String, Object?>{
                    'sessionUpdate': 'agent_message_chunk',
                    'content': <String, Object?>{
                      'type': 'text',
                      'text':
                          (read.toJson()! as JsonObject)['content']! as String,
                    },
                  },
                },
              ),
            );
            return <String, Object?>{'stopReason': 'end_turn'};
          },
        },
        notifications: <String, AcpNotificationHandler>{
          'session/cancel': (_) {
            if (!sessionCancel.isCompleted) {
              sessionCancel.complete();
            }
          },
        },
      ),
    );
    final client = AcpClient(
      transport: pair.left,
      capabilities: AcpClientCapabilities(readTextFile: true),
      handlers: AcpHandlerSet(
        requests: <String, AcpRequestHandler>{
          'fs/read_text_file': (_) => <String, Object?>{'content': 'chaos ✅'},
        },
      ),
    );

    await client.initialize();
    final created = await client.createSession(
      AcpNewSessionRequest.fromJson(
        <String, Object?>{'cwd': '/workspace', 'mcpServers': <Object?>[]},
      ),
    );
    expect(
      (created.toJson()! as JsonObject)['sessionId'],
      'session-chaos',
    );
    final loaded = await client.loadSession(
      AcpLoadSessionRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-chaos',
          'cwd': '/workspace',
          'mcpServers': <Object?>[],
        },
      ),
    );
    expect(loaded.historicalUpdates.single.kind, 'user_message_chunk');
    expect(
      (await client.resumeSession(
        AcpResumeSessionRequest.fromJson(
          <String, Object?>{
            'sessionId': 'session-chaos',
            'cwd': '/workspace',
          },
        ),
      ))
          .historicalUpdates,
      isEmpty,
    );
    final prompt = await client.prompt(
      AcpPromptRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-chaos',
          'prompt': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'hello'},
          ],
        },
      ),
    );
    expect(prompt.stopReason, 'end_turn');
    expect(prompt.updates.single.kind, 'agent_message_chunk');

    await client.cancelSession('session-chaos');
    await sessionCancel.future;

    final requestCancellation = ProtocolCancellationSource();
    final pending = client.request(
      'session/prompt',
      <String, Object?>{
        'sessionId': 'session-chaos',
        'prompt': <Object?>[],
      },
      cancellation: requestCancellation.signal,
    );
    requestCancellation.cancel('scripted request cancellation');
    await expectLater(
      pending,
      throwsA(isA<ProtocolCancellationException>()),
    );

    await client.close();
    await agent.close();
  });
}
