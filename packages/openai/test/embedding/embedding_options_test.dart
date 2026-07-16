import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_openai/src/internal/provider_options.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAiEmbeddingProviderOptions.fromProviderOptions', () {
    test('null options 时返回全字段默认(null)的实例', () {
      final options = OpenAiEmbeddingProviderOptions.fromProviderOptions(null);

      expect(options.dimensions, isNull);
      expect(options.user, isNull);
    });

    test('openai 键下 dimensions/user 两字段正确解析', () {
      final options = OpenAiEmbeddingProviderOptions.fromProviderOptions(
        <String, JsonObject>{
          'openai': <String, Object?>{'dimensions': 256, 'user': 'u1'},
        },
      );

      expect(options.dimensions, 256);
      expect(options.user, 'u1');
    });

    test('dimensions 传字符串(非法类型)时抛 TypeValidationError', () {
      expect(
        () => OpenAiEmbeddingProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'openai': <String, Object?>{'dimensions': 'not-a-number'},
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('azure 键经 resolveOpenAiProviderOptions 重映射后可读到 dimensions', () {
      // 只验证 azure 重映射链路的接线(resolveOpenAiProviderOptions 本身
      // 已在 provider_options 的既有测试覆盖):调用方把 {'azure': {...}}
      // 经重映射后传入 fromProviderOptions,应能读到字段。
      final options = OpenAiEmbeddingProviderOptions.fromProviderOptions(
        resolveOpenAiProviderOptions(
          'azure-foo',
          <String, JsonObject>{
            'azure': <String, Object?>{'dimensions': 512},
          },
        ),
      );

      expect(options.dimensions, 512);
    });
  });
}
