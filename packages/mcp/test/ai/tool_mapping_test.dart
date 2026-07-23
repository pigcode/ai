import 'dart:async';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

import '../support/initialized_pair.dart';

void main() {
  test('preserves exact name, description, schema, and annotations', () async {
    final pair = await _createToolPair();
    addTearDown(pair.close);
    final tools = McpToolAdapter(pair.client).mapTools(<McpTool>[_tool]);

    expect(tools.keys, <String>['inspect']);
    final mapped = tools['inspect']!;
    expect(mapped.description, 'Inspect input');
    expect(mapped.inputSchema!.value[r'$schema'], contains('2020-12'));
    expect(mapped.inputSchema!.value[r'$defs'], isNotEmpty);
    expect(mapped.inputSchema!.value['additionalProperties'], isFalse);
    expect(
      mapped.providerOptions!['mcp']!['annotations'],
      containsPair('readOnlyHint', true),
    );

    final languageTool = buildLanguageModelTools(tools).single as FunctionTool;
    expect(
      languageTool.providerOptions!['mcp']!['annotations'],
      containsPair('readOnlyHint', true),
    );
  });

  test('fails collisions unless caller supplies deterministic prefix',
      () async {
    final pair = await _createToolPair();
    addTearDown(pair.close);
    final adapter = McpToolAdapter(pair.client);
    expect(
      () => adapter.mapTools(<McpTool>[
        _tool
      ], existing: <String, Tool>{
        'inspect': Tool(
          inputSchema: const JsonSchema(<String, Object?>{'type': 'object'}),
        ),
      }),
      throwsA(isA<McpToolNameCollisionException>()),
    );

    final prefixed = McpToolAdapter(
      pair.client,
      namePolicy: const McpToolNamePolicy.prefixed('serverA'),
    ).mapTools(<McpTool>[_tool]);
    expect(prefixed.keys.single, 'serverA_inspect');
  });

  test('forwards AI cancellation to the matching MCP request', () async {
    final cancelled = Completer<Object?>();
    final pair = await _createToolPair(
      callHandler: (invocation) async {
        invocation.cancellation.onCancel((reason) {
          if (!cancelled.isCompleted) cancelled.complete(reason);
        });
        await cancelled.future;
        return const <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'cancel observed'},
          ],
        };
      },
    );
    addTearDown(pair.close);
    final tool =
        McpToolAdapter(pair.client).mapTools(<McpTool>[_tool]).values.single;
    final controller = CancellationController();

    final pending = tool.execute!(
      <String, Object?>{'value': 'x'},
      ToolExecuteOptions(
        toolCallId: 'call-1',
        messages: const [],
        cancellation: controller.signal,
      ),
    );
    controller.cancel('stop');

    expect(await cancelled.future, 'stop');
    expect(await pending, isA<McpCallToolResult>());
  });

  test('exposes task-augmented execution as a typed deferred handle', () async {
    final pair = await createInitializedMcpPair(
      serverCapabilities: McpServerCapabilities(
        tools: true,
        taskToolCall: true,
      ),
      serverHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'tools/list': (_) => const <String, Object?>{'tools': <Object?>[]},
          'tools/call': (_) => const <String, Object?>{
                'task': <String, Object?>{
                  'taskId': 'task::mapped',
                  'status': 'working',
                  'createdAt': '2026-07-23T00:00:00Z',
                  'lastUpdatedAt': '2026-07-23T00:00:00Z',
                  'ttl': 60000,
                },
              },
          'tasks/get': (_) => const <String, Object?>{
                'taskId': 'task::mapped',
                'status': 'completed',
                'createdAt': '2026-07-23T00:00:00Z',
                'lastUpdatedAt': '2026-07-23T00:00:01Z',
                'ttl': 60000,
              },
          'tasks/result': (_) => const <String, Object?>{
                'content': <Object?>[
                  <String, Object?>{'type': 'text', 'text': 'complete'},
                ],
              },
        },
      ),
    );
    addTearDown(pair.close);
    final definition = McpTool.fromJson(
      <String, Object?>{
        ...(_tool.toJson()! as Map<String, Object?>),
        'execution': const <String, Object?>{'taskSupport': 'required'},
      },
    );
    final tool = McpToolAdapter(pair.client)
        .mapTools(<McpTool>[definition])
        .values
        .single;

    final result = await tool.execute!(
      <String, Object?>{'value': 'x'},
      const ToolExecuteOptions(toolCallId: 'call-2', messages: []),
    );
    expect(result, isA<McpDeferredToolResult>());
    final deferred = result as McpDeferredToolResult;
    expect(deferred.taskId, 'task::mapped');
    expect(await deferred.getResult(), isA<McpCallToolResult>());
  });

  test('keeps protocol failure separate from MCP isError', () async {
    final pair = await _createToolPair(
      callHandler: (_) => throw Exception('server failure'),
    );
    addTearDown(pair.close);
    final tool =
        McpToolAdapter(pair.client).mapTools(<McpTool>[_tool]).values.single;

    await expectLater(
      tool.execute!(
        <String, Object?>{},
        const ToolExecuteOptions(toolCallId: 'call-3', messages: []),
      ),
      throwsA(isA<McpToolExecutionException>()),
    );
  });
}

Future<InitializedMcpPair> _createToolPair({
  McpRequestHandler? callHandler,
}) =>
    createInitializedMcpPair(
      serverCapabilities: McpServerCapabilities(tools: true),
      serverHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'tools/list': (_) => <String, Object?>{
                'tools': <Object?>[_tool.toJson()]
              },
          'tools/call': callHandler ??
              (_) => const <String, Object?>{
                    'content': <Object?>[
                      <String, Object?>{'type': 'text', 'text': 'done'},
                    ],
                  },
        },
      ),
    );

final McpTool _tool = McpTool.fromJson(
  const <String, Object?>{
    'name': 'inspect',
    'description': 'Inspect input',
    'annotations': <String, Object?>{
      'readOnlyHint': true,
      'unknownHint': 'kept',
    },
    'inputSchema': <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      r'$defs': <String, Object?>{
        'Value': <String, Object?>{'type': 'string'},
      },
      'type': 'object',
      'properties': <String, Object?>{
        'value': <String, Object?>{r'$ref': '#/\$defs/Value'},
      },
      'additionalProperties': false,
    },
  },
);
