import 'dart:convert';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

import 'live_env.dart';

void main() {
  final env = loadLiveEnv();
  final baseUrl = env['OPENAI_BASE_URL'];
  final apiKey = env['OPENAI_API_KEY'];
  final model = env['OPENAI_MODEL'];
  final multiModalModel = env['OPENAI_MULTI_MODAL_MODEL'];

  final gated = baseUrl == null || apiKey == null || model == null;

  group('chat wire live smoke', () {
    late LanguageModel chatModel;

    setUpAll(() {
      if (gated) return;
      chatModel = createOpenAi(apiKey: apiKey, baseUrl: baseUrl).chat(model);
    });

    test('doGenerate 文本', () async {
      final result = await chatModel.doGenerate(
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
            ? '缺少 .env(OPENAI_BASE_URL/OPENAI_API_KEY/OPENAI_MODEL)'
            : false);

    test('doStream 文本', () async {
      final streamResult = await chatModel.doStream(
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
            ? '缺少 .env(OPENAI_BASE_URL/OPENAI_API_KEY/OPENAI_MODEL)'
            : false);

    test('function 工具调用', () async {
      const tool = FunctionTool(
        name: 'get_current_time',
        description: 'Get the current time.',
        inputSchema: JsonSchema({'type': 'object', 'properties': {}}),
      );

      LanguageModelGenerateResult result;
      try {
        result = await chatModel.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('What time is it right now?')]),
            ],
            tools: [tool],
            toolChoice: ToolChoiceRequired(),
          ),
        );
      } on ApiCallError catch (e) {
        if (e.statusCode != null &&
            e.statusCode! >= 400 &&
            e.statusCode! < 500) {
          markTestSkipped(
              '端点对 toolChoice:required 返回 4xx,能力不支持:${e.statusCode}');
          return;
        }
        rethrow;
      }

      final toolCalls = result.content.whereType<ToolCall>().toList();
      expect(toolCalls, isNotEmpty);
      expect(toolCalls.first.toolName, 'get_current_time');
      expect(() => jsonDecode(toolCalls.first.input), returnsNormally);
    },
        skip: gated
            ? '缺少 .env(OPENAI_BASE_URL/OPENAI_API_KEY/OPENAI_MODEL)'
            : false);

    test('多模态:1x1 红色 PNG 图片理解', () async {
      if (multiModalModel == null) {
        markTestSkipped('缺少 .env OPENAI_MULTI_MODAL_MODEL');
        return;
      }

      final multiModalChatModel =
          createOpenAi(apiKey: apiKey!, baseUrl: baseUrl).chat(multiModalModel);

      // 1x1 红色 PNG 的原始字节。
      const redPixelPngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
      final bytes = base64Decode(redPixelPngBase64);

      final result = await multiModalChatModel.doGenerate(
        LanguageModelCallOptions(
          prompt: [
            UserMessage([
              const TextPart('What color is this image? Answer in one word.'),
              FilePart(data: FileDataBytes(bytes), mediaType: 'image/png'),
            ]),
          ],
        ),
      );

      final textContents = result.content.whereType<TextContent>();
      expect(textContents, isNotEmpty);
      expect(textContents.first.text, isNotEmpty);
    },
        skip: gated
            ? '缺少 .env(OPENAI_BASE_URL/OPENAI_API_KEY/OPENAI_MODEL)'
            : false);
  });
}
