import 'package:pigcode_ai/src/ui_message_stream/ui_message_chunk.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('UiMessageChunk JSON', () {
    test('round-trips every supported chunk type', () {
      final chunks = <UiMessageChunk>[
        StartUiMessageChunk(
          messageId: 'm1',
          messageMetadata: {
            'thread': {'id': 't1'},
          },
        ),
        FinishUiMessageChunk(
          finishReason: const provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          messageMetadata: {
            'done': {'ok': true},
          },
        ),
        AbortUiMessageChunk(
          reason: 'cancelled',
          messageMetadata: {
            'abort': {'ok': true},
          },
        ),
        ErrorUiMessageChunk(
          'An error occurred.',
          messageMetadata: {
            'error': {'ok': true},
          },
        ),
        MessageMetadataUiMessageChunk({
          'run': {'id': 'r1'},
        }),
        const StartStepUiMessageChunk(),
        const FinishStepUiMessageChunk(),
        TextStartUiMessageChunk(
          'txt_1',
          providerMetadata: {
            'openai': {'id': 'txt_1'},
          },
        ),
        TextDeltaUiMessageChunk(
          'txt_1',
          'hello',
          providerMetadata: {
            'openai': {'delta': 'meta'},
          },
        ),
        TextEndUiMessageChunk(
          'txt_1',
          providerMetadata: {
            'openai': {'end': 'meta'},
          },
        ),
        ReasoningStartUiMessageChunk(
          'rsn_1',
          providerMetadata: {
            'openai': {'id': 'rsn_1'},
          },
        ),
        ReasoningDeltaUiMessageChunk(
          'rsn_1',
          'think',
          providerMetadata: {
            'openai': {'delta': 'meta'},
          },
        ),
        ReasoningEndUiMessageChunk(
          'rsn_1',
          providerMetadata: {
            'openai': {'end': 'meta'},
          },
        ),
        ToolInputStartUiMessageChunk(
          toolCallId: 'call_1',
          toolName: 'lookup',
          providerExecuted: true,
          providerMetadata: {
            'openai': {'id': 'call_1'},
          },
        ),
        const ToolInputDeltaUiMessageChunk('call_1', '{"q"'),
        ToolInputAvailableUiMessageChunk(
          toolCallId: 'call_1',
          toolName: 'lookup',
          input: {'q': 'dart'},
          providerExecuted: false,
          providerMetadata: {
            'openai': {'input': 'meta'},
          },
        ),
        ToolApprovalRequestUiMessageChunk(
          approvalId: 'ap_1',
          toolCallId: 'call_1',
          providerMetadata: {
            'openai': {'request': 'meta'},
          },
        ),
        ToolApprovalResponseUiMessageChunk(
          approvalId: 'ap_1',
          approved: true,
          reason: 'ok',
          providerExecuted: false,
          providerMetadata: {
            'openai': {'approval': 'meta'},
          },
        ),
        ToolOutputAvailableUiMessageChunk(
          toolCallId: 'call_1',
          output: {'answer': 'ok'},
          providerExecuted: true,
          preliminary: true,
          providerMetadata: {
            'openai': {'output': 'meta'},
          },
        ),
        ToolOutputErrorUiMessageChunk(
          toolCallId: 'call_2',
          errorText: 'failed',
          providerExecuted: false,
          providerMetadata: {
            'openai': {'error': 'meta'},
          },
        ),
      ];

      for (final chunk in chunks) {
        expect(UiMessageChunk.fromJson(chunk.toJson()), equals(chunk));
      }
    });

    test('omits nullable fields from JSON', () {
      expect(
        StartUiMessageChunk().toJson(),
        const {'type': 'start'},
      );
      expect(
        FinishUiMessageChunk().toJson(),
        const {'type': 'finish'},
      );
      expect(
        ToolApprovalResponseUiMessageChunk(
          approvalId: 'ap_1',
          approved: true,
        ).toJson(),
        const {
          'type': 'tool-approval-response',
          'approvalId': 'ap_1',
          'approved': true,
        },
      );
    });

    test('normalizes raw finish reasons before serialization', () {
      final chunk = FinishUiMessageChunk(
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
          raw: 'provider_raw',
        ),
      );

      expect(
        chunk.finishReason,
        const provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop),
      );
      expect(UiMessageChunk.fromJson(chunk.toJson()), equals(chunk));
    });

    test('rejects unknown chunk types', () {
      expectInvalid(
        () => UiMessageChunk.fromJson(const {'type': 'unknown'}),
        'type',
      );
    });

    test('rejects malformed required and optional fields', () {
      expectInvalid(
        () => UiMessageChunk.fromJson(const {
          'type': 'text-delta',
          'id': 1,
          'delta': 'hello',
        }),
        'id',
      );
      expectInvalid(
        () => UiMessageChunk.fromJson(const {
          'type': 'tool-approval-response',
          'approvalId': 'ap_1',
          'approved': 'true',
        }),
        'approved',
      );
      expectInvalid(
        () => UiMessageChunk.fromJson(const {
          'type': 'message-metadata',
          'messageMetadata': 'bad',
        }),
        'messageMetadata',
      );
      expectInvalid(
        () => UiMessageChunk.fromJson(const {
          'type': 'tool-input-start',
          'toolCallId': 'call_1',
          'toolName': 'lookup',
          'providerMetadata': {
            'openai': 'bad',
          },
        }),
        'providerMetadata',
      );
      expectInvalid(
        () => UiMessageChunk.fromJson(const {
          'type': 'finish',
          'finishReason': 'invalid',
        }),
        'finishReason',
      );
    });

    test('rejects malformed nested JSON payloads', () {
      expectInvalid(
        () => UiMessageChunk.fromJson({
          'type': 'tool-input-available',
          'toolCallId': 'call_1',
          'toolName': 'lookup',
          'input': DateTime(2026),
        }),
        'input',
      );
      expectInvalid(
        () => UiMessageChunk.fromJson({
          'type': 'tool-output-available',
          'toolCallId': 'call_1',
          'output': {
            'items': [() => 'bad'],
          },
        }),
        'output',
      );
      expectInvalid(
        () => UiMessageChunk.fromJson({
          'type': 'start',
          'messageMetadata': {
            'outer': {1: 'bad'},
          },
        }),
        'messageMetadata',
      );
      expectInvalid(
        () => UiMessageChunk.fromJson({
          'type': 'text-start',
          'id': 'txt_1',
          'providerMetadata': {
            'openai': {'createdAt': DateTime(2026)},
          },
        }),
        'providerMetadata',
      );
    });

    test('snapshots JSON payloads on construction', () {
      final messageItems = <Object?>['initial'];
      final messageMetadata = <String, Object?>{'items': messageItems};
      final start = StartUiMessageChunk(messageMetadata: messageMetadata);
      messageItems.add('mutated');
      messageMetadata['extra'] = true;

      expect(start.messageMetadata, const {
        'items': ['initial'],
      });
      expect(start.toJson()['messageMetadata'], const {
        'items': ['initial'],
      });
      expect(
          () => start.messageMetadata!['extra'] = true, throwsUnsupportedError);
      expect(
        () => (start.messageMetadata!['items']! as List<Object?>).add('local'),
        throwsUnsupportedError,
      );

      final providerIds = <Object?>['txt_1'];
      final openaiMetadata = <String, Object?>{'ids': providerIds};
      final providerMetadata = <String, provider.JsonObject>{
        'openai': openaiMetadata,
      };
      final text = TextStartUiMessageChunk(
        'txt_1',
        providerMetadata: providerMetadata,
      );
      providerIds.add('mutated');
      providerMetadata['anthropic'] = const {'id': 'ignored'};

      expect(text.providerMetadata, const {
        'openai': {
          'ids': ['txt_1'],
        },
      });
      expect(
        () => text.providerMetadata!['anthropic'] = const {'id': 'local'},
        throwsUnsupportedError,
      );
      expect(
        () => (text.providerMetadata!['openai']!['ids']! as List<Object?>)
            .add('local'),
        throwsUnsupportedError,
      );

      final inputItems = <Object?>['q'];
      final input = <String, Object?>{'items': inputItems};
      final inputChunk = ToolInputAvailableUiMessageChunk(
        toolCallId: 'call_1',
        toolName: 'lookup',
        input: input,
      );
      inputItems.add('mutated');
      input['extra'] = true;

      expect(inputChunk.input, const {
        'items': ['q'],
      });
      expect(
        () => ((inputChunk.input! as provider.JsonObject)['items']!
                as List<Object?>)
            .add('local'),
        throwsUnsupportedError,
      );

      final outputItems = <Object?>['ok'];
      final output = <String, Object?>{'items': outputItems};
      final outputChunk = ToolOutputAvailableUiMessageChunk(
        toolCallId: 'call_1',
        output: output,
      );
      outputItems.add('mutated');
      output['extra'] = true;

      expect(outputChunk.output, const {
        'items': ['ok'],
      });
      expect(
        () => ((outputChunk.output! as provider.JsonObject)['items']!
                as List<Object?>)
            .add('local'),
        throwsUnsupportedError,
      );
    });

    test('maps finish reason JSON strings', () {
      const cases = <String, provider.FinishReasonType>{
        'stop': provider.FinishReasonType.stop,
        'length': provider.FinishReasonType.length,
        'content-filter': provider.FinishReasonType.contentFilter,
        'tool-calls': provider.FinishReasonType.toolCalls,
        'error': provider.FinishReasonType.error,
        'other': provider.FinishReasonType.other,
      };

      for (final entry in cases.entries) {
        final reason = provider.LanguageModelFinishReason(entry.value);
        final chunk = FinishUiMessageChunk(finishReason: reason);

        expect(chunk.toJson()['finishReason'], entry.key);
        expect(
          (UiMessageChunk.fromJson({
            'type': 'finish',
            'finishReason': entry.key,
          }) as FinishUiMessageChunk)
              .finishReason,
          reason,
        );
      }
    });
  });
}

void expectInvalid(void Function() callback, String argument) {
  expect(
    callback,
    throwsA(isA<provider.InvalidArgumentError>().having(
      (error) => error.argument,
      'argument',
      argument,
    )),
  );
}
