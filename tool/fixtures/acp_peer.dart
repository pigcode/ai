import 'dart:async';
import 'dart:io';

import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('The fixed ACP peer accepts no arguments.');
    exitCode = 64;
    return;
  }
  late AcpAgent agent;
  var nextSession = 1;
  agent = AcpAgent.fromByteTransport(
    byteTransport: _StdioByteTransport(),
    capabilities: AcpAgentCapabilities(
      loadSession: true,
      sessionResume: true,
    ),
    agentInfo: const <String, Object?>{
      'name': 'pigcode-fixed-dart-peer',
      'version': '1.0.0',
    },
    handlers: AcpHandlerSet(
      requests: <String, AcpRequestHandler>{
        'session/new': (_) => <String, Object?>{
              'sessionId': 'dart-session-${nextSession++}',
            },
        'session/load': (invocation) async {
          final params = invocation.params! as JsonObject;
          await agent.updateSession(
            AcpSessionNotification.fromJson(
              <String, Object?>{
                'sessionId': params['sessionId'],
                'update': <String, Object?>{
                  'sessionUpdate': 'user_message_chunk',
                  'content': <String, Object?>{
                    'type': 'text',
                    'text': 'historical dart peer',
                  },
                },
              },
            ),
          );
          return <String, Object?>{};
        },
        'session/resume': (_) => <String, Object?>{},
        'session/prompt': (invocation) async {
          final params = invocation.params! as JsonObject;
          final sessionId = params['sessionId']! as String;
          final read = await agent.readTextFile(
            AcpReadTextFileRequest.fromJson(
              <String, Object?>{
                'sessionId': sessionId,
                'path': 'README.md',
              },
            ),
          );
          await agent.updateSession(
            AcpSessionNotification.fromJson(
              <String, Object?>{
                'sessionId': sessionId,
                'update': <String, Object?>{
                  'sessionUpdate': 'agent_message_chunk',
                  'content': <String, Object?>{
                    'type': 'text',
                    'text': 'dart peer: '
                        '${(read.toJson()! as JsonObject)['content']}',
                  },
                },
              },
            ),
          );
          return <String, Object?>{'stopReason': 'end_turn'};
        },
      },
    ),
  );

  try {
    await agent.connection.peer.done;
  } on Object catch (error, stackTrace) {
    stderr
      ..writeln('Fixed ACP peer failed: ${error.runtimeType}')
      ..writeln(stackTrace);
    exitCode = 1;
  }
}

final class _StdioByteTransport implements ProtocolByteTransport {
  @override
  Stream<List<int>> get incomingBytes => stdin;

  @override
  Future<void> sendBytes(List<int> bytes) async {
    stdout.add(bytes);
    await stdout.flush();
  }

  @override
  Future<void> close() async {
    await stdout.flush();
  }
}
