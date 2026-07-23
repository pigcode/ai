import 'dart:async';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

import 'support/initialized_pair.dart';

void main() {
  test('resources cover list, templates, read, subscriptions, and changes',
      () async {
    final listChanged = Completer<void>();
    final updated = Completer<String>();
    final pair = await createInitializedMcpPair(
      serverCapabilities: McpServerCapabilities(
        resources: true,
        resourceSubscribe: true,
        resourceListChanged: true,
      ),
      serverHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'resources/list': (_) => <String, Object?>{
                'resources': <Object?>[
                  <String, Object?>{
                    'name': 'readme',
                    'uri': 'file:///workspace/README.md',
                    'annotations': <String, Object?>{
                      'audience': <Object?>['user'],
                      'priority': 1,
                    },
                  },
                ],
              },
          'resources/templates/list': (_) => <String, Object?>{
                'resourceTemplates': <Object?>[
                  <String, Object?>{
                    'name': 'file',
                    'uriTemplate': 'file:///{path}',
                  },
                ],
              },
          'resources/read': (_) => <String, Object?>{
                'contents': <Object?>[
                  <String, Object?>{
                    'uri': 'file:///workspace/README.md',
                    'text': 'hello',
                    'mimeType': 'text/markdown',
                  },
                  <String, Object?>{
                    'uri': 'file:///workspace/icon.png',
                    'blob': 'AA==',
                    'mimeType': 'image/png',
                  },
                ],
              },
          'resources/subscribe': (_) => const <String, Object?>{},
          'resources/unsubscribe': (_) => const <String, Object?>{},
        },
      ),
      clientHandlers: McpHandlerSet(
        notifications: <String, McpNotificationHandler>{
          'notifications/resources/list_changed': (_) {
            if (!listChanged.isCompleted) {
              listChanged.complete();
            }
          },
          'notifications/resources/updated': (invocation) {
            final params = invocation.params! as Map<String, Object?>;
            if (!updated.isCompleted) {
              updated.complete(params['uri']! as String);
            }
          },
        },
      ),
    );

    final resources = await pair.client.listResources(mcpPageRequest());
    expect(
      (resources.toJson()! as Map<String, Object?>)['resources'],
      hasLength(1),
    );
    final templates = await pair.client.listResourceTemplates(mcpPageRequest());
    expect(
      (templates.toJson()! as Map<String, Object?>)['resourceTemplates'],
      hasLength(1),
    );
    final contents = await pair.client.readResource(
      McpReadResourceRequestParams.fromJson(
        const <String, Object?>{'uri': 'file:///workspace/README.md'},
      ),
    );
    expect(
      (contents.toJson()! as Map<String, Object?>)['contents'],
      hasLength(2),
    );
    await pair.client.subscribeResource(
      McpSubscribeRequestParams.fromJson(
        const <String, Object?>{'uri': 'file:///workspace/README.md'},
      ),
    );
    await pair.client.unsubscribeResource(
      McpUnsubscribeRequestParams.fromJson(
        const <String, Object?>{'uri': 'file:///workspace/README.md'},
      ),
    );

    await pair.server.notifyResourceListChanged();
    await pair.server.notifyResourceUpdated(
      McpResourceUpdatedNotificationParams.fromJson(
        const <String, Object?>{'uri': 'file:///workspace/README.md'},
      ),
    );
    await listChanged.future;
    expect(await updated.future, 'file:///workspace/README.md');
    await pair.close();
  });
}
