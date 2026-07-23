import 'dart:async';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

import 'support/initialized_pair.dart';

void main() {
  test('elicitation number defaults accept fractional JSON numbers', () {
    final params = McpElicitRequestParams.fromJson(
      const <String, Object?>{
        'message': 'score',
        'requestedSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'score': <String, Object?>{
              'type': 'number',
              'default': 95.5,
            },
          },
        },
      },
    );

    expect(
      ((params.toJson()! as Map<String, Object?>)['requestedSchema']!
          as Map<String, Object?>)['properties'],
      containsPair(
        'score',
        containsPair('default', 95.5),
      ),
    );

    final result = McpElicitResult.fromJson(
      const <String, Object?>{
        'action': 'accept',
        'content': <String, Object?>{'score': 95.5},
      },
    );
    expect(
      (result.toJson()! as Map<String, Object?>)['content'],
      containsPair('score', 95.5),
    );
  });

  test('sampling, roots, elicitation, and progress preserve host policy',
      () async {
    final clientProgress = Completer<Object?>();
    final serverProgress = Completer<Object?>();
    final rootsChanged = Completer<void>();
    final elicitationComplete = Completer<String>();
    var authorizationChecks = 0;
    final pair = await createInitializedMcpPair(
      clientCapabilities: McpClientCapabilities(
        roots: true,
        rootsListChanged: true,
        sampling: true,
        samplingTools: true,
        elicitationForm: true,
        elicitationUrl: true,
      ),
      clientHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'sampling/createMessage': (_) {
            authorizationChecks++;
            return <String, Object?>{
              'role': 'assistant',
              'model': 'policy-approved-model',
              'stopReason': 'provider-specific-finish',
              'content': <String, Object?>{
                'type': 'text',
                'text': 'approved by host policy',
              },
            };
          },
          'roots/list': (_) {
            authorizationChecks++;
            return <String, Object?>{
              'roots': <Object?>[
                <String, Object?>{
                  'uri': 'file:///workspace',
                  'name': 'authorized-root',
                },
              ],
            };
          },
          'elicitation/create': (_) {
            authorizationChecks++;
            return const <String, Object?>{'action': 'decline'};
          },
        },
        notifications: <String, McpNotificationHandler>{
          'notifications/progress': (invocation) {
            final params = invocation.params! as Map<String, Object?>;
            if (!clientProgress.isCompleted) {
              clientProgress.complete(params['progressToken']);
            }
          },
          'notifications/elicitation/complete': (invocation) {
            final params = invocation.params! as Map<String, Object?>;
            if (!elicitationComplete.isCompleted) {
              elicitationComplete.complete(params['elicitationId']! as String);
            }
          },
        },
      ),
      serverHandlers: McpHandlerSet(
        notifications: <String, McpNotificationHandler>{
          'notifications/progress': (invocation) {
            final params = invocation.params! as Map<String, Object?>;
            if (!serverProgress.isCompleted) {
              serverProgress.complete(params['progressToken']);
            }
          },
          'notifications/roots/list_changed': (_) {
            if (!rootsChanged.isCompleted) rootsChanged.complete();
          },
        },
      ),
    );

    final sampled = await pair.server.createMessage(
      McpCreateMessageRequestParams.fromJson(
        const <String, Object?>{
          'messages': <Object?>[
            <String, Object?>{
              'role': 'user',
              'content': <String, Object?>{
                'type': 'text',
                'text': 'hello',
              },
            },
          ],
          'maxTokens': 64,
          'tools': <Object?>[
            <String, Object?>{
              'name': 'hinted',
              'annotations': <String, Object?>{'readOnlyHint': true},
              'inputSchema': <String, Object?>{'type': 'object'},
            },
          ],
        },
      ),
    );
    expect(
      (sampled.toJson()! as Map<String, Object?>)['stopReason'],
      'provider-specific-finish',
    );
    final roots = await pair.server.listRoots();
    expect((roots.toJson()! as Map<String, Object?>)['roots'], hasLength(1));
    final elicited = await pair.server.elicit(
      McpElicitRequestParams.fromJson(
        const <String, Object?>{
          'mode': 'form',
          'message': 'Continue?',
          'requestedSchema': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'confirmed': <String, Object?>{'type': 'boolean'},
            },
          },
        },
      ),
    );
    expect(
      (elicited.toJson()! as Map<String, Object?>)['action'],
      'decline',
    );
    expect(authorizationChecks, 3);

    await pair.server.notifyProgress(
      McpProgressNotificationParams.fromJson(
        const <String, Object?>{
          'progressToken': 'server-token',
          'progress': 1,
          'total': 2,
        },
      ),
    );
    await pair.client.notifyProgress(
      McpProgressNotificationParams.fromJson(
        const <String, Object?>{
          'progressToken': 42,
          'progress': 2,
        },
      ),
    );
    await pair.client.notifyRootsListChanged();
    await pair.server.notifyElicitationComplete('elicitation::opaque');

    expect(await clientProgress.future, 'server-token');
    expect(await serverProgress.future, 42);
    await rootsChanged.future;
    expect(await elicitationComplete.future, 'elicitation::opaque');
    await pair.close();
  });

  test('negotiated capabilities do not bypass explicit tool authorization',
      () async {
    final pair = await createInitializedMcpPair(
      serverCapabilities: McpServerCapabilities(tools: true),
      serverHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'tools/list': (_) => const <String, Object?>{
                'tools': <Object?>[
                  <String, Object?>{
                    'name': 'hinted',
                    'annotations': <String, Object?>{'readOnlyHint': true},
                    'inputSchema': <String, Object?>{'type': 'object'},
                  },
                ],
              },
          'tools/call': (_) => const <String, Object?>{
                'content': <Object?>[
                  <String, Object?>{
                    'type': 'text',
                    'text': 'host authorization denied',
                  },
                ],
                'isError': true,
              },
        },
      ),
    );

    final result = await pair.client.callTool(
      McpCallToolRequestParams.fromJson(
        const <String, Object?>{'name': 'hinted'},
      ),
    );
    expect((result.toJson()! as Map<String, Object?>)['isError'], isTrue);
    await pair.close();
  });
}
