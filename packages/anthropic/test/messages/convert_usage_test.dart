import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('convertAnthropicUsage', () {
    test('基础字段:input/output 直取,cache 兜底为 0,raw 为 wire usage 本身', () {
      final usage = <String, Object?>{'input_tokens': 10, 'output_tokens': 5};

      final result = convertAnthropicUsage(usage);

      expect(
        result.inputTokens,
        const InputTokens(total: 10, noCache: 10, cacheRead: 0, cacheWrite: 0),
      );
      expect(
        result.outputTokens,
        const OutputTokens(total: 5, text: null, reasoning: null),
      );
      expect(result.raw, same(usage));
    });

    test('cache 两项计入 total:total = input + cacheWrite + cacheRead', () {
      final result = convertAnthropicUsage(<String, Object?>{
        'input_tokens': 3,
        'output_tokens': 7,
        'cache_creation_input_tokens': 100,
        'cache_read_input_tokens': 200,
      });

      expect(
        result.inputTokens,
        const InputTokens(
          total: 303,
          noCache: 3,
          cacheRead: 200,
          cacheWrite: 100,
        ),
      );
      expect(
        result.outputTokens,
        const OutputTokens(total: 7, text: null, reasoning: null),
      );
    });

    test('iterations 含 fallback_message 时直接用顶层值,不做 executor 求和', () {
      final result = convertAnthropicUsage(<String, Object?>{
        'input_tokens': 50,
        'output_tokens': 60,
        'iterations': <Object?>[
          <String, Object?>{
            'type': 'message',
            'input_tokens': 4,
            'output_tokens': 6,
          },
          <String, Object?>{
            'type': 'fallback_message',
            'input_tokens': 1,
            'output_tokens': 2,
          },
        ],
      });

      expect(
        result.inputTokens,
        const InputTokens(total: 50, noCache: 50, cacheRead: 0, cacheWrite: 0),
      );
      expect(
        result.outputTokens,
        const OutputTokens(total: 60, text: null, reasoning: null),
      );
    });

    test(
        'iterations executor 求和:message/compaction 计入,advisor_message 排除;'
        'cache 仍取顶层', () {
      final result = convertAnthropicUsage(<String, Object?>{
        'input_tokens': 50,
        'output_tokens': 50,
        'cache_creation_input_tokens': 10,
        'cache_read_input_tokens': 20,
        'iterations': <Object?>[
          <String, Object?>{
            'type': 'message',
            'input_tokens': 4,
            'output_tokens': 6,
          },
          <String, Object?>{
            'type': 'compaction',
            'input_tokens': 2,
            'output_tokens': 1,
          },
          <String, Object?>{
            'type': 'advisor_message',
            'input_tokens': 99,
            'output_tokens': 99,
          },
        ],
      });

      expect(
        result.inputTokens,
        const InputTokens(total: 36, noCache: 6, cacheRead: 20, cacheWrite: 10),
      );
      expect(
        result.outputTokens,
        const OutputTokens(total: 7, text: null, reasoning: null),
      );
    });

    test('iterations 全为 advisor_message 时回退顶层值', () {
      final result = convertAnthropicUsage(<String, Object?>{
        'input_tokens': 50,
        'output_tokens': 60,
        'iterations': <Object?>[
          <String, Object?>{
            'type': 'advisor_message',
            'input_tokens': 99,
            'output_tokens': 99,
          },
        ],
      });

      expect(
        result.inputTokens,
        const InputTokens(total: 50, noCache: 50, cacheRead: 0, cacheWrite: 0),
      );
      expect(
        result.outputTokens,
        const OutputTokens(total: 60, text: null, reasoning: null),
      );
    });

    test('无 iterations 键或 iterations 为 null 时用顶层值', () {
      for (final usage in <Map<String, Object?>>[
        <String, Object?>{'input_tokens': 8, 'output_tokens': 9},
        <String, Object?>{
          'input_tokens': 8,
          'output_tokens': 9,
          'iterations': null,
        },
      ]) {
        final result = convertAnthropicUsage(usage);

        expect(
          result.inputTokens,
          const InputTokens(total: 8, noCache: 8, cacheRead: 0, cacheWrite: 0),
        );
        expect(
          result.outputTokens,
          const OutputTokens(total: 9, text: null, reasoning: null),
        );
      }
    });

    test('显式传入 rawUsage 时 raw 取 rawUsage', () {
      final usage = <String, Object?>{'input_tokens': 1, 'output_tokens': 2};
      final rawUsage = <String, Object?>{'anything': 'else'};

      final result = convertAnthropicUsage(usage, rawUsage: rawUsage);

      expect(result.raw, same(rawUsage));
    });
  });
}
