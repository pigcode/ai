import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

import 'support/echo_model.dart';

/// 从 prompt 里取最后一条 user 文本的期望值,和 EchoModel 内部逻辑对齐。
LanguageModelCallOptions _options(String userText) => LanguageModelCallOptions(
      prompt: [
        const SystemMessage('you are a test'),
        UserMessage([TextPart(userText)]),
      ],
    );

void main() {
  group('EchoModel.doGenerate', () {
    test('回吐最后一条 user 文本为单个 TextContent + stop', () async {
      final model = EchoModel();

      final result = await model.doGenerate(_options('hello world'));

      expect(result.content, hasLength(1));
      final first = result.content.first;
      expect(first, isA<TextContent>());
      expect((first as TextContent).text, 'hello world');

      expect(result.finishReason.unified, FinishReasonType.stop);
      expect(result.finishReason.raw, isNull);

      // usage:output.text = 回吐字符数;input 归零。
      expect(result.usage.outputTokens.text, 'hello world'.length);
      expect(result.usage.outputTokens.total, 'hello world'.length);
      expect(result.usage.inputTokens.total, 0);

      expect(result.warnings, isEmpty);
    });

    test('无 user 消息时回吐空文本,仍为一个 TextContent', () async {
      final model = EchoModel();

      final result =
          await model.doGenerate(const LanguageModelCallOptions(prompt: []));

      expect(result.content, hasLength(1));
      expect((result.content.first as TextContent).text, '');
      expect(result.usage.outputTokens.text, 0);
      expect(result.finishReason.unified, FinishReasonType.stop);
    });
  });

  group('EchoModel.doStream', () {
    test(
        '按 StreamStart -> TextStart -> TextDelta -> TextEnd -> FinishPart 顺序发出',
        () async {
      final model = EchoModel();

      final stream = (await model.doStream(_options('hi'))).stream;
      final parts = await stream.toList();

      expect(parts.map((p) => p.runtimeType).toList(), [
        StreamStart,
        TextStart,
        TextDelta,
        TextEnd,
        FinishPart,
      ]);

      final start = parts[0] as StreamStart;
      expect(start.warnings, isEmpty);

      final textStart = parts[1] as TextStart;
      final delta = parts[2] as TextDelta;
      final textEnd = parts[3] as TextEnd;
      // 三个文本分块共享同一个 id。
      expect(delta.id, textStart.id);
      expect(textEnd.id, textStart.id);
      expect(delta.delta, 'hi');

      final finish = parts[4] as FinishPart;
      expect(finish.finishReason.unified, FinishReasonType.stop);
      expect(finish.usage.outputTokens.text, 'hi'.length);
    });
  });

  group('spec 常量', () {
    test('languageModelSpecVersion 为 v4', () {
      expect(languageModelSpecVersion, 'v4');
    });

    test('LanguageModel exposes specificationVersion v4', () {
      const LanguageModel model = EchoModel();

      expect(model.specificationVersion, 'v4');
    });
  });
}
