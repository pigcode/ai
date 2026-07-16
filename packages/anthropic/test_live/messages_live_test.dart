import 'dart:convert';

import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

import 'live_env.dart';

void main() {
  final env = loadLiveEnv();
  final baseUrl = env['ANTHROPIC_BASE_URL'];
  final apiKey = env['ANTHROPIC_API_KEY'];
  final model = env['ANTHROPIC_MODEL'];

  final gated = baseUrl == null || apiKey == null || model == null;

  group('messages wire live smoke', () {
    late LanguageModel messagesModel;

    setUpAll(() {
      if (gated) return;
      messagesModel =
          createAnthropic(apiKey: apiKey, baseUrl: baseUrl).messages(model);
    });

    test('doGenerate 文本', () async {
      final result = await messagesModel.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('Say "hello" and nothing else.')]),
          ],
        ),
      );

      final textContents = result.content.whereType<TextContent>();
      expect(textContents, isNotEmpty);
      expect(textContents.first.text, isNotEmpty);
      expect(result.finishReason.unified, FinishReasonType.stop);
      expect(result.usage.inputTokens.total, isNotNull);
      expect(result.usage.inputTokens.total, greaterThan(0));
    },
        skip: gated
            ? '缺少 .env(ANTHROPIC_BASE_URL/ANTHROPIC_API_KEY/ANTHROPIC_MODEL)'
            : false);

    test('doStream 文本', () async {
      final streamResult = await messagesModel.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('Say "hello" and nothing else.')]),
          ],
        ),
      );

      final parts = await streamResult.stream.toList();

      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas, isNotEmpty);
      expect(parts.last, isA<FinishPart>());
      final aggregated = textDeltas.map((d) => d.delta).join();
      expect(aggregated, isNotEmpty);
    },
        skip: gated
            ? '缺少 .env(ANTHROPIC_BASE_URL/ANTHROPIC_API_KEY/ANTHROPIC_MODEL)'
            : false);

    test('function 工具调用', () async {
      const tool = FunctionTool(
        name: 'get_current_time',
        description: 'Get the current time.',
        inputSchema: JsonSchema({'type': 'object', 'properties': {}}),
      );

      final result = await messagesModel.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('What time is it right now?')]),
          ],
          tools: [tool],
        ),
      );

      // 宽松断言:模型可能选择不调用工具;只在确有工具调用时校验其形态。
      final toolCalls = result.content.whereType<ToolCall>().toList();
      if (toolCalls.isNotEmpty) {
        expect(toolCalls.first.toolName, 'get_current_time');
        expect(() => jsonDecode(toolCalls.first.input), returnsNormally);
      }
    },
        skip: gated
            ? '缺少 .env(ANTHROPIC_BASE_URL/ANTHROPIC_API_KEY/ANTHROPIC_MODEL)'
            : false);
  });
}
