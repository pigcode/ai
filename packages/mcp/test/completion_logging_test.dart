import 'dart:async';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

import 'support/initialized_pair.dart';

void main() {
  test('completion and logging use typed stable-protocol surfaces', () async {
    final log = Completer<Map<String, Object?>>();
    final pair = await createInitializedMcpPair(
      serverCapabilities:
          McpServerCapabilities(completions: true, logging: true),
      serverHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'completion/complete': (_) => <String, Object?>{
                'completion': <String, Object?>{
                  'values': <Object?>['README.md'],
                  'total': 1,
                  'hasMore': false,
                },
              },
          'logging/setLevel': (_) => const <String, Object?>{},
        },
      ),
      clientHandlers: McpHandlerSet(
        notifications: <String, McpNotificationHandler>{
          'notifications/message': (invocation) {
            if (!log.isCompleted) {
              log.complete(invocation.params! as Map<String, Object?>);
            }
          },
        },
      ),
    );

    final completion = await pair.client.complete(
      McpCompleteRequestParams.fromJson(
        const <String, Object?>{
          'ref': <String, Object?>{
            'type': 'ref/resource',
            'uri': 'file:///{path}',
          },
          'argument': <String, Object?>{
            'name': 'path',
            'value': 'READ',
          },
        },
      ),
    );
    expect(
      ((completion.toJson()! as Map<String, Object?>)['completion']!
          as Map<String, Object?>)['values'],
      <Object?>['README.md'],
    );
    await pair.client.setLoggingLevel(
      McpSetLevelRequestParams.fromJson(
        const <String, Object?>{'level': 'info'},
      ),
    );
    await pair.server.logMessage(
      McpLoggingMessageNotificationParams.fromJson(
        const <String, Object?>{
          'level': 'info',
          'logger': 'mcp.test',
          'data': <String, Object?>{'message': 'ready'},
        },
      ),
    );
    expect((await log.future)['logger'], 'mcp.test');
    await pair.close();
  });
}
