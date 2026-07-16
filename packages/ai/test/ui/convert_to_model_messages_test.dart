import 'package:pigcode_ai/src/prompt/content_part.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai/src/ui/convert_to_model_messages.dart';
import 'package:pigcode_ai/src/ui/ui_message.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('convertToModelMessages', () {
    test('concatenates system text and skips data parts', () {
      final result = convertToModelMessages([
        UiMessage(
          id: 'sys_1',
          role: UiMessageRole.system,
          parts: const [
            TextUiPart('You '),
            DataUiPart(type: 'data-private', data: {'hidden': true}),
            TextUiPart('are helpful.'),
          ],
        ),
      ]);

      expect(result, const [
        SystemModelMessage('You are helpful.'),
      ]);
    });

    test('converts user text, files, and opted-in data parts', () {
      final result = convertToModelMessages(
        [
          UiMessage(
            id: 'user_1',
            role: UiMessageRole.user,
            parts: [
              const TextUiPart('show '),
              FileUiPart(
                url: Uri.parse('https://example.com/a.png'),
                mediaType: 'image/png',
                filename: 'a.png',
                providerMetadata: const {
                  'openai': {'file': 'meta'},
                },
              ),
              const TextUiPart(
                'with metadata',
                providerMetadata: {
                  'openai': {'text': 'meta'},
                },
              ),
              FileUiPart(
                url: Uri.parse('https://example.com/ignored.txt'),
                mediaType: 'text/plain',
                providerReference: const {'openai': 'file_1'},
              ),
              const DataUiPart(
                type: 'data-weather',
                id: 'weather_1',
                data: {'temp': 72},
              ),
            ],
          ),
        ],
        convertDataPart: (part) => TextPart('converted ${part.id}'),
      );

      expect(result, [
        UserModelMessage(<UserContentPart>[
          const TextPart('show '),
          FilePart(
            data: DataUrl(Uri.parse('https://example.com/a.png')),
            mediaType: 'image/png',
            filename: 'a.png',
            providerOptions: const {
              'openai': {'file': 'meta'},
            },
          ),
          const TextPart(
            'with metadata',
            providerOptions: {
              'openai': {'text': 'meta'},
            },
          ),
          const FilePart(
            data: DataProviderRef({'openai': 'file_1'}),
            mediaType: 'text/plain',
          ),
          const TextPart('converted weather_1'),
        ]),
      ]);
    });

    test('skips user messages with no model-visible parts', () {
      final result = convertToModelMessages([
        UiMessage(
          id: 'user_private',
          role: UiMessageRole.user,
          parts: const [
            DataUiPart(type: 'data-private', data: {'hidden': true}),
          ],
        ),
      ]);

      expect(result, isEmpty);
    });

    test('converts assistant content and provider-executed tool result inline',
        () {
      final result = convertToModelMessages([
        UiMessage(
          id: 'assistant_1',
          role: UiMessageRole.assistant,
          parts: [
            const TextUiPart('answer'),
            const ReasoningUiPart('thinking'),
            const CustomUiPart(
              'openai.foo',
              providerMetadata: {
                'openai': {'custom': 'meta'},
              },
            ),
            const ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              state: UiToolState.outputAvailable,
              input: {'city': 'SF'},
              output: {'weather': 'sunny'},
              providerExecuted: true,
              callProviderMetadata: {
                'openai': {'call': 'meta'},
              },
              resultProviderMetadata: {
                'openai': {'result': 'meta'},
              },
            ),
          ],
        ),
      ]);

      expect(result, const [
        AssistantModelMessage(<AssistantContentPart>[
          TextPart('answer'),
          ReasoningPart('thinking'),
          CustomPart(
            'openai.foo',
            providerOptions: {
              'openai': {'custom': 'meta'},
            },
          ),
          ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: {'city': 'SF'},
            providerExecuted: true,
            providerOptions: {
              'openai': {'call': 'meta'},
            },
          ),
          ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            output: provider.ToolResultJson({'weather': 'sunny'}),
            providerOptions: {
              'openai': {'result': 'meta'},
            },
          ),
        ]),
      ]);
    });

    test('converts provider-executed tool error inline', () {
      final result = convertToModelMessages([
        UiMessage(
          id: 'assistant_1',
          role: UiMessageRole.assistant,
          parts: const [
            ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              state: UiToolState.outputError,
              input: {'city': 'SF'},
              errorText: 'provider failed',
              providerExecuted: true,
              resultProviderMetadata: {
                'openai': {'result': 'meta'},
              },
            ),
          ],
        ),
      ]);

      expect(result, const [
        AssistantModelMessage(<AssistantContentPart>[
          ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: {'city': 'SF'},
            providerExecuted: true,
          ),
          ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            output: provider.ToolResultErrorText('provider failed'),
            providerOptions: {
              'openai': {'result': 'meta'},
            },
          ),
        ]),
      ]);
    });

    test('converts local tool output to assistant call and tool result', () {
      final tool = const ToolUiPart(
        toolCallId: 'call_1',
        toolName: 'lookup',
        state: UiToolState.outputAvailable,
        input: {'city': 'SF'},
        output: {'weather': 'sunny'},
        callProviderMetadata: {
          'openai': {'call': 'meta'},
        },
        resultProviderMetadata: {
          'openai': {'result': 'meta'},
        },
      );

      final result = convertToModelMessages([
        UiMessage(
          id: 'assistant_1',
          role: UiMessageRole.assistant,
          parts: [tool, tool],
        ),
      ]);

      expect(result, const [
        AssistantModelMessage(<AssistantContentPart>[
          ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: {'city': 'SF'},
            providerOptions: {
              'openai': {'call': 'meta'},
            },
          ),
          ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: {'city': 'SF'},
            providerOptions: {
              'openai': {'call': 'meta'},
            },
          ),
        ]),
        ToolModelMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            output: provider.ToolResultJson({'weather': 'sunny'}),
            providerOptions: {
              'openai': {'result': 'meta'},
            },
          ),
        ]),
      ]);
    });

    test('converts string tool output to text result', () {
      final result = convertToModelMessages([
        UiMessage(
          id: 'assistant_1',
          role: UiMessageRole.assistant,
          parts: const [
            ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'delete_file',
              state: UiToolState.outputAvailable,
              input: {'path': '/tmp/a.txt'},
              output: 'deleted',
            ),
          ],
        ),
      ]);

      expect(result, const [
        AssistantModelMessage(<AssistantContentPart>[
          ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'delete_file',
            input: {'path': '/tmp/a.txt'},
          ),
        ]),
        ToolModelMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'delete_file',
            output: provider.ToolResultText('deleted'),
          ),
        ]),
      ]);
    });

    test('converts approval response and denied result', () {
      final result = convertToModelMessages([
        UiMessage(
          id: 'assistant_1',
          role: UiMessageRole.assistant,
          parts: const [
            ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'delete_file',
              state: UiToolState.approvalResponded,
              input: {'path': '/tmp/a.txt'},
              callProviderMetadata: {
                'openai': {'call': 'meta'},
              },
              resultProviderMetadata: {
                'openai': {'result': 'meta'},
              },
              approval: UiToolApproval(
                approvalId: 'ap_1',
                approved: false,
                reason: 'not allowed',
              ),
            ),
          ],
        ),
      ]);

      expect(result, const [
        AssistantModelMessage(<AssistantContentPart>[
          ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'delete_file',
            input: {'path': '/tmp/a.txt'},
            providerOptions: {
              'openai': {'call': 'meta'},
            },
          ),
          ToolApprovalRequestPart(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
            providerOptions: {
              'openai': {'call': 'meta'},
            },
          ),
        ]),
        ToolModelMessage(<ToolContentPart>[
          ToolApprovalResponsePart(
            approvalId: 'ap_1',
            approved: false,
            reason: 'not allowed',
            providerOptions: {
              'openai': {'result': 'meta'},
            },
          ),
          ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'delete_file',
            output: provider.ToolResultExecutionDenied(reason: 'not allowed'),
            providerOptions: {
              'openai': {'result': 'meta'},
            },
          ),
        ]),
      ]);
    });

    test('converts outputDenied to error text with call metadata', () {
      final result = convertToModelMessages([
        UiMessage(
          id: 'assistant_1',
          role: UiMessageRole.assistant,
          parts: const [
            ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'delete_file',
              state: UiToolState.outputDenied,
              input: {'path': '/tmp/a.txt'},
              callProviderMetadata: {
                'openai': {'call': 'meta'},
              },
              resultProviderMetadata: {
                'openai': {'result': 'meta'},
              },
              approval: UiToolApproval(
                approvalId: 'ap_1',
                reason: 'blocked',
              ),
            ),
          ],
        ),
      ]);

      expect(result, const [
        AssistantModelMessage(<AssistantContentPart>[
          ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'delete_file',
            input: {'path': '/tmp/a.txt'},
            providerOptions: {
              'openai': {'call': 'meta'},
            },
          ),
          ToolApprovalRequestPart(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
            providerOptions: {
              'openai': {'call': 'meta'},
            },
          ),
        ]),
        ToolModelMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'delete_file',
            output: provider.ToolResultErrorText('blocked'),
            providerOptions: {
              'openai': {'result': 'meta'},
            },
          ),
        ]),
      ]);
    });

    test('converts provider-executed outputDenied inline', () {
      final result = convertToModelMessages([
        UiMessage(
          id: 'assistant_1',
          role: UiMessageRole.assistant,
          parts: const [
            ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'delete_file',
              state: UiToolState.outputDenied,
              input: {'path': '/tmp/a.txt'},
              providerExecuted: true,
              resultProviderMetadata: {
                'openai': {'result': 'meta'},
              },
            ),
          ],
        ),
      ]);

      expect(result, const [
        AssistantModelMessage(<AssistantContentPart>[
          ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'delete_file',
            input: {'path': '/tmp/a.txt'},
            providerExecuted: true,
          ),
          ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'delete_file',
            output: provider.ToolResultErrorText(
              'Tool call execution denied.',
            ),
            providerOptions: {
              'openai': {'result': 'meta'},
            },
          ),
        ]),
      ]);
    });

    test('throws on incomplete tool input unless ignored', () {
      final messages = [
        UiMessage(
          id: 'assistant_1',
          role: UiMessageRole.assistant,
          parts: const [
            TextUiPart('before'),
            ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              state: UiToolState.inputStreaming,
              input: {'partial': true},
            ),
            ToolUiPart(
              toolCallId: 'call_2',
              toolName: 'lookup',
              state: UiToolState.inputAvailable,
              input: {'city': 'SF'},
            ),
          ],
        ),
      ];

      expect(
        () => convertToModelMessages(messages),
        throwsA(isA<provider.InvalidArgumentError>().having(
          (error) => error.argument,
          'argument',
          'messages',
        )),
      );
      expect(
        convertToModelMessages(messages, ignoreIncompleteToolCalls: true),
        const [
          AssistantModelMessage(<AssistantContentPart>[
            TextPart('before'),
          ]),
        ],
      );
    });

    test('does not drop repeated tool result ids across steps', () {
      final result = convertToModelMessages([
        UiMessage(
          id: 'assistant_1',
          role: UiMessageRole.assistant,
          parts: const [
            ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              state: UiToolState.outputAvailable,
              input: {'city': 'SF'},
              output: {'weather': 'sunny'},
            ),
            StepStartUiPart(),
            ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              state: UiToolState.outputAvailable,
              input: {'city': 'NYC'},
              output: {'weather': 'rainy'},
            ),
          ],
        ),
      ]);

      expect(result, const [
        AssistantModelMessage(<AssistantContentPart>[
          ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: {'city': 'SF'},
          ),
        ]),
        ToolModelMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            output: provider.ToolResultJson({'weather': 'sunny'}),
          ),
        ]),
        AssistantModelMessage(<AssistantContentPart>[
          ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: {'city': 'NYC'},
          ),
        ]),
        ToolModelMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            output: provider.ToolResultJson({'weather': 'rainy'}),
          ),
        ]),
      ]);
    });

    test('splits assistant and tool blocks at step starts', () {
      final result = convertToModelMessages([
        UiMessage(
          id: 'assistant_1',
          role: UiMessageRole.assistant,
          parts: const [
            TextUiPart('step 1'),
            ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              state: UiToolState.outputAvailable,
              input: {'city': 'SF'},
              output: {'weather': 'sunny'},
            ),
            StepStartUiPart(),
            TextUiPart('step 2'),
            ToolUiPart(
              toolCallId: 'call_2',
              toolName: 'lookup',
              state: UiToolState.outputAvailable,
              input: {'city': 'NYC'},
              output: {'weather': 'rainy'},
            ),
          ],
        ),
      ]);

      expect(result, const [
        AssistantModelMessage(<AssistantContentPart>[
          TextPart('step 1'),
          ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: {'city': 'SF'},
          ),
        ]),
        ToolModelMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'lookup',
            output: provider.ToolResultJson({'weather': 'sunny'}),
          ),
        ]),
        AssistantModelMessage(<AssistantContentPart>[
          TextPart('step 2'),
          ToolCallPart(
            toolCallId: 'call_2',
            toolName: 'lookup',
            input: {'city': 'NYC'},
          ),
        ]),
        ToolModelMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'call_2',
            toolName: 'lookup',
            output: provider.ToolResultJson({'weather': 'rainy'}),
          ),
        ]),
      ]);
    });
  });
}
