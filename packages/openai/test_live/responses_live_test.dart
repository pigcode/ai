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

  final gated = baseUrl == null || apiKey == null || model == null;

  group('responses wire live smoke', () {
    late LanguageModel responsesModel;
    var unsupported = false;

    setUpAll(() {
      if (gated) return;
      responsesModel =
          createOpenAi(apiKey: apiKey, baseUrl: baseUrl).responses(model);
    });

    test('doGenerate 文本', () async {
      try {
        final result = await responsesModel.doGenerate(
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
      } on ApiCallError catch (e) {
        if (e.statusCode == 404) {
          unsupported = true;
          markTestSkipped('端点不支持 responses 协议:404');
          return;
        }
        rethrow;
      }
    },
        skip: gated
            ? '缺少 .env(OPENAI_BASE_URL/OPENAI_API_KEY/OPENAI_MODEL)'
            : false);

    test('doStream 文本', () async {
      if (unsupported) {
        markTestSkipped('端点不支持 responses 协议(见首个用例)');
        return;
      }

      final streamResult = await responsesModel.doStream(
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
      if (unsupported) {
        markTestSkipped('端点不支持 responses 协议(见首个用例)');
        return;
      }

      const tool = FunctionTool(
        name: 'get_current_time',
        description: 'Get the current time.',
        inputSchema: JsonSchema({'type': 'object', 'properties': {}}),
      );

      LanguageModelGenerateResult result;
      try {
        result = await responsesModel.doGenerate(
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
  });
}
