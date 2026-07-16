import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('convertToOpenAiResponsesInput — system message modes', () {
    test('system mode maps to role:system', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [const SystemMessage('be helpful')],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {'role': 'system', 'content': 'be helpful'},
      ]);
      expect(result.warnings, isEmpty);
    });

    test('developer mode maps to role:developer', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [const SystemMessage('be helpful')],
        systemMessageMode: SystemMessageMode.developer,
        store: true,
      );

      expect(result.input, [
        {'role': 'developer', 'content': 'be helpful'},
      ]);
    });

    test('remove mode drops the message and emits a warning', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [const SystemMessage('be helpful')],
        systemMessageMode: SystemMessageMode.remove,
        store: true,
      );

      expect(result.input, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, isA<OtherWarning>());
    });
  });

  group('convertToOpenAiResponsesInput — user text', () {
    test('single text part maps to input_text', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const UserMessage([TextPart('hello')]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'hello'},
          ],
        },
      ]);
    });
  });

  group('convertToOpenAiResponsesInput — assistant text', () {
    test(
        'text without itemId is sent inline with no id key (no item_reference)',
        () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([TextPart('hi there')]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': 'hi there'},
          ],
        },
      ]);
      final item = result.input.single;
      expect(item.containsKey('id'), isFalse);
    });

    test('text with itemId and store==true uses item_reference', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            TextPart(
              'hi there',
              providerOptions: {
                'openai': {'itemId': 'msg_123'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {'type': 'item_reference', 'id': 'msg_123'},
      ]);
    });

    test('text with itemId and store==false is sent inline with id', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            TextPart(
              'hi there',
              providerOptions: {
                'openai': {'itemId': 'msg_123'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
      );

      expect(result.input, [
        {
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': 'hi there'},
          ],
          'id': 'msg_123',
        },
      ]);
    });
  });

  group('convertToOpenAiResponsesInput — function_call round-trip', () {
    test('tool-call maps to function_call, tool-result to function_call_output',
        () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'nyc'},
            ),
          ]),
          const ToolMessage([
            ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              output: ToolResultText('sunny'),
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {
          'type': 'function_call',
          'call_id': 'call_1',
          'name': 'get_weather',
          'arguments': '{"city":"nyc"}',
        },
        {
          'type': 'function_call_output',
          'call_id': 'call_1',
          'output': 'sunny',
        },
      ]);
    });

    test('store:false mcp approval response without continuation is skipped',
        () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'mcp.search',
              input: {'query': 'dart ai sdk'},
              providerExecuted: true,
            ),
            ToolApprovalRequestPart(
              approvalId: 'approval_1',
              toolCallId: 'call_1',
            ),
          ]),
          const ToolMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval_1',
              approved: true,
              reason: 'approved by user',
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
      );

      expect(result.input, isEmpty);
      expect(result.warnings, hasLength(1));
    });

    test('store:false MCP approval replays request before the response', () {
      const approvalItem = <String, Object?>{
        'type': 'mcp_approval_request',
        'id': 'approval_item_1',
        'approval_request_id': 'approval_1',
        'server_label': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
      };
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'mcp.search',
              input: {'query': 'dart ai sdk'},
              providerExecuted: true,
              providerOptions: {
                'openai': {'itemId': 'approval_item_1', 'item': approvalItem},
              },
            ),
            ToolApprovalRequestPart(
              approvalId: 'approval_1',
              toolCallId: 'call_1',
              providerOptions: {
                'openai': {'itemId': 'approval_item_1', 'item': approvalItem},
              },
            ),
          ]),
          const ToolMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval_1',
              approved: true,
              reason: 'approved by user',
              providerOptions: {
                'openai': {'itemId': 'approval_item_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
      );

      expect(result.input, [
        approvalItem,
        {
          'type': 'mcp_approval_response',
          'approval_request_id': 'approval_1',
          'approve': true,
          'reason': 'approved by user',
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('store:false MCP approval can replay request keyed by item id', () {
      const approvalItem = <String, Object?>{
        'type': 'mcp_approval_request',
        'id': 'approval_item_1',
        'server_label': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
      };
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'mcp.search',
              input: {'query': 'dart ai sdk'},
              providerExecuted: true,
              providerOptions: {
                'openai': {'itemId': 'approval_item_1', 'item': approvalItem},
              },
            ),
            ToolApprovalRequestPart(
              approvalId: 'approval_item_1',
              toolCallId: 'call_1',
              providerOptions: {
                'openai': {'itemId': 'approval_item_1', 'item': approvalItem},
              },
            ),
          ]),
          const ToolMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval_item_1',
              approved: true,
              providerOptions: {
                'openai': {'itemId': 'approval_item_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
      );

      expect(result.input, [
        approvalItem,
        {
          'type': 'mcp_approval_response',
          'approval_request_id': 'approval_item_1',
          'approve': true,
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('local tool approval response is not sent as MCP approval', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'nyc'},
            ),
            ToolApprovalRequestPart(
              approvalId: 'approval_1',
              toolCallId: 'call_1',
            ),
          ]),
          const ToolMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval_1',
              approved: true,
              reason: 'approved by user',
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
      );

      expect(
        result.input.where(
          (item) => item['type'] == 'mcp_approval_response',
        ),
        isEmpty,
      );
      expect(result.input, [
        {
          'type': 'function_call',
          'call_id': 'call_1',
          'name': 'get_weather',
          'arguments': '{"city":"nyc"}',
        },
      ]);
      expect(result.warnings, hasLength(2));
    });

    test('stored tool approval response also sends an item reference', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'mcp.search',
              input: {'query': 'dart ai sdk'},
              providerExecuted: true,
            ),
            ToolApprovalRequestPart(
              approvalId: 'approval_1',
              toolCallId: 'call_1',
            ),
          ]),
          const ToolMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval_1',
              approved: false,
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {'type': 'item_reference', 'id': 'approval_1'},
        {
          'type': 'mcp_approval_response',
          'approval_request_id': 'approval_1',
          'approve': false,
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('stored MCP approval response references the approval item once', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'mcp.search',
              input: {'query': 'dart ai sdk'},
              providerExecuted: true,
              providerOptions: {
                'openai': {'itemId': 'approval_item_1'},
              },
            ),
            ToolApprovalRequestPart(
              approvalId: 'approval_1',
              toolCallId: 'call_1',
              providerOptions: {
                'openai': {'itemId': 'approval_item_1'},
              },
            ),
          ]),
          const ToolMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval_1',
              approved: true,
              providerOptions: {
                'openai': {'itemId': 'approval_item_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {'type': 'item_reference', 'id': 'approval_item_1'},
        {
          'type': 'mcp_approval_response',
          'approval_request_id': 'approval_1',
          'approve': true,
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('previousResponseId tool approval response omits item reference', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'mcp.search',
              input: {'query': 'dart ai sdk'},
              providerExecuted: true,
            ),
            ToolApprovalRequestPart(
              approvalId: 'approval_1',
              toolCallId: 'call_1',
            ),
          ]),
          const ToolMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval_1',
              approved: true,
              providerOptions: {
                'openai': {'itemId': 'approval_item_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasPreviousResponseId: true,
      );

      expect(result.input, [
        {
          'type': 'mcp_approval_response',
          'approval_request_id': 'approval_1',
          'approve': true,
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('conversation tool approval response omits item reference', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'mcp.search',
              input: {'query': 'dart ai sdk'},
              providerExecuted: true,
            ),
            ToolApprovalRequestPart(
              approvalId: 'approval_1',
              toolCallId: 'call_1',
            ),
          ]),
          const ToolMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval_1',
              approved: true,
              providerOptions: {
                'openai': {'itemId': 'approval_item_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasConversation: true,
      );

      expect(result.input, [
        {
          'type': 'mcp_approval_response',
          'approval_request_id': 'approval_1',
          'approve': true,
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('continuation tool approval response works without local request', () {
      final previousResponseIdResult = convertToOpenAiResponsesInput(
        prompt: [
          const ToolMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval_1',
              approved: true,
              providerOptions: {
                'openai': {'itemId': 'approval_item_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasPreviousResponseId: true,
      );
      final conversationResult = convertToOpenAiResponsesInput(
        prompt: [
          const ToolMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval_1',
              approved: true,
              providerOptions: {
                'openai': {'itemId': 'approval_item_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasConversation: true,
      );

      final expected = [
        {
          'type': 'mcp_approval_response',
          'approval_request_id': 'approval_1',
          'approve': true,
        },
      ];
      expect(previousResponseIdResult.input, expected);
      expect(previousResponseIdResult.warnings, isEmpty);
      expect(conversationResult.input, expected);
      expect(conversationResult.warnings, isEmpty);
    });

    test('continuation local approval response without metadata is skipped',
        () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const ToolMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval_1',
              approved: true,
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasPreviousResponseId: true,
      );

      expect(result.input, isEmpty);
      expect(result.warnings, hasLength(1));
    });

    test('stored MCP provider call is replayed as an item reference', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'mcp_1',
              toolName: 'mcp.search',
              input: {'query': 'dart ai sdk'},
              providerExecuted: true,
              providerOptions: {
                'openai': {'itemId': 'mcp_1'},
              },
            ),
            ToolResultPart(
              toolCallId: 'mcp_1',
              toolName: 'mcp.search',
              output: ToolResultJson({'ok': true}),
              providerOptions: {
                'openai': {'itemId': 'mcp_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {'type': 'item_reference', 'id': 'mcp_1'},
      ]);
      expect(result.warnings, isEmpty);
    });

    test('non-stored MCP provider call is replayed as a raw item', () {
      const mcpCallItem = <String, Object?>{
        'type': 'mcp_call',
        'id': 'mcp_1',
        'status': 'completed',
        'server_label': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
        'output': '{"ok":true}',
      };
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'mcp_1',
              toolName: 'mcp.search',
              input: {'query': 'dart ai sdk'},
              providerExecuted: true,
              providerOptions: {
                'openai': {'itemId': 'mcp_1', 'item': mcpCallItem},
              },
            ),
            ToolResultPart(
              toolCallId: 'mcp_1',
              toolName: 'mcp.search',
              output: ToolResultJson({'ok': true}),
              providerOptions: {
                'openai': {'itemId': 'mcp_1', 'item': mcpCallItem},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
      );

      expect(result.input, [mcpCallItem]);
      expect(result.warnings, isEmpty);
    });

    test('stored MCP provider result can replay the item reference', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolResultPart(
              toolCallId: 'mcp_1',
              toolName: 'mcp.search',
              output: ToolResultJson({'ok': true}),
              providerOptions: {
                'openai': {'itemId': 'mcp_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {'type': 'item_reference', 'id': 'mcp_1'},
      ]);
      expect(result.warnings, isEmpty);
    });

    test('server-side continuation does not resend stored MCP provider call',
        () {
      const content = <AssistantContentPart>[
        ToolCallPart(
          toolCallId: 'mcp_1',
          toolName: 'mcp.search',
          input: {'query': 'dart ai sdk'},
          providerExecuted: true,
          providerOptions: {
            'openai': {'itemId': 'mcp_1'},
          },
        ),
        ToolResultPart(
          toolCallId: 'mcp_1',
          toolName: 'mcp.search',
          output: ToolResultJson({'ok': true}),
          providerOptions: {
            'openai': {'itemId': 'mcp_1'},
          },
        ),
      ];

      final previousResponseIdResult = convertToOpenAiResponsesInput(
        prompt: [AssistantMessage(content)],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasPreviousResponseId: true,
      );
      final conversationResult = convertToOpenAiResponsesInput(
        prompt: [AssistantMessage(content)],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasConversation: true,
      );

      expect(previousResponseIdResult.input, isEmpty);
      expect(previousResponseIdResult.warnings, isEmpty);
      expect(conversationResult.input, isEmpty);
      expect(conversationResult.warnings, isEmpty);
    });

    test('null input falls back to "{}" instead of the literal "null"', () {
      // 回归 Fix 3:逐字对齐上游 `serializeToolCallArguments`
      // (`input === undefined ? {} : input`)——`part.input` 为 null 时
      // 不应产出 `jsonEncode(null)` 的字面量 `"null"`。
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_2',
              toolName: 'ping',
              input: null,
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {
          'type': 'function_call',
          'call_id': 'call_2',
          'name': 'ping',
          'arguments': '{}',
        },
      ]);
    });

    test('stored provider-defined call is replayed as an item reference', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_patch',
              toolName: 'apply_patch',
              input: {
                'callId': 'call_patch',
                'operation': {
                  'type': 'delete_file',
                  'path': 'obsolete.dart',
                },
              },
              providerOptions: {
                'openai': {'itemId': 'apc_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        tools: [openAiTools.applyPatch()],
      );

      expect(result.input, [
        {'type': 'item_reference', 'id': 'apc_1'},
      ]);
      expect(result.warnings, isEmpty);
    });

    test('provider-defined tool results map to Responses output items', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const ToolMessage([
            ToolResultPart(
              toolCallId: 'call_patch',
              toolName: 'apply_patch',
              output: ToolResultJson({
                'status': 'completed',
                'output': 'patched',
              }),
            ),
            ToolResultPart(
              toolCallId: 'call_shell',
              toolName: 'shell',
              output: ToolResultJson({
                'maxOutputLength': 4096,
                'output': [
                  {
                    'stdout': 'done\n',
                    'stderr': '',
                    'outcome': {'type': 'exit', 'exitCode': 0},
                  },
                ],
              }),
            ),
            ToolResultPart(
              toolCallId: 'call_custom',
              toolName: 'grammar_out',
              output: ToolResultText('ok'),
            ),
            ToolResultPart(
              toolCallId: 'call_tool_search',
              toolName: 'tool_search',
              output: ToolResultJson({
                'tools': [
                  {'type': 'function', 'name': 'get_weather'},
                ],
              }),
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
        tools: [
          openAiTools.applyPatch(),
          openAiTools.shell(),
          openAiTools.customTool(name: 'grammar_out'),
          openAiTools.toolSearch(execution: 'client'),
        ],
      );

      expect(result.input, [
        {
          'type': 'apply_patch_call_output',
          'call_id': 'call_patch',
          'status': 'completed',
          'output': 'patched',
        },
        {
          'type': 'shell_call_output',
          'call_id': 'call_shell',
          'max_output_length': 4096,
          'output': [
            {
              'stdout': 'done\n',
              'stderr': '',
              'outcome': {'type': 'exit', 'exit_code': 0},
            },
          ],
        },
        {
          'type': 'custom_tool_call_output',
          'call_id': 'call_custom',
          'output': 'ok',
        },
        {
          'type': 'tool_search_output',
          'execution': 'client',
          'call_id': 'call_tool_search',
          'status': 'completed',
          'tools': [
            {'type': 'function', 'name': 'get_weather'},
          ],
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('invalid provider-defined tool result is skipped after warning', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const ToolMessage([
            ToolResultPart(
              toolCallId: 'call_patch',
              toolName: 'apply_patch',
              output: ToolResultText('done'),
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
        tools: [openAiTools.applyPatch()],
      );

      expect(result.input, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, isA<OtherWarning>());
      expect(
        (result.warnings.single as OtherWarning).message,
        contains(
            'OpenAI provider tool apply_patch result must be a JSON object'),
      );
    });

    test('invalid shell output entries are skipped after warning', () {
      for (final invalidEntry in const <Object?>[
        'not an object',
        {
          'stdout': '',
          'stderr': '',
          'outcome': 'exit',
        },
      ]) {
        final result = convertToOpenAiResponsesInput(
          prompt: [
            ToolMessage([
              ToolResultPart(
                toolCallId: 'call_shell',
                toolName: 'shell',
                output: ToolResultJson({
                  'output': [invalidEntry],
                }),
              ),
            ]),
          ],
          systemMessageMode: SystemMessageMode.system,
          store: false,
          tools: [openAiTools.shell()],
        );

        expect(result.input, isEmpty);
        expect(result.warnings, hasLength(1));
        expect(result.warnings.single, isA<OtherWarning>());
        expect(
          (result.warnings.single as OtherWarning).message,
          contains('OpenAI provider tool shell result must be a JSON object'),
        );
      }
    });
  });

  group('convertToOpenAiResponsesInput — MCP list tools context', () {
    const mcpListToolsItem = <String, Object?>{
      'type': 'mcp_list_tools',
      'id': 'mcp_list_1',
      'server_label': 'dmcp',
      'tools': [
        <String, Object?>{'name': 'search'},
      ],
    };

    test('mcp_list_tools custom part round-trips into input', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            CustomPart(
              'openai.mcp_list_tools',
              providerOptions: {
                'openai': {'item': mcpListToolsItem},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [mcpListToolsItem]);
      expect(result.warnings, isEmpty);
    });

    test('server-side continuation does not resend mcp_list_tools', () {
      final previousResponseIdResult = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            CustomPart(
              'openai.mcp_list_tools',
              providerOptions: {
                'openai': {'item': mcpListToolsItem},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasPreviousResponseId: true,
      );
      final conversationResult = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            CustomPart(
              'openai.mcp_list_tools',
              providerOptions: {
                'openai': {'item': mcpListToolsItem},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasConversation: true,
      );

      expect(previousResponseIdResult.input, isEmpty);
      expect(previousResponseIdResult.warnings, isEmpty);
      expect(conversationResult.input, isEmpty);
      expect(conversationResult.warnings, isEmpty);
    });
  });

  group('convertToOpenAiResponsesInput — reasoning without itemId', () {
    test('encrypted_content fallback never emits a null id key', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ReasoningPart(
              'thinking...',
              providerOptions: {
                'openai': {'reasoningEncryptedContent': 'enc_abc'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {
          'type': 'reasoning',
          'encrypted_content': 'enc_abc',
          'summary': [
            {'type': 'summary_text', 'text': 'thinking...'},
          ],
        },
      ]);
      final item = result.input.single;
      expect(item.containsKey('id'), isFalse);
    });
  });

  group('convertToOpenAiResponsesInput — reasoning multi-summary merge', () {
    test(
        'store==false merges same-itemId summary parts into one item and '
        'keeps the last non-null encrypted_content', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            // 前一个 summary part 在 upstream 状态机里提前 conclude,
            // 没拿到 encrypted_content(逐字对齐 raw
            // response.reasoning_summary_part.added 分支:can-conclude
            // 转 reasoning-end 时 providerMetadata 只有 itemId)。
            ReasoningPart(
              'first summary',
              providerOptions: {
                'openai': {'itemId': 'rs_1'},
              },
            ),
            // 最后一个 summary part 在 output_item.done 才 conclude,
            // 带上 item 级别的 encrypted_content。
            ReasoningPart(
              'second summary',
              providerOptions: {
                'openai': {
                  'itemId': 'rs_1',
                  'reasoningEncryptedContent': 'enc_final',
                },
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
      );

      expect(result.input, [
        {
          'type': 'reasoning',
          'id': 'rs_1',
          'encrypted_content': 'enc_final',
          'summary': [
            {'type': 'summary_text', 'text': 'first summary'},
            {'type': 'summary_text', 'text': 'second summary'},
          ],
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test(
        'store==true merges same-itemId summary parts into a single '
        'item_reference (no duplicates)', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ReasoningPart(
              'first summary',
              providerOptions: {
                'openai': {'itemId': 'rs_2'},
              },
            ),
            ReasoningPart(
              'second summary',
              providerOptions: {
                'openai': {'itemId': 'rs_2'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {'type': 'item_reference', 'id': 'rs_2'},
      ]);
    });

    test(
        'store==false: first part has empty text, second part (same itemId) '
        'has text — does not crash, merges correctly', () {
      // 回归 Fix 2:第一个到达的 summary part 文本为空时,存入
      // `reasoningMessages` 的 `summary` 列表此前是 `const <JsonObject>[]`
      // ——同 itemId 的第二个 part 到达时对它 `addAll` 会抛
      // `UnsupportedError`(const 列表不可变)。此用例复现该序列并断言
      // 不再 crash、最终 summary 只包含非空文本的那一条。
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ReasoningPart(
              '',
              providerOptions: {
                'openai': {'itemId': 'rs_empty_first'},
              },
            ),
            ReasoningPart(
              'second summary',
              providerOptions: {
                'openai': {
                  'itemId': 'rs_empty_first',
                  'reasoningEncryptedContent': 'enc_final',
                },
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
      );

      expect(result.input, [
        {
          'type': 'reasoning',
          'id': 'rs_empty_first',
          'encrypted_content': 'enc_final',
          'summary': [
            {'type': 'summary_text', 'text': 'second summary'},
          ],
        },
      ]);
    });

    test(
        'store==false: first part has text, second part (same itemId) has '
        'empty text — skips the empty part and emits the upstream warning', () {
      // 回归 Fix 2 的另一半:已存在同 itemId 的 wire item 时,后到达的空
      // 文本 part 不应被追加为空 `summary_text`,且要产出对齐上游文案的
      // 告警(此前实现完全遗漏了这条告警)。
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ReasoningPart(
              'first summary',
              providerOptions: {
                'openai': {'itemId': 'rs_empty_second'},
              },
            ),
            ReasoningPart(
              '',
              providerOptions: {
                'openai': {
                  'itemId': 'rs_empty_second',
                  'reasoningEncryptedContent': 'enc_final',
                },
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
      );

      expect(result.input, [
        {
          'type': 'reasoning',
          'id': 'rs_empty_second',
          'encrypted_content': 'enc_final',
          'summary': [
            {'type': 'summary_text', 'text': 'first summary'},
          ],
        },
      ]);
      expect(
        result.warnings.any(
          (w) =>
              w is OtherWarning &&
              w.message.contains(
                'Cannot append empty reasoning part to existing reasoning '
                'sequence',
              ),
        ),
        isTrue,
      );
    });

    test(
        'store==false drops a reasoning item still missing encrypted_content '
        'after merging and emits a warning', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ReasoningPart(
              'only summary',
              providerOptions: {
                'openai': {'itemId': 'rs_3'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
      );

      expect(result.input, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, isA<OtherWarning>());
    });
  });

  group('convertToOpenAiResponsesInput — user file parts', () {
    test('image bytes map to input_image with data URI', () {
      final bytes = Uint8List.fromList(utf8.encode('fake-png-bytes'));
      final result = convertToOpenAiResponsesInput(
        prompt: [
          UserMessage([
            FilePart(data: FileDataBytes(bytes), mediaType: 'image/png'),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      final expectedB64 = base64Encode(bytes);
      expect(result.input, [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_image',
              'image_url': 'data:image/png;base64,$expectedB64',
            },
          ],
        },
      ]);
    });

    test('image url maps to input_image with image_url passthrough', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataUrl(Uri.parse('https://example.com/cat.png')),
              mediaType: 'image/png',
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_image',
              'image_url': 'https://example.com/cat.png',
            },
          ],
        },
      ]);
    });

    test('pdf data maps to input_file with file_data data URI', () {
      final bytes = Uint8List.fromList(utf8.encode('%PDF-1.4 fake'));
      final result = convertToOpenAiResponsesInput(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataBytes(bytes),
              mediaType: 'application/pdf',
              filename: 'doc.pdf',
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      final expectedB64 = base64Encode(bytes);
      expect(result.input, [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_file',
              'filename': 'doc.pdf',
              'file_data': 'data:application/pdf;base64,$expectedB64',
            },
          ],
        },
      ]);
    });

    test(
        'two unnamed pdf parts fall back to part-0.pdf/part-1.pdf by their '
        'index in the content array', () {
      // 回归 Fix 4:逐字对齐上游 `part.filename ?? \`part-\${index}.pdf\``
      // (raw ~200-204 行)——`index` 是该 part 在 user 消息 content 数组
      // 里的下标(与 chat 侧 `convert_messages.dart:202` 同款),不是恒定
      // 的 'file.pdf'。
      final bytes = Uint8List.fromList(utf8.encode('%PDF-1.4 fake'));
      final result = convertToOpenAiResponsesInput(
        prompt: [
          UserMessage([
            FilePart(data: FileDataBytes(bytes), mediaType: 'application/pdf'),
            FilePart(data: FileDataBytes(bytes), mediaType: 'application/pdf'),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      final content =
          (result.input.single['content']! as List<Object?>).cast<Object?>();
      final filenames = content
          .map((part) => (part! as Map<String, Object?>)['filename'])
          .toList();
      expect(filenames, ['part-0.pdf', 'part-1.pdf']);
    });

    test('index accounts for preceding text parts (not a file-only counter)',
        () {
      final bytes = Uint8List.fromList(utf8.encode('%PDF-1.4 fake'));
      final result = convertToOpenAiResponsesInput(
        prompt: [
          UserMessage([
            const TextPart('describe this'),
            FilePart(data: FileDataBytes(bytes), mediaType: 'application/pdf'),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      final content =
          (result.input.single['content']! as List<Object?>).cast<Object?>();
      final filePart = content[1]! as Map<String, Object?>;
      expect(filePart['filename'], 'part-1.pdf');
    });

    test(
        'imageDetail providerOption sets detail on input_image (data URI '
        'form)', () {
      // 回归 Fix 5:逐字对齐上游 `part.providerOptions?.[providerOptionsName]
      // ?.imageDetail`(raw ~172-175 行 data/url 分支)。
      final bytes = Uint8List.fromList(utf8.encode('fake-png-bytes'));
      final result = convertToOpenAiResponsesInput(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataBytes(bytes),
              mediaType: 'image/png',
              providerOptions: const {
                'openai': {'imageDetail': 'low'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      final content =
          (result.input.single['content']! as List<Object?>).cast<Object?>();
      final imagePart = content.single! as Map<String, Object?>;
      expect(imagePart['detail'], 'low');
    });

    test(
        'imageDetail providerOption sets detail on input_image (file '
        'reference form)', () {
      // 回归 Fix 5:逐字对齐上游 `part.providerOptions?.[providerOptionsName]
      // ?.imageDetail`(raw ~141-144 行 reference 分支)。
      final result = convertToOpenAiResponsesInput(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataReference({'openai': 'file-abc123'}),
              mediaType: 'image/png',
              providerOptions: const {
                'openai': {'imageDetail': 'high'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_image',
              'file_id': 'file-abc123',
              'detail': 'high',
            },
          ],
        },
      ]);
    });

    test('imageDetail absent does not add a detail key', () {
      final bytes = Uint8List.fromList(utf8.encode('fake-png-bytes'));
      final result = convertToOpenAiResponsesInput(
        prompt: [
          UserMessage([
            FilePart(data: FileDataBytes(bytes), mediaType: 'image/png'),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      final content =
          (result.input.single['content']! as List<Object?>).cast<Object?>();
      final imagePart = content.single! as Map<String, Object?>;
      expect(imagePart.containsKey('detail'), isFalse);
    });

    test('non-pdf non-image data throws UnsupportedFunctionalityError', () {
      expect(
        () => convertToOpenAiResponsesInput(
          prompt: [
            UserMessage([
              FilePart(
                data: FileDataBytes(Uint8List(0)),
                mediaType: 'text/csv',
              ),
            ]),
          ],
          systemMessageMode: SystemMessageMode.system,
          store: true,
        ),
        throwsA(isA<UnsupportedFunctionalityError>()),
      );
    });

    test('provider reference resolves via the openai key', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataReference({'openai': 'file-abc123'}),
              mediaType: 'image/png',
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {
          'role': 'user',
          'content': [
            {'type': 'input_image', 'file_id': 'file-abc123'},
          ],
        },
      ]);
    });
  });

  group('convertToOpenAiResponsesInput — tool-result content output', () {
    test('content list maps to input_text/input_image array', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const ToolMessage([
            ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'search',
              output: ToolResultContentOutput([
                ToolResultTextItem('found it'),
              ]),
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      expect(result.input, [
        {
          'type': 'function_call_output',
          'call_id': 'call_1',
          'output': [
            {'type': 'input_text', 'text': 'found it'},
          ],
        },
      ]);
    });
  });

  group(
      'convertToOpenAiResponsesInput — hasPreviousResponseId continuation '
      'mode', () {
    test(
        'stored assistant text (itemId present) is not skipped, sent as '
        'item_reference (hasPreviousResponseId does not affect text parts)',
        () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            TextPart(
              'hi there',
              providerOptions: {
                'openai': {'itemId': 'msg_123'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasPreviousResponseId: true,
      );

      // Fix 1 逐字对齐上游:`hasPreviousResponseId` 只对 reasoning 与
      // plain function-call 生效,text part 不受影响(仍按 store 走
      // item_reference)——此用例覆盖「非 stored 项恒保留」的回归要求。
      expect(result.input, [
        {'type': 'item_reference', 'id': 'msg_123'},
      ]);
    });

    test(
        'stored reasoning item (itemId present) is skipped entirely in '
        'continuation mode', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ReasoningPart(
              'thinking...',
              providerOptions: {
                'openai': {'itemId': 'rs_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasPreviousResponseId: true,
      );

      expect(result.input, isEmpty);
    });

    test(
        'stored plain function-call (itemId present) is skipped entirely in '
        'continuation mode', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'nyc'},
              providerOptions: {
                'openai': {'itemId': 'fc_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasPreviousResponseId: true,
      );

      expect(result.input, isEmpty);
    });

    test(
        'stored client tool_search call is skipped but output is sent in '
        'continuation mode', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_tool_search',
              toolName: 'tool_search',
              input: {
                'call_id': 'call_tool_search',
                'arguments': '{}',
              },
              providerOptions: {
                'openai': {'itemId': 'ts_1'},
              },
            ),
          ]),
          const ToolMessage([
            ToolResultPart(
              toolCallId: 'call_tool_search',
              toolName: 'tool_search',
              output: ToolResultJson({'tools': <Object?>[]}),
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasPreviousResponseId: true,
        tools: [openAiTools.toolSearch(execution: 'client')],
      );

      expect(result.input, [
        {
          'type': 'tool_search_output',
          'execution': 'client',
          'call_id': 'call_tool_search',
          'status': 'completed',
          'tools': <Object?>[],
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test(
        'function-call without itemId is still sent (not part of a stored '
        'chain)', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'nyc'},
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasPreviousResponseId: true,
      );

      expect(result.input, [
        {
          'type': 'function_call',
          'call_id': 'call_1',
          'name': 'get_weather',
          'arguments': '{"city":"nyc"}',
        },
      ]);
    });

    test(
        'without continuation mode, item_reference behavior does not '
        'regress', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            TextPart(
              'hi there',
              providerOptions: {
                'openai': {'itemId': 'msg_123'},
              },
            ),
            ReasoningPart(
              'thinking...',
              providerOptions: {
                'openai': {'itemId': 'rs_1'},
              },
            ),
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'nyc'},
              providerOptions: {
                'openai': {'itemId': 'fc_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
      );

      // 首版转换器对 plain function-call 恒内联为 `function_call`(不走
      // item_reference,与 raw 的 provider-defined-tool-only item_reference
      // 语义一致);只有 text/reasoning 在 store==true 时走 item_reference。
      expect(result.input, [
        {'type': 'item_reference', 'id': 'msg_123'},
        {'type': 'item_reference', 'id': 'rs_1'},
        {
          'type': 'function_call',
          'call_id': 'call_1',
          'name': 'get_weather',
          'arguments': '{"city":"nyc"}',
        },
      ]);
    });
  });

  group('convertToOpenAiResponsesInput — hasConversation continuation mode',
      () {
    test(
        'stored assistant text/reasoning/function-call (itemId present) are '
        'all skipped', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            TextPart(
              'hi there',
              providerOptions: {
                'openai': {'itemId': 'msg_123'},
              },
            ),
            ReasoningPart(
              'thinking...',
              providerOptions: {
                'openai': {'itemId': 'rs_1'},
              },
            ),
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'nyc'},
              providerOptions: {
                'openai': {'itemId': 'fc_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasConversation: true,
      );

      // 与 hasPreviousResponseId 不同:上游 `hasConversation` 对带 itemId
      // 的 assistant text 也生效(raw ~234-237 行,避免 "Duplicate item
      // found"),三类 stored part 全部跳过。
      expect(result.input, isEmpty);
    });

    test(
        'parts without itemId are still sent (not yet part of the '
        'conversation context)', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const UserMessage([TextPart('question')]),
          const AssistantMessage([
            TextPart('local text'),
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'nyc'},
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasConversation: true,
      );

      expect(result.input, [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'question'},
          ],
        },
        {
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': 'local text'},
          ],
        },
        {
          'type': 'function_call',
          'call_id': 'call_1',
          'name': 'get_weather',
          'arguments': '{"city":"nyc"}',
        },
      ]);
    });

    test('tool-call with itemId is skipped even when store is false', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'nyc'},
              providerOptions: {
                'openai': {'itemId': 'fc_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: false,
        hasConversation: true,
      );

      // 上游 raw ~278 行的 `hasConversation && id != null` 不检查 store
      // (与 hasPreviousResponseId 的 ~326 行不同)。
      expect(result.input, isEmpty);
    });
  });

  group('convertToOpenAiResponsesInput — providerOptionsName (azure)', () {
    test(
        'providerOptionsName: azure + itemId under "azure" key makes '
        'store==true text emit item_reference', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            TextPart(
              'hello',
              providerOptions: {
                'azure': {'itemId': 'msg_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        providerOptionsName: 'azure',
      );

      expect(result.input, [
        {'type': 'item_reference', 'id': 'msg_1'},
      ]);
    });

    test(
        'providerOptionsName: azure + hasConversation skips stored text '
        'itemId under the "azure" key', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            TextPart(
              'hello',
              providerOptions: {
                'azure': {'itemId': 'msg_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasConversation: true,
        providerOptionsName: 'azure',
      );

      expect(result.input, isEmpty);
    });

    test(
        'providerOptionsName: azure + hasPreviousResponseId skips stored '
        'function-call itemId under the "azure" key', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'nyc'},
              providerOptions: {
                'azure': {'itemId': 'fc_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        hasPreviousResponseId: true,
        providerOptionsName: 'azure',
      );

      expect(result.input, isEmpty);
    });

    test(
        'providerOptionsName: azure — an itemId under the "openai" key is '
        'not recognized (no fallback, unlike the upstream converter)', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          const AssistantMessage([
            TextPart(
              'hello',
              providerOptions: {
                'openai': {'itemId': 'msg_1'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        providerOptionsName: 'azure',
      );

      // 未命中 'azure' 键,itemId 视为 null:按无 itemId 的路径内联重建,
      // 而不是发 item_reference(对齐上游无 fallback 的读取语义)。
      expect(result.input, [
        {
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': 'hello'},
          ],
        },
      ]);
    });

    test(
        'providerOptionsName: azure + FileDataReference resolves the '
        '"azure" key', () {
      final result = convertToOpenAiResponsesInput(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataReference({'azure': 'file_1'}),
              mediaType: 'application/pdf',
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        providerOptionsName: 'azure',
      );

      expect(result.input, [
        {
          'role': 'user',
          'content': [
            {'type': 'input_file', 'file_id': 'file_1'},
          ],
        },
      ]);
    });

    test(
        'providerOptionsName: azure + imageDetail resolves under the '
        '"azure" key', () {
      final bytes = Uint8List.fromList(utf8.encode('fake-png-bytes'));
      final result = convertToOpenAiResponsesInput(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataBytes(bytes),
              mediaType: 'image/png',
              providerOptions: const {
                'azure': {'imageDetail': 'low'},
              },
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        store: true,
        providerOptionsName: 'azure',
      );

      final content =
          (result.input.single['content']! as List<Object?>).cast<Object?>();
      final imagePart = content.single! as Map<String, Object?>;
      expect(imagePart['detail'], 'low');
    });

    test(
        'providerOptionsName: azure + FileDataReference missing the '
        '"azure" key throws NoSuchProviderReferenceError', () {
      expect(
        () => convertToOpenAiResponsesInput(
          prompt: [
            UserMessage([
              FilePart(
                data: FileDataReference({'openai': 'file_1'}),
                mediaType: 'application/pdf',
              ),
            ]),
          ],
          systemMessageMode: SystemMessageMode.system,
          store: true,
          providerOptionsName: 'azure',
        ),
        throwsA(
          isA<NoSuchProviderReferenceError>()
              .having((error) => error.provider, 'provider', 'azure')
              .having(
            (error) => error.reference,
            'reference',
            {'openai': 'file_1'},
          ),
        ),
      );
    });
  });
}
