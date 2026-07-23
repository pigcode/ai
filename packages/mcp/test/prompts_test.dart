import 'dart:async';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

import 'support/initialized_pair.dart';

void main() {
  test('prompts list, render mixed content, and announce list changes',
      () async {
    final changed = Completer<void>();
    final pair = await createInitializedMcpPair(
      serverCapabilities:
          McpServerCapabilities(prompts: true, promptListChanged: true),
      serverHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'prompts/list': (_) => <String, Object?>{
                'prompts': <Object?>[
                  <String, Object?>{
                    'name': 'inspect',
                    'arguments': <Object?>[
                      <String, Object?>{'name': 'path', 'required': true},
                    ],
                  },
                ],
              },
          'prompts/get': (_) => <String, Object?>{
                'messages': _mixedPromptMessages,
              },
        },
      ),
      clientHandlers: McpHandlerSet(
        notifications: <String, McpNotificationHandler>{
          'notifications/prompts/list_changed': (_) {
            if (!changed.isCompleted) changed.complete();
          },
        },
      ),
    );

    final listed = await pair.client.listPrompts(mcpPageRequest());
    expect(
      (listed.toJson()! as Map<String, Object?>)['prompts'],
      hasLength(1),
    );
    final prompt = await pair.client.getPrompt(
      McpGetPromptRequestParams.fromJson(
        const <String, Object?>{
          'name': 'inspect',
          'arguments': <String, Object?>{'path': 'README.md'},
        },
      ),
    );
    expect(
      (prompt.toJson()! as Map<String, Object?>)['messages'],
      hasLength(5),
    );

    await pair.server.notifyPromptListChanged();
    await changed.future;
    await pair.close();
  });
}

const _mixedPromptMessages = <Object?>[
  <String, Object?>{
    'role': 'user',
    'content': <String, Object?>{
      'type': 'text',
      'text': 'inspect',
      'annotations': <String, Object?>{'priority': 0.5},
    },
  },
  <String, Object?>{
    'role': 'user',
    'content': <String, Object?>{
      'type': 'image',
      'data': 'AA==',
      'mimeType': 'image/png',
    },
  },
  <String, Object?>{
    'role': 'user',
    'content': <String, Object?>{
      'type': 'audio',
      'data': 'AA==',
      'mimeType': 'audio/wav',
    },
  },
  <String, Object?>{
    'role': 'user',
    'content': <String, Object?>{
      'type': 'resource_link',
      'name': 'readme',
      'uri': 'file:///workspace/README.md',
    },
  },
  <String, Object?>{
    'role': 'user',
    'content': <String, Object?>{
      'type': 'resource',
      'resource': <String, Object?>{
        'uri': 'file:///workspace/README.md',
        'text': 'embedded',
      },
    },
  },
];
