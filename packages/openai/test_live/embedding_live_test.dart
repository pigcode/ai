import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

import 'live_env.dart';

// 注:与计划文档中的示意代码不同,本文件直接调用契约层 `doEmbed` 而非
// `pigcode_ai` 的 `embed`/`embedMany`——本包 pubspec 不依赖(架构上也禁止
// 反向依赖)核心包 `pigcode_ai`,与既有 `chat_live_test.dart` 直接调
// `doGenerate`/`doStream` 的先例一致;冒烟语义(单值/多值、保序、非空
// 向量、宽松 usage)不变。
void main() {
  final env = loadLiveEnv();
  final baseUrl = env['OPENAI_BASE_URL'];
  final apiKey = env['OPENAI_API_KEY'];
  final embeddingModelId = env['OPENAI_EMBEDDING_MODEL'];

  final gated = baseUrl == null || apiKey == null;

  group('embedding wire live smoke', () {
    late EmbeddingModel embeddingModel;

    setUpAll(() {
      if (gated || embeddingModelId == null) return;
      embeddingModel =
          createOpenAi(apiKey: apiKey, baseUrl: baseUrl).embeddingModel(
        embeddingModelId,
      );
    });

    test('doEmbed 单值:返回非空向量', () async {
      if (gated) {
        markTestSkipped('缺少 .env(OPENAI_BASE_URL/OPENAI_API_KEY)');
        return;
      }
      if (embeddingModelId == null) {
        markTestSkipped('缺少 .env OPENAI_EMBEDDING_MODEL');
        return;
      }

      final result = await embeddingModel.doEmbed(
        const EmbeddingModelCallOptions(values: ['Hello, world!']),
      );

      expect(result.embeddings, hasLength(1));
      expect(result.embeddings.single, isNotEmpty);
    });

    test('doEmbed 三值:与输入保序对应且各向量非空', () async {
      if (gated) {
        markTestSkipped('缺少 .env(OPENAI_BASE_URL/OPENAI_API_KEY)');
        return;
      }
      if (embeddingModelId == null) {
        markTestSkipped('缺少 .env OPENAI_EMBEDDING_MODEL');
        return;
      }

      const values = ['apple', 'banana', 'cherry'];
      final result = await embeddingModel.doEmbed(
        const EmbeddingModelCallOptions(values: values),
      );

      // 契约保证 embeddings 与输入 values 保序对应,冒烟层面断言条数
      // 与非空;向量语义上的"哪个对应哪个"无法在黑盒冒烟里可靠断言。
      expect(result.embeddings, hasLength(3));
      for (final embedding in result.embeddings) {
        expect(embedding, isNotEmpty);
      }
      // usage.tokens 断言宽松:端点是否回传 usage 不是本冒烟测试要锁定
      // 的稳定契约,只要类型合法(int 或 null)即可,不强求非 null。
      expect(result.usage.tokens, anyOf(isNull, isA<int>()));
    });
  });
}
