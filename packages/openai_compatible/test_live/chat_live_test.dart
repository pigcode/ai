import 'dart:convert';

import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
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
  const skipReason = '缺少 .env(OPENAI_BASE_URL/OPENAI_API_KEY/OPENAI_MODEL)';

  group('openai_compatible chat wire live smoke', () {
    late LanguageModel chatModel;

    setUpAll(() {
      if (gated) return;
      // 本包是该兼容端点的主场:name 任意取一个便于辨识日志来源的值。
      // 注:`if (gated) return;` 已把 baseUrl/model 流提升为非空,无需 `!`。
      chatModel = createOpenAiCompatible(
        name: 'live',
        baseUrl: baseUrl,
        apiKey: apiKey,
      ).chatModel(model);
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
    }, skip: gated ? skipReason : false);

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
    }, skip: gated ? skipReason : false);

    test('function 工具调用闭环', () async {
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
    }, skip: gated ? skipReason : false);

    test('reasoning 双读:reasoning_content 累积进 ReasoningContent', () async {
      // glm 系模型在思考型请求下会返回 reasoning_content(非标准 OpenAI
      // 字段,本包「宽松 schema」策略下双读回传,见 spec §1)。用一个需要
      // 多步推理的问题提高触发概率;若端点/模型未开启推理模式,
      // reasoningContents 可能为空——这种情况下降级为 markTestSkipped
      // 而非断言失败,因为「该模型是否触发 reasoning_content」不是本包
      // 该负责的稳定契约,只验证「若出现则被正确解析」。
      final result = await chatModel.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([
              TextPart(
                'If a train travels 60 km in 45 minutes, what is its '
                'speed in km/h? Think step by step.',
              ),
            ]),
          ],
        ),
      );

      final reasoningContents = result.content.whereType<ReasoningContent>();
      final textContents = result.content.whereType<TextContent>();
      expect(textContents, isNotEmpty);

      if (reasoningContents.isEmpty) {
        markTestSkipped('本次响应未触发 reasoning_content,降级跳过双读断言');
        return;
      }
      expect(reasoningContents.first.text, isNotEmpty);
    }, skip: gated ? skipReason : false);

    test('多模态:1x1 红色 PNG 图片理解(data URI)', () async {
      if (multiModalModel == null) {
        markTestSkipped('缺少 .env OPENAI_MULTI_MODAL_MODEL');
        return;
      }

      final multiModalChatModel = createOpenAiCompatible(
        name: 'live',
        baseUrl: baseUrl!,
        apiKey: apiKey,
      ).chatModel(multiModalModel);

      // 1x1 红色 PNG 的原始字节,与 packages/openai/test_live/chat_live_test.dart
      // 的既定做法一致:直接传 FileDataBytes,由 convert_messages 编码层
      // 负责转成 data URI(base64),测试不手写 data URI 字符串。
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
    }, skip: gated ? skipReason : false);
  });
}
