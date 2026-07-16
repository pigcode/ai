import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:test/test.dart';

void main() {
  group('convertOpenAiCompatibleChatUsage', () {
    test('usage 为 null 时返回全 null 壳', () {
      final usage = convertOpenAiCompatibleChatUsage(null);

      expect(usage.inputTokens.total, isNull);
      expect(usage.inputTokens.noCache, isNull);
      expect(usage.inputTokens.cacheRead, isNull);
      expect(usage.inputTokens.cacheWrite, isNull);
      expect(usage.outputTokens.total, isNull);
      expect(usage.outputTokens.text, isNull);
      expect(usage.outputTokens.reasoning, isNull);
      expect(usage.raw, isNull);
    });

    test('完整 usage 对象按两级判空精确复刻', () {
      final rawUsage = <String, Object?>{
        'prompt_tokens': 100,
        'completion_tokens': 50,
        'total_tokens': 150,
        'prompt_tokens_details': {'cached_tokens': 20},
        'completion_tokens_details': {
          'reasoning_tokens': 10,
          'accepted_prediction_tokens': 3,
          'rejected_prediction_tokens': 1,
        },
      };

      final usage = convertOpenAiCompatibleChatUsage(rawUsage);

      expect(usage.inputTokens.total, 100);
      expect(usage.inputTokens.noCache, 80);
      expect(usage.inputTokens.cacheRead, 20);
      expect(usage.inputTokens.cacheWrite, isNull);
      expect(usage.outputTokens.total, 50);
      expect(usage.outputTokens.text, 40);
      expect(usage.outputTokens.reasoning, 10);
      expect(usage.raw, rawUsage);
    });

    test('usage 存在但缺少 details 字段时按 0 兜底(非全 null)', () {
      final usage = convertOpenAiCompatibleChatUsage(<String, Object?>{
        'prompt_tokens': 10,
        'completion_tokens': 5,
      });

      expect(usage.inputTokens.total, 10);
      expect(usage.inputTokens.noCache, 10); // cached=0
      expect(usage.inputTokens.cacheRead, 0);
      expect(usage.outputTokens.total, 5);
      expect(usage.outputTokens.text, 5); // reasoning=0
      expect(usage.outputTokens.reasoning, 0);
    });
  });
}
