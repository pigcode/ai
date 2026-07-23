import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

const _usage = lm.LanguageModelUsage(
  inputTokens: lm.InputTokens(total: 1),
  outputTokens: lm.OutputTokens(total: 1),
);

ScriptedModel _model() {
  return ScriptedModel(
    turns: const <ScriptedTurn>[
      ScriptedTurn(
        content: <lm.LanguageModelContent>[
          lm.ToolCall(
            toolCallId: 'reused-id',
            toolName: 'echo',
            input: '{"value":1}',
          ),
        ],
        finishReason: lm.LanguageModelFinishReason(
          lm.FinishReasonType.toolCalls,
        ),
        usage: _usage,
      ),
      ScriptedTurn(
        content: <lm.LanguageModelContent>[
          lm.ToolCall(
            toolCallId: 'reused-id',
            toolName: 'echo',
            input: '{"value":2}',
          ),
        ],
        finishReason: lm.LanguageModelFinishReason(
          lm.FinishReasonType.toolCalls,
        ),
        usage: _usage,
      ),
      ScriptedTurn(
        content: <lm.LanguageModelContent>[lm.TextContent('done')],
        finishReason: lm.LanguageModelFinishReason(lm.FinishReasonType.stop),
        usage: _usage,
      ),
    ],
  );
}

Tool _tool(List<int> executions) {
  return Tool(
    inputSchema: const lm.JsonSchema(<String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'value': <String, Object?>{'type': 'number'},
      },
      'required': <Object?>['value'],
    }),
    execute: (input, options) {
      final value = (input as Map<String, Object?>)['value']! as int;
      executions.add(value);
      return value;
    },
  );
}

void _expectCompleteHistory(ScriptedModel model) {
  final prompt = model.receivedCallOptions.last.prompt;
  final calls = prompt
      .whereType<lm.AssistantMessage>()
      .expand((message) => message.content)
      .whereType<lm.ToolCallPart>()
      .toList();
  final results = prompt
      .whereType<lm.ToolMessage>()
      .expand((message) => message.content)
      .whereType<lm.ToolResultPart>()
      .toList();

  expect(calls.map((call) => call.toolCallId), <String>[
    'reused-id',
    'reused-id',
  ]);
  expect(calls.map((call) => call.input), <Object?>[
    <String, Object?>{'value': 1},
    <String, Object?>{'value': 2},
  ]);
  expect(results.map((result) => result.toolCallId), <String>[
    'reused-id',
    'reused-id',
  ]);
}

void main() {
  // Compatibility fixture (unit): P1-CORE-04
  group('P1-CORE-04 repeated tool-call IDs remain scoped to their step', () {
    test('generateText preserves both calls and results', () async {
      final executions = <int>[];
      final model = _model();

      final result = await generateText(
        model: model,
        prompt: 'repeat',
        tools: <String, Tool>{'echo': _tool(executions)},
        stopWhen: isStepCount(3),
      );

      expect(executions, <int>[1, 2]);
      expect(result.steps.expand((step) => step.toolCalls), hasLength(2));
      expect(result.steps.expand((step) => step.toolResults), hasLength(2));
      _expectCompleteHistory(model);
    });

    test('streamText preserves both calls and results', () async {
      final executions = <int>[];
      final model = _model();
      final result = streamText(
        model: model,
        prompt: 'repeat',
        tools: <String, Tool>{'echo': _tool(executions)},
        stopWhen: isStepCount(3),
      );

      await result.consumeStream();

      expect(executions, <int>[1, 2]);
      expect(await result.toolCalls, hasLength(2));
      expect(await result.toolResults, hasLength(2));
      _expectCompleteHistory(model);
    });
  });
}
