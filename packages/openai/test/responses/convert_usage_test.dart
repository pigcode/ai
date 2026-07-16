import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:test/test.dart';

void main() {
  group('convertOpenAiResponsesUsage', () {
    test('null usage yields an all-undefined shell', () {
      final usage = convertOpenAiResponsesUsage(null);

      expect(usage.inputTokens.total, isNull);
      expect(usage.inputTokens.noCache, isNull);
      expect(usage.inputTokens.cacheRead, isNull);
      expect(usage.inputTokens.cacheWrite, isNull);
      expect(usage.outputTokens.total, isNull);
      expect(usage.outputTokens.text, isNull);
      expect(usage.outputTokens.reasoning, isNull);
      expect(usage.raw, isNull);
    });

    test('usage without details defaults cached/reasoning to 0', () {
      final usage = convertOpenAiResponsesUsage(<String, Object?>{
        'input_tokens': 100,
        'output_tokens': 50,
      });

      expect(usage.inputTokens.total, 100);
      expect(usage.inputTokens.noCache, 100);
      expect(usage.inputTokens.cacheRead, 0);
      expect(usage.inputTokens.cacheWrite, isNull);
      expect(usage.outputTokens.total, 50);
      expect(usage.outputTokens.text, 50);
      expect(usage.outputTokens.reasoning, 0);
      expect(usage.raw, {'input_tokens': 100, 'output_tokens': 50});
    });

    test('usage with cached/reasoning tokens subtracts correctly', () {
      final usage = convertOpenAiResponsesUsage(<String, Object?>{
        'input_tokens': 100,
        'output_tokens': 50,
        'input_tokens_details': {'cached_tokens': 20},
        'output_tokens_details': {'reasoning_tokens': 10},
      });

      expect(usage.inputTokens.total, 100);
      expect(usage.inputTokens.noCache, 80);
      expect(usage.inputTokens.cacheRead, 20);
      expect(usage.outputTokens.total, 50);
      expect(usage.outputTokens.text, 40);
      expect(usage.outputTokens.reasoning, 10);
    });
  });
}
