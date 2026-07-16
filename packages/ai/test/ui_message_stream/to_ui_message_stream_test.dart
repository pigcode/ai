import 'package:pigcode_ai/src/generate_text/text_stream_part.dart';
import 'package:pigcode_ai/src/ui_message_stream/to_ui_message_chunk.dart';
import 'package:pigcode_ai/src/ui_message_stream/to_ui_message_stream.dart';
import 'package:pigcode_ai/src/ui_message_stream/ui_message_chunk.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('toUiMessageChunk', () {
    test('maps lifecycle, text, reasoning, error, and raw parts', () {
      expect(
        toUiMessageChunk(
          const StartPart(),
          responseMessageId: 'm1',
          messageMetadata: const {
            'run': {'id': 'r1'},
          },
        ),
        StartUiMessageChunk(
          messageId: 'm1',
          messageMetadata: const {
            'run': {'id': 'r1'},
          },
        ),
      );
      expect(
        toUiMessageChunk(
          FinishPart(finishReason: _finishReason, totalUsage: _usage),
          messageMetadata: const {
            'done': {'ok': true},
          },
        ),
        FinishUiMessageChunk(
          finishReason: _finishReason,
          messageMetadata: const {
            'done': {'ok': true},
          },
        ),
      );
      expect(
        toUiMessageChunk(const AbortPart(reason: 'cancelled')),
        AbortUiMessageChunk(reason: 'cancelled'),
      );
      expect(
        toUiMessageChunk(StartStepPart(warnings: const [])),
        const StartStepUiMessageChunk(),
      );
      expect(
        toUiMessageChunk(FinishStepPart(
          usage: _usage,
          finishReason: _finishReason,
        )),
        const FinishStepUiMessageChunk(),
      );
      expect(
        toUiMessageChunk(const TextStartPart(
          'txt_1',
          providerMetadata: {
            'openai': {'id': 'txt_1'},
          },
        )),
        TextStartUiMessageChunk(
          'txt_1',
          providerMetadata: const {
            'openai': {'id': 'txt_1'},
          },
        ),
      );
      expect(
        toUiMessageChunk(const TextDeltaPart(
          'txt_1',
          'hi',
          providerMetadata: {
            'openai': {'delta': 'meta'},
          },
        )),
        TextDeltaUiMessageChunk(
          'txt_1',
          'hi',
          providerMetadata: const {
            'openai': {'delta': 'meta'},
          },
        ),
      );
      expect(
        toUiMessageChunk(const TextEndPart(
          'txt_1',
          providerMetadata: {
            'openai': {'end': 'meta'},
          },
        )),
        TextEndUiMessageChunk(
          'txt_1',
          providerMetadata: const {
            'openai': {'end': 'meta'},
          },
        ),
      );
      expect(
        toUiMessageChunk(const ReasoningStartPart('rsn_1')),
        ReasoningStartUiMessageChunk('rsn_1'),
      );
      expect(
        toUiMessageChunk(const ReasoningDeltaPart('rsn_1', 'thinking')),
        ReasoningDeltaUiMessageChunk('rsn_1', 'thinking'),
      );
      expect(
        toUiMessageChunk(const ReasoningEndPart('rsn_1')),
        ReasoningEndUiMessageChunk('rsn_1'),
      );
      expect(
        toUiMessageChunk(
          const ReasoningDeltaPart('rsn_1', 'thinking'),
          sendReasoning: false,
        ),
        isNull,
      );
      expect(
        toUiMessageChunk(const StartPart(), sendStart: false),
        isNull,
      );
      expect(
        toUiMessageChunk(
          FinishPart(finishReason: _finishReason, totalUsage: _usage),
          sendFinish: false,
        ),
        isNull,
      );
      expect(
        toUiMessageChunk(ErrorPart(StateError('secret-token'))),
        ErrorUiMessageChunk('An error occurred.'),
      );
      expect(
        toUiMessageChunk(
          ErrorPart(StateError('secret-token')),
          onError: (error) => 'visible:$error',
        ),
        isA<ErrorUiMessageChunk>().having(
            (chunk) => chunk.errorText, 'errorText', contains('secret')),
      );
      expect(toUiMessageChunk(const RawStreamPart({'x': 1})), isNull);
    });

    test('maps tool input start, delta, end, and calls', () {
      expect(
        toUiMessageChunk(const ToolInputStartPart('call_1', 'lookup')),
        ToolInputStartUiMessageChunk(
          toolCallId: 'call_1',
          toolName: 'lookup',
        ),
      );
      expect(
        toUiMessageChunk(const ToolInputDeltaPart('call_1', '{"city"')),
        const ToolInputDeltaUiMessageChunk('call_1', '{"city"'),
      );
      expect(toUiMessageChunk(const ToolInputEndPart('call_1')), isNull);
      expect(
        toUiMessageChunk(const ToolCallStreamPart(provider.ToolCall(
          toolCallId: 'call_1',
          toolName: 'lookup',
          input: '{"city":"SF","count":2}',
          providerExecuted: true,
          providerMetadata: {
            'openai': {'id': 'call_1'},
          },
        ))),
        ToolInputAvailableUiMessageChunk(
          toolCallId: 'call_1',
          toolName: 'lookup',
          input: const {'city': 'SF', 'count': 2},
          providerExecuted: true,
          providerMetadata: const {
            'openai': {'id': 'call_1'},
          },
        ),
      );
      expect(
        toUiMessageChunk(const ToolCallStreamPart(provider.ToolCall(
          toolCallId: 'call_2',
          toolName: 'lookup',
          input: '{"city":',
        ))),
        ToolInputAvailableUiMessageChunk(
          toolCallId: 'call_2',
          toolName: 'lookup',
          input: '{"city":',
        ),
      );
    });

    test('maps tool approval and result parts', () {
      expect(
        toUiMessageChunk(const ToolApprovalRequestStreamPart(
          provider.ToolApprovalRequest(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
            providerMetadata: {
              'openai': {'request': 'meta'},
            },
          ),
        )),
        ToolApprovalRequestUiMessageChunk(
          approvalId: 'ap_1',
          toolCallId: 'call_1',
          providerMetadata: const {
            'openai': {'request': 'meta'},
          },
        ),
      );
      expect(
        toUiMessageChunk(const ToolApprovalResponseStreamPart(
          provider.ToolApprovalResponsePart(
            approvalId: 'ap_1',
            approved: true,
            reason: 'ok',
            providerOptions: {
              'openai': {'approval': 'meta'},
            },
          ),
        )),
        ToolApprovalResponseUiMessageChunk(
          approvalId: 'ap_1',
          approved: true,
          reason: 'ok',
          providerMetadata: const {
            'openai': {'approval': 'meta'},
          },
        ),
      );
      expect(
        toUiMessageChunk(const ToolResultStreamPart(provider.ToolResult(
          toolCallId: 'call_1',
          toolName: 'lookup',
          result: {'weather': 'sunny'},
          preliminary: true,
          providerMetadata: {
            'openai': {'id': 'result_1'},
          },
        ))),
        ToolOutputAvailableUiMessageChunk(
          toolCallId: 'call_1',
          output: const {'weather': 'sunny'},
          preliminary: true,
          providerMetadata: const {
            'openai': {'id': 'result_1'},
          },
        ),
      );
      expect(
        toUiMessageChunk(const ToolResultStreamPart(provider.ToolResult(
          toolCallId: 'call_1',
          toolName: 'lookup',
          result: 'bad',
          isError: true,
        ))),
        ToolOutputErrorUiMessageChunk(
          toolCallId: 'call_1',
          errorText: 'bad',
        ),
      );
      expect(
        toUiMessageChunk(const ToolResultStreamPart(provider.ToolResult(
          toolCallId: 'call_2',
          toolName: 'lookup',
          result: {'code': 'bad'},
          isError: true,
          providerMetadata: {
            'openai': {'id': 'error_1'},
          },
        ))),
        ToolOutputErrorUiMessageChunk(
          toolCallId: 'call_2',
          errorText: '{"code":"bad"}',
          providerMetadata: const {
            'openai': {'id': 'error_1'},
          },
        ),
      );
    });
  });

  group('toUiMessageStream', () {
    test('maps streams with inline and extra metadata chunks', () async {
      final chunks = await toUiMessageStream(
        Stream<TextStreamPart>.fromIterable([
          const StartPart(),
          const TextDeltaPart('txt_1', 'hi'),
          FinishPart(finishReason: _finishReason, totalUsage: _usage),
        ]),
        responseMessageId: 'm1',
        messageMetadata: (part) => switch (part) {
          StartPart() => const {
              'start': {'ok': true},
            },
          FinishPart() => const {
              'finish': {'ok': true},
            },
          _ => const {
              'part': {'ok': true},
            },
        },
      ).toList();

      expect(chunks, [
        StartUiMessageChunk(
          messageId: 'm1',
          messageMetadata: const {
            'start': {'ok': true},
          },
        ),
        TextDeltaUiMessageChunk('txt_1', 'hi'),
        MessageMetadataUiMessageChunk(const {
          'part': {'ok': true},
        }),
        FinishUiMessageChunk(
          finishReason: _finishReason,
          messageMetadata: const {
            'finish': {'ok': true},
          },
        ),
      ]);
    });

    test('emits metadata for filtered non-lifecycle parts only', () async {
      final chunks = await toUiMessageStream(
        Stream<TextStreamPart>.fromIterable([
          const StartPart(),
          const ReasoningDeltaPart('rsn_1', 'thinking'),
          const RawStreamPart({'raw': true}),
          FinishPart(finishReason: _finishReason, totalUsage: _usage),
        ]),
        sendStart: false,
        sendReasoning: false,
        sendFinish: false,
        messageMetadata: (part) => switch (part) {
          StartPart() => const {
              'filtered': {'name': 'start'},
            },
          ReasoningDeltaPart() => const {
              'filtered': {'name': 'reasoning'},
            },
          RawStreamPart() => const {
              'filtered': {'name': 'raw'},
            },
          FinishPart() => const {
              'filtered': {'name': 'finish'},
            },
          _ => null,
        },
      ).toList();

      expect(chunks, [
        MessageMetadataUiMessageChunk(const {
          'filtered': {'name': 'reasoning'},
        }),
        MessageMetadataUiMessageChunk(const {
          'filtered': {'name': 'raw'},
        }),
      ]);
    });

    test('inlines metadata on terminal errors', () async {
      final chunks = await toUiMessageStream(
        Stream<TextStreamPart>.fromIterable([
          const TextDeltaPart('txt_1', 'hi'),
          const ErrorPart('boom'),
        ]),
        messageMetadata: (part) => switch (part) {
          TextDeltaPart() => const {
              'part': {'name': 'text'},
            },
          ErrorPart() => const {
              'part': {'name': 'error'},
            },
          _ => null,
        },
      ).toList();

      expect(chunks, [
        TextDeltaUiMessageChunk('txt_1', 'hi'),
        MessageMetadataUiMessageChunk(const {
          'part': {'name': 'text'},
        }),
        ErrorUiMessageChunk(
          'An error occurred.',
          messageMetadata: const {
            'part': {'name': 'error'},
          },
        ),
      ]);
    });

    test('inlines metadata on aborts', () async {
      final chunks = await toUiMessageStream(
        Stream<TextStreamPart>.fromIterable([
          const AbortPart(reason: 'cancelled'),
        ]),
        messageMetadata: (part) => switch (part) {
          AbortPart() => const {
              'part': {'name': 'abort'},
            },
          _ => null,
        },
      ).toList();

      expect(chunks, [
        AbortUiMessageChunk(
          reason: 'cancelled',
          messageMetadata: const {
            'part': {'name': 'abort'},
          },
        ),
      ]);
    });
  });
}

const _finishReason = provider.LanguageModelFinishReason(
  provider.FinishReasonType.stop,
);

const _usage = provider.LanguageModelUsage(
  inputTokens: provider.InputTokens(),
  outputTokens: provider.OutputTokens(),
);
