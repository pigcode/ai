import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('typed agent covers every stable client reverse method', () async {
    final pair = MemoryTransportPair.create();
    final seen = <String>[];
    final responses = <String, Object?>{
      'session/request_permission': <String, Object?>{
        'outcome': <String, Object?>{'outcome': 'cancelled'},
      },
      'fs/read_text_file': <String, Object?>{'content': 'contents'},
      'fs/write_text_file': <String, Object?>{},
      'terminal/create': <String, Object?>{'terminalId': 'terminal-1'},
      'terminal/output': <String, Object?>{
        'output': 'output',
        'truncated': false,
      },
      'terminal/release': <String, Object?>{},
      'terminal/wait_for_exit': <String, Object?>{},
      'terminal/kill': <String, Object?>{},
    };
    final client = AcpClient(
      transport: pair.left,
      capabilities: AcpClientCapabilities(
        readTextFile: true,
        writeTextFile: true,
        terminal: true,
      ),
      handlers: AcpHandlerSet(
        requests: <String, AcpRequestHandler>{
          for (final entry in responses.entries)
            entry.key: (invocation) {
              seen.add(invocation.descriptor.method);
              return entry.value;
            },
        },
      ),
    );
    final agent = AcpAgent(
      transport: pair.right,
      capabilities: AcpAgentCapabilities(),
      handlers: AcpHandlerSet(),
    );
    await client.initialize();

    await agent.requestPermission(
      AcpRequestPermissionRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'toolCall': <String, Object?>{'toolCallId': 'tool-1'},
          'options': <Object?>[],
        },
      ),
    );
    await agent.readTextFile(
      AcpReadTextFileRequest.fromJson(
        <String, Object?>{'sessionId': 'session-1', 'path': 'README.md'},
      ),
    );
    await agent.writeTextFile(
      AcpWriteTextFileRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'path': 'README.md',
          'content': 'contents',
        },
      ),
    );
    await agent.createTerminal(
      AcpCreateTerminalRequest.fromJson(
        <String, Object?>{'sessionId': 'session-1', 'command': 'dart'},
      ),
    );
    await agent.terminalOutput(
      AcpTerminalOutputRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'terminalId': 'terminal-1',
        },
      ),
    );
    await agent.releaseTerminal(
      AcpReleaseTerminalRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'terminalId': 'terminal-1',
        },
      ),
    );
    await agent.waitForTerminalExit(
      AcpWaitForTerminalExitRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'terminalId': 'terminal-1',
        },
      ),
    );
    await agent.killTerminal(
      AcpKillTerminalRequest.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'terminalId': 'terminal-1',
        },
      ),
    );
    await agent.updateSession(
      AcpSessionNotification.fromJson(
        <String, Object?>{
          'sessionId': 'session-1',
          'update': <String, Object?>{
            'sessionUpdate': 'usage_update',
            'used': 1,
            'size': 2,
          },
        },
      ),
    );

    expect(seen, responses.keys);
    expect(client.history.forSession('session-1'), hasLength(1));
    await client.close();
    await agent.close();
  });

  test('reverse requests only invoke caller handlers and preserve denial',
      () async {
    final pair = MemoryTransportPair.create();
    final client = AcpClient(
      transport: pair.left,
      capabilities: AcpClientCapabilities(),
      handlers: AcpHandlerSet(
        requests: <String, AcpRequestHandler>{
          'session/request_permission': (_) {
            throw const JsonRpcHandlerException(
              code: -32003,
              message: 'Denied by caller policy',
            );
          },
        },
      ),
    );
    final agent = AcpAgent(
      transport: pair.right,
      capabilities: AcpAgentCapabilities(),
      handlers: AcpHandlerSet(),
    );
    await client.initialize();

    await expectLater(
      agent.requestPermission(
        AcpRequestPermissionRequest.fromJson(
          <String, Object?>{
            'sessionId': 'session-1',
            'toolCall': <String, Object?>{'toolCallId': 'tool-1'},
            'options': <Object?>[],
          },
        ),
      ),
      throwsA(
        isA<JsonRpcRemoteException>().having(
          (error) => error.remoteCode,
          'remoteCode',
          -32003,
        ),
      ),
    );
    await client.close();
    await agent.close();
  });
}
