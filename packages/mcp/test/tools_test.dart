import 'dart:async';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

import 'support/initialized_pair.dart';

void main() {
  test('tools preserve JSON Schema 2020-12 and mixed result content', () async {
    final changed = Completer<void>();
    final pair = await createInitializedMcpPair(
      serverCapabilities:
          McpServerCapabilities(tools: true, toolListChanged: true),
      serverHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'tools/list': (_) => <String, Object?>{
                'tools': <Object?>[_toolDefinition],
              },
          'tools/call': (_) => <String, Object?>{
                'content': <Object?>[
                  <String, Object?>{'type': 'text', 'text': 'done'},
                  <String, Object?>{
                    'type': 'image',
                    'data': 'AA==',
                    'mimeType': 'image/png',
                  },
                  <String, Object?>{
                    'type': 'audio',
                    'data': 'AA==',
                    'mimeType': 'audio/wav',
                  },
                  <String, Object?>{
                    'type': 'resource_link',
                    'name': 'result',
                    'uri': 'file:///workspace/result.txt',
                  },
                  <String, Object?>{
                    'type': 'resource',
                    'resource': <String, Object?>{
                      'uri': 'file:///workspace/result.txt',
                      'text': 'done',
                    },
                  },
                ],
                'structuredContent': <String, Object?>{'value': 'done'},
              },
        },
      ),
      clientHandlers: McpHandlerSet(
        notifications: <String, McpNotificationHandler>{
          'notifications/tools/list_changed': (_) {
            if (!changed.isCompleted) changed.complete();
          },
        },
      ),
    );

    final tools = await pair.client.listTools(mcpPageRequest());
    final tool = ((tools.toJson()! as Map<String, Object?>)['tools']! as List)
        .single as Map<String, Object?>;
    expect(
      (tool['inputSchema']! as Map<String, Object?>)['\$schema'],
      'https://json-schema.org/draft/2020-12/schema',
    );

    final result = await pair.client.callTool(
      McpCallToolRequestParams.fromJson(
        const <String, Object?>{
          'name': 'fixed',
          'arguments': <String, Object?>{'value': 'done'},
        },
      ),
    );
    expect(
      (result.toJson()! as Map<String, Object?>)['content'],
      hasLength(5),
    );
    await pair.server.notifyToolListChanged();
    await changed.future;
    await pair.close();
  });
}

const _toolDefinition = <String, Object?>{
  'name': 'fixed',
  'annotations': <String, Object?>{
    'title': 'Hints are not authorization',
    'readOnlyHint': true,
  },
  'inputSchema': <String, Object?>{
    '\$schema': 'https://json-schema.org/draft/2020-12/schema',
    'type': 'object',
    'properties': <String, Object?>{
      'value': <String, Object?>{'type': 'string'},
    },
    'required': <Object?>['value'],
  },
  'outputSchema': <String, Object?>{
    '\$schema': 'https://json-schema.org/draft/2020-12/schema',
    'type': 'object',
    'properties': <String, Object?>{
      'value': <String, Object?>{'type': 'string'},
    },
    'required': <Object?>['value'],
  },
};
