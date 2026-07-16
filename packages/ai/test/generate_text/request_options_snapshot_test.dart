import 'package:pigcode_ai/src/generate_text/prepare_step.dart';
import 'package:pigcode_ai/src/generate_text/request_options_snapshot.dart';
import 'package:pigcode_ai/src/generate_text/stream_text.dart';
import 'package:pigcode_ai/src/generate_text/tool_loop.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

void main() {
  group('mergeProviderOptions (recursive deep merge)', () {
    test(
        'nested objects merge recursively: container keeps skills and '
        'gains id', () {
      final merged = mergeProviderOptions(
        const {
          'anthropic': {
            'container': {
              'skills': [
                {'type': 'anthropic', 'skill_id': 'pptx'},
              ],
            },
          },
        },
        const {
          'anthropic': {
            'container': {'id': 'container-1'},
          },
        },
      )!;

      expect(merged, {
        'anthropic': {
          'container': {
            'skills': [
              {'type': 'anthropic', 'skill_id': 'pptx'},
            ],
            'id': 'container-1',
          },
        },
      });
    });

    test('lists are replaced, not concatenated', () {
      final merged = mergeProviderOptions(
        const {
          'anthropic': {
            'items': ['a', 'b'],
          },
        },
        const {
          'anthropic': {
            'items': ['c'],
          },
        },
      )!;

      expect(merged['anthropic']!['items'], ['c']);
    });

    test('explicit null in override replaces the base value', () {
      final merged = mergeProviderOptions(
        const {
          'anthropic': {'keep': 'base', 'drop': 'base-value'},
        },
        const {
          'anthropic': {'drop': null},
        },
      )!;

      final anthropic = merged['anthropic']!;
      expect(anthropic.containsKey('drop'), isTrue);
      expect(anthropic['drop'], isNull);
      expect(anthropic['keep'], 'base');
    });

    test('keys absent from override keep the base value', () {
      final merged = mergeProviderOptions(
        const {
          'anthropic': {'a': 1, 'b': 2},
          'openai': {'x': true},
        },
        const {
          'anthropic': {'b': 3},
        },
      )!;

      expect(merged, {
        'anthropic': {'a': 1, 'b': 3},
        'openai': {'x': true},
      });
    });

    test(
        'null-side passthrough: null base returns override snapshot, '
        'null override returns base content, both null returns null', () {
      expect(mergeProviderOptions(null, null), isNull);
      expect(
        mergeProviderOptions(null, const {
          'openai': {'k': 'v'},
        }),
        {
          'openai': {'k': 'v'},
        },
      );
      expect(
        mergeProviderOptions(const {
          'openai': {'k': 'v'},
        }, null),
        {
          'openai': {'k': 'v'},
        },
      );
    });

    test('merged result is a deeply unmodifiable snapshot', () {
      final merged = mergeProviderOptions(
        const {
          'anthropic': {
            'container': {'skills': <Object?>[]},
          },
        },
        const {
          'anthropic': {
            'container': {'id': 'container-1'},
          },
        },
      )!;

      expect(() => merged['x'] = const {}, throwsUnsupportedError);
      expect(
        () => merged['anthropic']!['y'] = true,
        throwsUnsupportedError,
      );
      final container =
          merged['anthropic']!['container']! as Map<String, Object?>;
      expect(() => container['id'] = 'mutated', throwsUnsupportedError);
    });
  });

  group('providerOptions × prepareStep 深合并端到端(既有两调用点回归)', () {
    const turn = ScriptedTurn(
      content: [provider.TextContent('ok')],
      finishReason: provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop,
      ),
      usage: provider.LanguageModelUsage(
        inputTokens: provider.InputTokens(total: 1),
        outputTokens: provider.OutputTokens(total: 1),
      ),
    );
    const baseOptions = <String, provider.JsonObject>{
      'anthropic': {
        'container': {
          'skills': [
            {'type': 'anthropic', 'skill_id': 'pptx'},
          ],
        },
      },
    };
    const overrideOptions = <String, provider.JsonObject>{
      'anthropic': {
        'container': {'id': 'container-1'},
      },
    };
    const expectedMerged = <String, Object?>{
      'anthropic': {
        'container': {
          'skills': [
            {'type': 'anthropic', 'skill_id': 'pptx'},
          ],
          'id': 'container-1',
        },
      },
    };

    test('generate 路:tool_loop 调用点把深合并结果送进 callOptions', () async {
      final model = ScriptedModel(turns: [turn]);

      await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('hi')]),
        ],
        providerOptions: baseOptions,
        prepareStep: (options) =>
            PrepareStepResult(providerOptions: overrideOptions),
      );

      expect(
        model.receivedCallOptions.single.providerOptions,
        expectedMerged,
      );
    });

    test('stream 路:stream_text 调用点把深合并结果送进 callOptions', () async {
      final model = ScriptedModel(turns: [turn]);

      final result = streamText(
        model: model,
        prompt: 'hi',
        providerOptions: baseOptions,
        prepareStep: (options) =>
            PrepareStepResult(providerOptions: overrideOptions),
      );
      await result.consumeStream();

      expect(
        model.receivedCallOptions.single.providerOptions,
        expectedMerged,
      );
    });
  });
}
