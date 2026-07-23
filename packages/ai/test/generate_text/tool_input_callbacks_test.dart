import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

void main() {
  // Compatibility fixture (unit): P1-CORE-05
  test(
    'P1-CORE-05 invokes onInputStart before onInputAvailable and execute',
    () async {
      final events = <String>[];
      final model = ScriptedModel(
        turns: const <ScriptedTurn>[
          ScriptedTurn(
            content: <lm.LanguageModelContent>[
              lm.ToolCall(
                toolCallId: 'call-1',
                toolName: 'lookup',
                input: '{"city":"Shanghai"}',
              ),
            ],
            finishReason: lm.LanguageModelFinishReason(
              lm.FinishReasonType.toolCalls,
            ),
            usage: lm.LanguageModelUsage(
              inputTokens: lm.InputTokens(total: 2),
              outputTokens: lm.OutputTokens(total: 1),
            ),
          ),
        ],
      );
      final tool = Tool(
        inputSchema: const lm.JsonSchema(<String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'city': <String, Object?>{'type': 'string'},
          },
          'required': <Object?>['city'],
        }),
        onInputStart: (options) {
          events.add('start:${options.toolCallId}');
          expect(options.messages, hasLength(1));
          expect(options.cancellation?.isCancelled ?? false, isFalse);
        },
        onInputAvailable: (options) {
          events.add(
            'available:${(options.input as Map<String, Object?>)['city']}',
          );
          expect(options.toolCallId, 'call-1');
          expect(options.cancellation?.isCancelled ?? false, isFalse);
        },
        execute: (input, options) {
          events.add('execute:${options.toolCallId}');
          return 'sunny';
        },
      );

      final result = await generateText(
        model: model,
        prompt: 'weather',
        tools: <String, Tool>{'lookup': tool},
      );

      expect(
        events,
        <String>[
          'start:call-1',
          'available:Shanghai',
          'execute:call-1',
        ],
      );
      expect(result.toolResults.single.result, 'sunny');
    },
  );

  test('P1-CORE-05 denied approval emits an explicit denied tool output',
      () async {
    var executed = false;
    final model = ScriptedModel(
      turns: const <ScriptedTurn>[
        ScriptedTurn(
          content: <lm.LanguageModelContent>[
            lm.ToolCall(
              toolCallId: 'call-denied',
              toolName: 'delete',
              input: '{}',
            ),
          ],
          finishReason: lm.LanguageModelFinishReason(
            lm.FinishReasonType.toolCalls,
          ),
          usage: lm.LanguageModelUsage(
            inputTokens: lm.InputTokens(),
            outputTokens: lm.OutputTokens(),
          ),
        ),
      ],
    );

    final result = await generateText(
      model: model,
      prompt: 'delete',
      tools: <String, Tool>{
        'delete': Tool(
          inputSchema: const lm.JsonSchema(<String, Object?>{
            'type': 'object',
          }),
          execute: (input, options) {
            executed = true;
            return 'deleted';
          },
        ),
      },
      toolApproval: const <String, Object?>{
        'delete': ToolApprovalStatus.denied(reason: 'policy'),
      },
    );

    expect(executed, isFalse);
    expect(result.toolResults.single.result, 'policy');
    expect(
      result.finalStep.toolResultOutputs.single,
      const lm.ToolResultExecutionDenied(reason: 'policy'),
    );
  });

  test('P1-CORE-05 stream callbacks follow tool input framing', () async {
    final events = <String>[];
    final result = streamText(
      model: _ToolInputStreamModel(),
      prompt: 'weather',
      tools: <String, Tool>{
        'lookup': Tool(
          inputSchema: const lm.JsonSchema(<String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'city': <String, Object?>{'type': 'string'},
            },
            'required': <Object?>['city'],
          }),
          onInputStart: (options) {
            events.add('start:${options.toolCallId}');
          },
          onInputAvailable: (options) {
            events.add(
              'available:${(options.input as Map<String, Object?>)['city']}',
            );
          },
          execute: (input, options) => 'sunny',
        ),
      },
    );

    final parts = await result.stream.toList();

    expect(events, <String>['start:call-stream', 'available:Shanghai']);
    expect(parts.whereType<ToolInputStartPart>(), hasLength(1));
    expect(parts.whereType<ToolInputDeltaPart>(), hasLength(1));
    expect(parts.whereType<ToolInputEndPart>(), hasLength(1));
    expect(parts.whereType<ToolCallStreamPart>(), hasLength(1));
  });
}

final class _ToolInputStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'tool-input-test';

  @override
  String get modelId => 'tool-input-stream-model';

  @override
  Map<String, List<RegExp>> get supportedUrls => const <String, List<RegExp>>{};

  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) async =>
      throw UnimplementedError();

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async {
    return lm.LanguageModelStreamResult(
      stream: Stream<lm.LanguageModelStreamPart>.fromIterable(
        const <lm.LanguageModelStreamPart>[
          lm.StreamStart(<lm.Warning>[]),
          lm.ToolInputStart(id: 'call-stream', toolName: 'lookup'),
          lm.ToolInputDelta('call-stream', '{"city":"Shanghai"}'),
          lm.ToolInputEnd('call-stream'),
          lm.ToolCall(
            toolCallId: 'call-stream',
            toolName: 'lookup',
            input: '{"city":"Shanghai"}',
          ),
          lm.FinishPart(
            usage: lm.LanguageModelUsage(
              inputTokens: lm.InputTokens(total: 2),
              outputTokens: lm.OutputTokens(total: 1),
            ),
            finishReason: lm.LanguageModelFinishReason(
              lm.FinishReasonType.toolCalls,
            ),
          ),
        ],
      ),
    );
  }
}
