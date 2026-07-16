import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:test/test.dart';

void main() {
  group('pruneMessages', () {
    test('removes reasoning from assistant messages before the last message',
        () {
      final messages = <ModelMessage>[
        UserModelMessage.text('Weather in Tokyo?'),
        const AssistantModelMessage([
          ReasoningPart('I need to check the weather.'),
          TextPart('Let me check.'),
        ]),
        const AssistantModelMessage([
          ReasoningPart('I have the result.'),
          TextPart('It is sunny.'),
        ]),
      ];

      final result = pruneMessages(
        messages: messages,
        reasoning: PruneReasoning.beforeLastMessage,
      );

      expect(result, [
        UserModelMessage.text('Weather in Tokyo?'),
        const AssistantModelMessage([
          TextPart('Let me check.'),
        ]),
        const AssistantModelMessage([
          ReasoningPart('I have the result.'),
          TextPart('It is sunny.'),
        ]),
      ]);
      expect(
        (messages[1] as AssistantModelMessage)
            .content
            .whereType<ReasoningPart>(),
        hasLength(1),
      );
    });

    test('removes all tool calls, tool results, and approvals', () {
      final result = pruneMessages(
        messages: weatherMessages,
        toolCalls: [ToolCallPruning.all()],
      );

      expect(result, [
        UserModelMessage.text('Weather in Tokyo and Busan?'),
        const AssistantModelMessage([
          ReasoningPart('I need to get the weather in Tokyo and Busan.'),
        ]),
        const AssistantModelMessage([
          ReasoningPart('I have got the weather in Tokyo and Busan.'),
          TextPart(
            'The weather in Tokyo is sunny. '
            'I could not get the weather in Busan.',
          ),
        ]),
      ]);
    });

    test('keeps associated earlier tool calls for kept trailing tool results',
        () {
      final result = pruneMessages(
        messages: weatherMessages,
        toolCalls: [ToolCallPruning.beforeLastMessages(2)],
      );

      expect(result, weatherMessages);
    });

    test('selectively prunes tool approvals with their requested tool', () {
      final result = pruneMessages(
        messages: weatherMessages,
        toolCalls: [
          ToolCallPruning.all(tools: ['get-weather-tool-2']),
        ],
      );

      expect(result, [
        UserModelMessage.text('Weather in Tokyo and Busan?'),
        const AssistantModelMessage([
          ReasoningPart('I need to get the weather in Tokyo and Busan.'),
          ToolCallPart(
            toolCallId: 'call-1',
            toolName: 'get-weather-tool-1',
            input: {'city': 'Tokyo'},
          ),
        ]),
        const ToolModelMessage([
          ToolResultPart(
            toolCallId: 'call-1',
            toolName: 'get-weather-tool-1',
            output: ToolResultText('sunny'),
          ),
        ]),
        const AssistantModelMessage([
          ReasoningPart('I have got the weather in Tokyo and Busan.'),
          TextPart(
            'The weather in Tokyo is sunny. '
            'I could not get the weather in Busan.',
          ),
        ]),
      ]);
      for (final message in result.whereType<ToolModelMessage>()) {
        expect(
          message.content.whereType<ToolApprovalResponsePart>(),
          isEmpty,
        );
      }
    });

    test('applies multiple tool pruning rules in order', () {
      final result = pruneMessages(
        messages: weatherMessages,
        toolCalls: [
          ToolCallPruning.all(tools: ['get-weather-tool-1']),
          ToolCallPruning.beforeLastMessages(
            2,
            tools: ['get-weather-tool-2'],
          ),
        ],
      );

      expect(result, [
        UserModelMessage.text('Weather in Tokyo and Busan?'),
        const AssistantModelMessage([
          ReasoningPart('I need to get the weather in Tokyo and Busan.'),
          ToolCallPart(
            toolCallId: 'call-2',
            toolName: 'get-weather-tool-2',
            input: {'city': 'Busan'},
          ),
          ToolApprovalRequestPart(
            approvalId: 'approval-1',
            toolCallId: 'call-2',
          ),
        ]),
        const ToolModelMessage([
          ToolApprovalResponsePart(
            approvalId: 'approval-1',
            approved: true,
          ),
          ToolResultPart(
            toolCallId: 'call-2',
            toolName: 'get-weather-tool-2',
            output: ToolResultErrorText('Error: Fetching weather data failed'),
          ),
        ]),
        const AssistantModelMessage([
          ReasoningPart('I have got the weather in Tokyo and Busan.'),
          TextPart(
            'The weather in Tokyo is sunny. '
            'I could not get the weather in Busan.',
          ),
        ]),
      ]);
    });

    test('drops unresolved approval responses during selective pruning', () {
      final result = pruneMessages(
        messages: [
          UserModelMessage.text('Weather in Tokyo?'),
          const AssistantModelMessage([
            ToolCallPart(
              toolCallId: 'call-1',
              toolName: 'get-weather-tool-1',
              input: {'city': 'Tokyo'},
            ),
          ]),
          const ToolModelMessage([
            ToolApprovalResponsePart(
              approvalId: 'unknown-approval',
              approved: true,
            ),
            ToolResultPart(
              toolCallId: 'call-1',
              toolName: 'get-weather-tool-1',
              output: ToolResultText('sunny'),
            ),
          ]),
        ],
        toolCalls: [
          ToolCallPruning.all(tools: ['get-weather-tool-2']),
        ],
      );

      expect(result, [
        UserModelMessage.text('Weather in Tokyo?'),
        const AssistantModelMessage([
          ToolCallPart(
            toolCallId: 'call-1',
            toolName: 'get-weather-tool-1',
            input: {'city': 'Tokyo'},
          ),
        ]),
        const ToolModelMessage([
          ToolResultPart(
            toolCallId: 'call-1',
            toolName: 'get-weather-tool-1',
            output: ToolResultText('sunny'),
          ),
        ]),
      ]);
    });

    test('keeps original tool call for kept approval responses', () {
      final result = pruneMessages(
        messages: [
          UserModelMessage.text('Weather in Tokyo?'),
          const AssistantModelMessage([
            ToolCallPart(
              toolCallId: 'call-1',
              toolName: 'get-weather',
              input: {'city': 'Tokyo'},
            ),
            ToolApprovalRequestPart(
              approvalId: 'approval-1',
              toolCallId: 'call-1',
            ),
          ]),
          const ToolModelMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval-1',
              approved: true,
            ),
          ]),
        ],
        toolCalls: [ToolCallPruning.beforeLastMessage()],
      );

      expect(result, [
        UserModelMessage.text('Weather in Tokyo?'),
        const AssistantModelMessage([
          ToolCallPart(
            toolCallId: 'call-1',
            toolName: 'get-weather',
            input: {'city': 'Tokyo'},
          ),
          ToolApprovalRequestPart(
            approvalId: 'approval-1',
            toolCallId: 'call-1',
          ),
        ]),
        const ToolModelMessage([
          ToolApprovalResponsePart(
            approvalId: 'approval-1',
            approved: true,
          ),
        ]),
      ]);
    });

    test('keeps empty messages when requested', () {
      final result = pruneMessages(
        messages: const [
          AssistantModelMessage([
            ToolCallPart(
              toolCallId: 'call-1',
              toolName: 'lookup',
              input: {},
            ),
          ]),
        ],
        toolCalls: [ToolCallPruning.all()],
        emptyMessages: PruneEmptyMessages.keep,
      );

      expect(result, const [AssistantModelMessage([])]);
    });
  });
}

