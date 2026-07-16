import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:test/test.dart';

/// 构造测试用 config 的最小必填字段集。
Uri _url(String path) => Uri.parse('https://api.mycustom.dev/v1$path');

Map<String, String> _headers() => const {'Authorization': 'Bearer test-key'};

void main() {
  group('OpenAiCompatibleEmbeddingConfig', () {
    test(
        '仅传必填字段时字段默认值生效:maxEmbeddingsPerCall 2048、'
        'supportsParallelCalls true', () {
      final config = OpenAiCompatibleEmbeddingConfig(
        providerName: 'mycustom',
        url: _url,
        headers: _headers,
      );

      expect(config.providerName, 'mycustom');
      expect(config.maxEmbeddingsPerCall, 2048);
      expect(config.supportsParallelCalls, isTrue);
      expect(config.client, isNull);
      expect(config.errorStructure, isNull);
    });

    test('显式传 maxEmbeddingsPerCall: null 时字段为 null(区别于未传的默认 2048)', () {
      // `int?` 语义:显式 null 表达"无覆盖",与"未传参数用默认值 2048"是
      // 两条不同路径;`??` 兜底把 null 变回 2048 由 embedding_model_test
      // 的 getter 测试验证。
      final config = OpenAiCompatibleEmbeddingConfig(
        providerName: 'mycustom',
        url: _url,
        headers: _headers,
        maxEmbeddingsPerCall: null,
      );

      expect(config.maxEmbeddingsPerCall, isNull);
    });

    test('显式传 maxEmbeddingsPerCall: 64、supportsParallelCalls: false 时原样保留', () {
      final config = OpenAiCompatibleEmbeddingConfig(
        providerName: 'mycustom',
        url: _url,
        headers: _headers,
        maxEmbeddingsPerCall: 64,
        supportsParallelCalls: false,
      );

      expect(config.maxEmbeddingsPerCall, 64);
      expect(config.supportsParallelCalls, isFalse);
    });
  });
}
