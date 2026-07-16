import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAiChatProviderOptions.fromProviderOptions', () {
    test('null options 时返回全字段默认(null)的实例', () {
      final options = OpenAiChatProviderOptions.fromProviderOptions(null);

      expect(options.logitBias, isNull);
      expect(options.logprobs, isNull);
      expect(options.parallelToolCalls, isNull);
      expect(options.user, isNull);
      expect(options.reasoningEffort, isNull);
      expect(options.maxCompletionTokens, isNull);
      expect(options.store, isNull);
      expect(options.metadata, isNull);
      expect(options.prediction, isNull);
      expect(options.serviceTier, isNull);
      expect(options.strictJsonSchema, isNull);
      expect(options.textVerbosity, isNull);
      expect(options.promptCacheKey, isNull);
      expect(options.promptCacheRetention, isNull);
      expect(options.safetyIdentifier, isNull);
      expect(options.systemMessageMode, isNull);
      expect(options.forceReasoning, isNull);
    });

    test('缺少 openai 键时同样返回全字段默认', () {
      final options = OpenAiChatProviderOptions.fromProviderOptions(
        <String, JsonObject>{'anthropic': <String, Object?>{}},
      );

      expect(options.user, isNull);
    });

    test('校验通过时逐字段读取', () {
      final options = OpenAiChatProviderOptions.fromProviderOptions(
        <String, JsonObject>{
          'openai': <String, Object?>{
            'logitBias': <String, Object?>{'50256': -100},
            'logprobs': true,
            'parallelToolCalls': false,
            'user': 'user-123',
            'reasoningEffort': 'medium',
            'maxCompletionTokens': 2048,
            'store': true,
            'metadata': <String, Object?>{'k': 'v'},
            'prediction': <String, Object?>{'type': 'content', 'content': 'x'},
            'serviceTier': 'flex',
            'strictJsonSchema': false,
            'textVerbosity': 'low',
            'promptCacheKey': 'cache-key',
            'promptCacheRetention': '24h',
            'safetyIdentifier': 'safety-1',
            'systemMessageMode': 'developer',
            'forceReasoning': true,
          },
        },
      );

      expect(options.logitBias, <String, num>{'50256': -100});
      expect(options.logprobs, true);
      expect(options.parallelToolCalls, false);
      expect(options.user, 'user-123');
      expect(options.reasoningEffort, 'medium');
      expect(options.maxCompletionTokens, 2048);
      expect(options.store, true);
      expect(options.metadata, <String, String>{'k': 'v'});
      expect(options.prediction,
          <String, Object?>{'type': 'content', 'content': 'x'});
      expect(options.serviceTier, 'flex');
      expect(options.strictJsonSchema, false);
      expect(options.textVerbosity, 'low');
      expect(options.promptCacheKey, 'cache-key');
      expect(options.promptCacheRetention, '24h');
      expect(options.safetyIdentifier, 'safety-1');
      expect(options.systemMessageMode, SystemMessageMode.developer);
      expect(options.forceReasoning, true);
    });

    test('logprobs 接受整数形式(top-n)', () {
      final options = OpenAiChatProviderOptions.fromProviderOptions(
        <String, JsonObject>{
          'openai': <String, Object?>{'logprobs': 3},
        },
      );

      expect(options.logprobs, 3);
    });

    test('reasoningEffort 不在枚举中时抛 TypeValidationError', () {
      expect(
        () => OpenAiChatProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'bogus'},
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('systemMessageMode 不在枚举中时抛 TypeValidationError', () {
      expect(
        () => OpenAiChatProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'openai': <String, Object?>{'systemMessageMode': 'bogus'},
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('metadata 值非 string 时抛 TypeValidationError(而非裸 _TypeError)', () {
      expect(
        () => OpenAiChatProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'openai': <String, Object?>{
              'metadata': <String, Object?>{'n': 1},
            },
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('metadata 值均为 string 时正常读取', () {
      final options = OpenAiChatProviderOptions.fromProviderOptions(
        <String, JsonObject>{
          'openai': <String, Object?>{
            'metadata': <String, Object?>{'a': 'b', 'c': 'd'},
          },
        },
      );

      expect(options.metadata, <String, String>{'a': 'b', 'c': 'd'});
    });

    test('logitBias 值非 num 时抛 TypeValidationError(而非裸 TypeError)', () {
      expect(
        () => OpenAiChatProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'openai': <String, Object?>{
              'logitBias': <String, Object?>{'50256': 'x'},
            },
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('logitBias 值均为 num 时正常读取', () {
      final options = OpenAiChatProviderOptions.fromProviderOptions(
        <String, JsonObject>{
          'openai': <String, Object?>{
            'logitBias': <String, Object?>{'50256': -100, '50257': 50},
          },
        },
      );

      expect(options.logitBias, <String, num>{'50256': -100, '50257': 50});
    });

    test('equatable 值相等', () {
      const a = OpenAiChatProviderOptions(user: 'u1');
      const b = OpenAiChatProviderOptions(user: 'u1');
      const c = OpenAiChatProviderOptions(user: 'u2');

      expect(a, equals(b));
      expect(a == c, isFalse);
    });
  });
}