final weatherMessages = <ModelMessage>[
  UserModelMessage.text('Weather in Tokyo and Busan?'),
  const AssistantModelMessage([
    ReasoningPart('I need to get the weather in Tokyo and Busan.'),
    ToolCallPart(
      toolCallId: 'call-1',
      toolName: 'get-weather-tool-1',
      input: {'city': 'Tokyo'},
    ),
    ToolCallPart(
      toolCallId: 'call-2',
      toolName: 'get-weather-tool-2',
      input: {'city': 'Busan'},
    ),
    ToolApprovalRequestPart(
      approvalId: 'approval-1',
      toolCallId: 'call-2',
    ),
  ]),
  const ToolModelMessage([
    ToolApprovalResponsePart(
      approvalId: 'approval-1',
      approved: true,
    ),
    ToolResultPart(
      toolCallId: 'call-1',
      toolName: 'get-weather-tool-1',
      output: ToolResultText('sunny'),
    ),
    ToolResultPart(
      toolCallId: 'call-2',
      toolName: 'get-weather-tool-2',
      output: ToolResultErrorText('Error: Fetching weather data failed'),
    ),
  ]),
  const AssistantModelMessage([
    ReasoningPart('I have got the weather in Tokyo and Busan.'),
    TextPart(
      'The weather in Tokyo is sunny. '
      'I could not get the weather in Busan.',
    ),
  ]),
];
