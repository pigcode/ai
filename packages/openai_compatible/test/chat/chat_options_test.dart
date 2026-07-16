import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAiCompatibleChatProviderOptions.fromProviderOptions', () {
    test('null options 时返回全字段默认(null)的实例', () {
      final options = OpenAiCompatibleChatProviderOptions.fromProviderOptions(
        null,
        providerOptionsName: 'mycustom',
      );

      expect(options.user, isNull);
      expect(options.reasoningEffort, isNull);
      expect(options.textVerbosity, isNull);
      expect(options.strictJsonSchema, isNull);
    });

    test('缺少 providerOptionsName 对应键时同样返回全字段默认', () {
      final options = OpenAiCompatibleChatProviderOptions.fromProviderOptions(
        <String, JsonObject>{'anthropic': <String, Object?>{}},
        providerOptionsName: 'mycustom',
      );

      expect(options.user, isNull);
    });

    test('校验通过时逐字段读取', () {
      final options = OpenAiCompatibleChatProviderOptions.fromProviderOptions(
        <String, JsonObject>{
          'mycustom': <String, Object?>{
            'user': 'user-123',
            'reasoningEffort': 'ultra-deep', // 非枚举取值,裸字符串放行
            'textVerbosity': 'super-verbose',
            'strictJsonSchema': false,
          },
        },
        providerOptionsName: 'mycustom',
      );

      expect(options.user, 'user-123');
      expect(options.reasoningEffort, 'ultra-deep');
      expect(options.textVerbosity, 'super-verbose');
      expect(options.strictJsonSchema, false);
    });

    test('reasoningEffort 任意字符串均放行(不像 openai 包做 enum 校验)', () {
      final options = OpenAiCompatibleChatProviderOptions.fromProviderOptions(
        <String, JsonObject>{
          'mycustom': <String, Object?>{'reasoningEffort': 'not-a-known-value'},
        },
        providerOptionsName: 'mycustom',
      );

      expect(options.reasoningEffort, 'not-a-known-value');
    });

    test('user 类型错误时抛 TypeValidationError', () {
      expect(
        () => OpenAiCompatibleChatProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'mycustom': <String, Object?>{'user': 123},
          },
          providerOptionsName: 'mycustom',
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('strictJsonSchema 类型错误时抛 TypeValidationError', () {
      expect(
        () => OpenAiCompatibleChatProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'mycustom': <String, Object?>{'strictJsonSchema': 'yes'},
          },
          providerOptionsName: 'mycustom',
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('providerOptionsName 按传入 key 读取,不同 key 互不影响', () {
      final options = OpenAiCompatibleChatProviderOptions.fromProviderOptions(
        <String, JsonObject>{
          'providerA': <String, Object?>{'user': 'a-user'},
          'providerB': <String, Object?>{'user': 'b-user'},
        },
        providerOptionsName: 'providerB',
      );

      expect(options.user, 'b-user');
    });

    test('equatable 值相等', () {
      const a = OpenAiCompatibleChatProviderOptions(user: 'u1');
      const b = OpenAiCompatibleChatProviderOptions(user: 'u1');
      const c = OpenAiCompatibleChatProviderOptions(user: 'u2');

      expect(a, equals(b));
      expect(a == c, isFalse);
    });
  });

  group('extractPassthroughProviderOptions', () {
    test('options 为 null 时返回 const {}', () {
      final result = extractPassthroughProviderOptions(
        null,
        providerOptionsName: 'mycustom',
      );

      expect(result, isEmpty);
    });

    test('providerOptionsName 对应键缺失时返回 const {}', () {
      final result = extractPassthroughProviderOptions(
        <String, JsonObject>{
          'other': <String, Object?>{'x': 1}
        },
        providerOptionsName: 'mycustom',
      );

      expect(result, isEmpty);
    });

    test('混合已知与未知键时只返回未知键', () {
      final result = extractPassthroughProviderOptions(
        <String, JsonObject>{
          'mycustom': <String, Object?>{
            'user': 'u1',
            'reasoningEffort': 'medium',
            'textVerbosity': 'low',
            'strictJsonSchema': true,
            'topK': 40,
            'customFlag': true,
          },
        },
        providerOptionsName: 'mycustom',
      );

      expect(result, <String, Object?>{'topK': 40, 'customFlag': true});
    });

    test('全部已知键时返回空 map', () {
      final result = extractPassthroughProviderOptions(
        <String, JsonObject>{
          'mycustom': <String, Object?>{'user': 'u1'},
        },
        providerOptionsName: 'mycustom',
      );

      expect(result, isEmpty);
    });

    test('全部未知键时原样透传(值不做任何转换)', () {
      final result = extractPassthroughProviderOptions(
        <String, JsonObject>{
          'mycustom': <String, Object?>{
            'nested': <String, Object?>{'a': 1},
            'list': [1, 2, 3],
          },
        },
        providerOptionsName: 'mycustom',
      );

      expect(result, <String, Object?>{
        'nested': {'a': 1},
        'list': [1, 2, 3],
      });
    });
  });
}
