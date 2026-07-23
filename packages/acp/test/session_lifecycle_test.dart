import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('typed client covers every stable agent lifecycle request', () async {
    final pair = MemoryTransportPair.create();
    final seen = <String>[];
    final responses = <String, Object?>{
      'authenticate': <String, Object?>{},
      'session/new': <String, Object?>{'sessionId': 'session-1'},
      'session/load': <String, Object?>{},
      'session/set_mode': <String, Object?>{},
      'session/set_config_option': <String, Object?>{
        'configOptions': <Object?>[],
      },
      'session/prompt': <String, Object?>{'stopReason': 'end_turn'},
      'session/list': <String, Object?>{'sessions': <Object?>[]},
      'session/delete': <String, Object?>{},
      'session/resume': <String, Object?>{},
      'session/close': <String, Object?>{},
      'logout': <String, Object?>{},
    };
    final agent = AcpAgent(
      transport: pair.right,
      capabilities: AcpAgentCapabilities(
        loadSession: true,
        sessionList: true,
        sessionDelete: true,
        sessionResume: true,
        sessionClose: true,
        logout: true,
      ),
      handlers: AcpHandlerSet(
        requests: <String, AcpRequestHandler>{
          for (final entry in responses.entries)
            entry.key: (invocation) {
              seen.add(invocation.descriptor.method);
              return entry.value;
            },
        },
        notifications: <String, AcpNotificationHandler>{
          'session/cancel': (invocation) {
            seen.add(invocation.descriptor.method);
          },
        },
      ),
    );
    final client = AcpClient(
      transport: pair.left,
      capabilities: AcpClientCapabilities(booleanConfigOptions: true),
      handlers: AcpHandlerSet(),
    );
    await client.initialize();

    await client.authenticate(
      AcpAuthenticateRequest.fromJson(<String, Object?>{'methodId': 'auth'}),
    );
    await client.createSession(
      AcpNewSessionRequest.fromJson(
        <String, Object?>{'cwd': '/workspace', 'mcpServers': <Object?>[]},
      ),
    );
    await client.loadSession(
      AcpLoadSessionRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'cwd': '/workspace',
          'mcpServers': <Object?>[],
        },
      ),
    );
    await client.setSessionMode(
      AcpSetSessionModeRequest.fromJson(
        <String, Object?>{'sessionId': 'session-1', 'modeId': 'code'},
      ),
    );
    await client.setSessionConfigOption(
      AcpSetSessionConfigOptionRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'configId': 'safe',
          'type': 'boolean',
          'value': true,
        },
      ),
    );
    await client.prompt(
      AcpPromptRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'prompt': <Object?>[],
        },
      ),
    );
    await client.cancelSession('session-1');
    await client.listSessions(
      AcpListSessionsRequest.fromJson(<String, Object?>{}),
    );
    await client.deleteSession(
      AcpDeleteSessionRequest.fromJson(
        <String, Object?>{'sessionId': 'session-1'},
      ),
    );
    await client.resumeSession(
      AcpResumeSessionRequest.fromJson(
        <String, Object?>{'sessionId': 'session-1', 'cwd': '/workspace'},
      ),
    );
    await client.closeSession(
      AcpCloseSessionRequest.fromJson(
        <String, Object?>{'sessionId': 'session-1'},
      ),
    );
    await client.logout(AcpLogoutRequest.fromJson(<String, Object?>{}));

    expect(
      seen,
      <String>[
        'authenticate',
        'session/new',
        'session/load',
        'session/set_mode',
        'session/set_config_option',
        'session/prompt',
        'session/cancel',
        'session/list',
        'session/delete',
        'session/resume',
        'session/close',
        'logout',
      ],
    );
    await client.close();
    await agent.close();
  });
}
