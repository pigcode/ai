import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAiCompatibleEmbeddingProviderOptions.fromProviderOptions', () {
    test('options 为 null 时返回全字段 null 的默认实例', () {
      final options =
          OpenAiCompatibleEmbeddingProviderOptions.fromProviderOptions(
        null,
        providerOptionsName: 'mycustom',
      );

      expect(options, const OpenAiCompatibleEmbeddingProviderOptions());
      expect(options.dimensions, isNull);
      expect(options.user, isNull);
    });

    test('providerOptionsName 键下的 dimensions/user 正确解析', () {
      final options =
          OpenAiCompatibleEmbeddingProviderOptions.fromProviderOptions(
        const {
          'mycustom': {'dimensions': 256, 'user': 'u1'},
        },
        providerOptionsName: 'mycustom',
      );

      expect(options.dimensions, 256);
      expect(options.user, 'u1');
    });

    test('providerOptionsName 对应键缺失时返回默认实例(不误读其他 key)', () {
      final options =
          OpenAiCompatibleEmbeddingProviderOptions.fromProviderOptions(
        const {
          'otherprovider': {'dimensions': 512},
        },
        providerOptionsName: 'mycustom',
      );

      expect(options, const OpenAiCompatibleEmbeddingProviderOptions());
    });

    test('dimensions 传布尔值(非法类型)时抛 TypeValidationError', () {
      expect(
        () => OpenAiCompatibleEmbeddingProviderOptions.fromProviderOptions(
          const {
            'mycustom': {'dimensions': true},
          },
          providerOptionsName: 'mycustom',
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('未知键不抛错但被丢弃(与 chat 侧的透传机制不同)', () {
      // schema `additionalProperties: true`,未知键不触发校验失败(与 chat
      // 侧一致);但与 chat 侧不同的是,embedding wire 没有
      // `extractPassthroughProviderOptions` 等价物——上游 raw embedding
      // 完全没有透传机制,body 只有五个固定字段,故未知键(extraField)
      // 在解析后无处承载,直接被丢弃。
      final options =
          OpenAiCompatibleEmbeddingProviderOptions.fromProviderOptions(
        const {
          'mycustom': {'dimensions': 1, 'extraField': 'x'},
        },
        providerOptionsName: 'mycustom',
      );

      expect(options.dimensions, 1);
      expect(options.user, isNull);
      // 返回值只有 dimensions/user 两个字段;整体值相等即证明 extraField
      // 未被任何字段承载。
      expect(
        options,
        const OpenAiCompatibleEmbeddingProviderOptions(dimensions: 1),
      );
    });
  });
}
