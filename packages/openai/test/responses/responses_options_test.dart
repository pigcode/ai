import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAiResponsesProviderOptions.fromProviderOptions', () {
    test('returns all-null defaults when providerOptions is null', () {
      final options = OpenAiResponsesProviderOptions.fromProviderOptions(null);

      expect(options.conversation, isNull);
      expect(options.include, isNull);
      expect(options.instructions, isNull);
      expect(options.logprobs, isNull);
      expect(options.maxToolCalls, isNull);
      expect(options.metadata, isNull);
      expect(options.parallelToolCalls, isNull);
      expect(options.previousResponseId, isNull);
      expect(options.promptCacheKey, isNull);
      expect(options.promptCacheRetention, isNull);
      expect(options.reasoningEffort, isNull);
      expect(options.reasoningSummary, isNull);
      expect(options.safetyIdentifier, isNull);
      expect(options.serviceTier, isNull);
      expect(options.store, isNull);
      expect(options.strictJsonSchema, isNull);
      expect(options.textVerbosity, isNull);
      expect(options.truncation, isNull);
      expect(options.user, isNull);
      expect(options.systemMessageMode, isNull);
      expect(options.forceReasoning, isNull);
    });

    test('returns all-null defaults when openai key is absent', () {
      final options = OpenAiResponsesProviderOptions.fromProviderOptions(
        <String, Map<String, Object?>>{'anthropic': <String, Object?>{}},
      );
      expect(options.reasoningEffort, isNull);
    });

    test('reads all fields when provided', () {
      final options = OpenAiResponsesProviderOptions.fromProviderOptions(
        <String, Map<String, Object?>>{
          'openai': <String, Object?>{
            'conversation': 'conv_123',
            'include': <String>['reasoning.encrypted_content'],
            'instructions': 'be concise',
            'logprobs': true,
            'maxToolCalls': 5,
            'metadata': <String, Object?>{'k': 'v'},
            'parallelToolCalls': false,
            'previousResponseId': 'resp_abc',
            'promptCacheKey': 'cache-1',
            'promptCacheRetention': '24h',
            'reasoningEffort': 'high',
            'reasoningSummary': 'detailed',
            'safetyIdentifier': 'user-42',
            'serviceTier': 'flex',
            'store': false,
            'strictJsonSchema': false,
            'textVerbosity': 'low',
            'truncation': 'disabled',
            'user': 'user-1',
            'systemMessageMode': 'developer',
            'forceReasoning': true,
          },
        },
      );

      expect(options.conversation, 'conv_123');
      expect(options.include, ['reasoning.encrypted_content']);
      expect(options.instructions, 'be concise');
      expect(options.logprobs, true);
      expect(options.maxToolCalls, 5);
      expect(options.metadata, {'k': 'v'});
      expect(options.parallelToolCalls, false);
      expect(options.previousResponseId, 'resp_abc');
      expect(options.promptCacheKey, 'cache-1');
      expect(options.promptCacheRetention, '24h');
      expect(options.reasoningEffort, 'high');
      expect(options.reasoningSummary, 'detailed');
      expect(options.safetyIdentifier, 'user-42');
      expect(options.serviceTier, 'flex');
      expect(options.store, false);
      expect(options.strictJsonSchema, false);
      expect(options.textVerbosity, 'low');
      expect(options.truncation, 'disabled');
      expect(options.user, 'user-1');
      expect(options.systemMessageMode, SystemMessageMode.developer);
      expect(options.forceReasoning, true);
    });

    test('accepts numeric logprobs (1..20)', () {
      final options = OpenAiResponsesProviderOptions.fromProviderOptions(
        <String, Map<String, Object?>>{
          'openai': <String, Object?>{'logprobs': 8},
        },
      );
      expect(options.logprobs, 8);
    });

    test('throws TypeValidationError for wrong field type', () {
      expect(
        () => OpenAiResponsesProviderOptions.fromProviderOptions(
          <String, Map<String, Object?>>{
            'openai': <String, Object?>{'store': 'not-a-bool'},
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('throws TypeValidationError for unknown systemMessageMode value', () {
      expect(
        () => OpenAiResponsesProviderOptions.fromProviderOptions(
          <String, Map<String, Object?>>{
            'openai': <String, Object?>{'systemMessageMode': 'bogus'},
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('two instances with identical fields are equal (Equatable)', () {
      const a = OpenAiResponsesProviderOptions(store: true, user: 'u1');
      const b = OpenAiResponsesProviderOptions(store: true, user: 'u1');
      expect(a, equals(b));
    });
  });
}
