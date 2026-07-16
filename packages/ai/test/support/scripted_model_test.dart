import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import 'scripted_model.dart';

void main() {
  group('ScriptedModel.doGenerate', () {
    test('返回脚本队列中的第一个 turn 并记录调用参数', () async {
      final turn = ScriptedTurn(
        content: const [provider.TextContent('hello')],
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        ),
        usage: const provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(total: 3),
          outputTokens: provider.OutputTokens(total: 1),
        ),
      );
      final model = ScriptedModel(turns: [turn]);
      final options = provider.LanguageModelCallOptions(
        prompt: [
          const provider.UserMessage([provider.TextPart('hi')]),
        ],
      );

      final result = await model.doGenerate(options);

      expect(result.content, turn.content);
      expect(result.finishReason, turn.finishReason);
      expect(result.usage, turn.usage);
      expect(result.warnings, isEmpty);
      expect(model.callCount, 1);
      expect(model.receivedCallOptions, [options]);
    });

    test('doGenerate 按队列顺序推进,第二次调用返回第二个 turn', () async {
      final first = ScriptedTurn(
        content: const [provider.TextContent('one')],
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        ),
        usage: const provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(),
          outputTokens: provider.OutputTokens(),
        ),
      );
      final second = ScriptedTurn(
        content: const [provider.TextContent('two')],
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        ),
        usage: const provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(),
          outputTokens: provider.OutputTokens(),
        ),
      );
      final model = ScriptedModel(turns: [first, second]);
      final options = provider.LanguageModelCallOptions(prompt: const []);

      final firstResult = await model.doGenerate(options);
      final secondResult = await model.doGenerate(options);

      expect(firstResult.content, first.content);
      expect(secondResult.content, second.content);
      expect(model.callCount, 2);
    });

    test('provider/modelId 默认值可被覆盖', () {
      final model = ScriptedModel(turns: const []);
      expect(model.provider, 'scripted');
      expect(model.modelId, 'scripted-model');

      final custom = ScriptedModel(
          turns: const [],
          provider: 'custom-provider',
          modelId: 'custom-model');
      expect(custom.provider, 'custom-provider');
      expect(custom.modelId, 'custom-model');
    });
  });

  group('ScriptedModel.doStream', () {
    test('依次发出 StreamStart/TextStart/TextDelta/TextEnd/FinishPart', () async {
      final turn = ScriptedTurn(
        content: const [provider.TextContent('hi there')],
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        ),
        usage: const provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(total: 2),
          outputTokens: provider.OutputTokens(total: 2),
        ),
      );
      final model = ScriptedModel(turns: [turn]);
      final options = provider.LanguageModelCallOptions(prompt: const []);

      final result = await model.doStream(options);
      final parts = await result.stream.toList();

      expect(parts, hasLength(5));
      expect(parts[0], isA<provider.StreamStart>());
      expect((parts[0] as provider.StreamStart).warnings, isEmpty);

      expect(parts[1], isA<provider.TextStart>());
      final textStart = parts[1] as provider.TextStart;

      expect(parts[2], isA<provider.TextDelta>());
      final textDelta = parts[2] as provider.TextDelta;
      expect(textDelta.id, textStart.id);
      expect(textDelta.delta, 'hi there');

      expect(parts[3], isA<provider.TextEnd>());
      expect((parts[3] as provider.TextEnd).id, textStart.id);

      expect(parts[4], isA<provider.FinishPart>());
      final finish = parts[4] as provider.FinishPart;
      expect(finish.finishReason, turn.finishReason);
      expect(finish.usage, turn.usage);

      expect(model.callCount, 1);
    });

    test('工具调用内容项作为 ToolCall 分块原样发出,finishReason=toolCalls', () async {
      const call = provider.ToolCall(
        toolCallId: 'call_1',
        toolName: 'lookup',
        input: '{"q":"dart"}',
      );
      final turn = ScriptedTurn(
        content: const [provider.TextContent('thinking'), call],
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.toolCalls,
        ),
        usage: const provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(total: 10),
          outputTokens: provider.OutputTokens(total: 5),
        ),
      );
      final model = ScriptedModel(turns: [turn]);
      final options = provider.LanguageModelCallOptions(prompt: const []);

      final result = await model.doStream(options);
      final parts = await result.stream.toList();

      expect(parts, hasLength(6));
      expect(parts[0], isA<provider.StreamStart>());
      expect(parts[1], isA<provider.TextStart>());
      expect(parts[2], isA<provider.TextDelta>());
      expect(parts[3], isA<provider.TextEnd>());
      expect(parts[4], call);
      expect(parts[5], isA<provider.FinishPart>());
      final finish = parts[5] as provider.FinishPart;
      expect(finish.finishReason.unified, provider.FinishReasonType.toolCalls);
    });

    test('多次调用 doStream 依次消费 turns,callCount 递增', () async {
      final first = ScriptedTurn(
        content: const [provider.TextContent('first')],
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        ),
        usage: const provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(),
          outputTokens: provider.OutputTokens(),
        ),
      );
      final second = ScriptedTurn(
        content: const [provider.TextContent('second')],
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        ),
        usage: const provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(),
          outputTokens: provider.OutputTokens(),
        ),
      );
      final model = ScriptedModel(turns: [first, second]);
      final options = provider.LanguageModelCallOptions(prompt: const []);

      final firstParts = await (await model.doStream(options)).stream.toList();
      expect(model.callCount, 1);
      expect((firstParts[2] as provider.TextDelta).delta, 'first');

      final secondParts = await (await model.doStream(options)).stream.toList();
      expect(model.callCount, 2);
      expect((secondParts[2] as provider.TextDelta).delta, 'second');
    });

    test('调用次数超出 turns 长度时抛 StateError', () async {
      final model = ScriptedModel(turns: [
        ScriptedTurn(
          content: const [provider.TextContent('only')],
          finishReason: const provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: const provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(),
            outputTokens: provider.OutputTokens(),
          ),
        ),
      ]);
      final options = provider.LanguageModelCallOptions(prompt: const []);

      await (await model.doStream(options)).stream.toList();
      final secondResult = await model.doStream(options);
      expect(secondResult.stream.toList(), throwsStateError);
    });
  });
}
