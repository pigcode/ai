import 'package:pigcode_ai/pigcode_ai.dart' as ai;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

void main() {
  const prompt = <provider.LanguageModelMessage>[
    provider.UserMessage([provider.TextPart('hi')]),
  ];

  ScriptedTurn textTurn(String text) {
    return ScriptedTurn(
      content: [provider.TextContent(text)],
      finishReason: const provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop,
      ),
      usage: const provider.LanguageModelUsage(
        inputTokens: provider.InputTokens(),
        outputTokens: provider.OutputTokens(),
      ),
    );
  }

  group('defaultSettingsMiddleware', () {
    test('fills missing language settings and deeply merges request metadata',
        () async {
      final scripted = ScriptedModel(
        provider: 'scripted',
        modelId: 'm-1',
        turns: [textTurn('ok')],
      );
      final controller = provider.CancellationController();
      const defaultTool = provider.FunctionTool(
        name: 'search',
        inputSchema: provider.JsonSchema({'type': 'object'}),
      );

      final wrapped = ai.wrapLanguageModel(
        scripted,
        ai.defaultSettingsMiddleware(
          settings: const ai.DefaultLanguageModelSettings(
            maxOutputTokens: 128,
            temperature: 0.2,
            topP: 0.7,
            topK: 40,
            presencePenalty: 0.1,
            frequencyPenalty: 0.2,
            seed: 7,
            stopSequences: ['STOP'],
            responseFormat: provider.ResponseFormatJson(name: 'default'),
            tools: [defaultTool],
            toolChoice: provider.ToolChoiceAuto(),
            reasoning: provider.ReasoningEffort.low,
            includeRawChunks: true,
            headers: {
              'x-default': 'default',
              'x-shared': 'default',
            },
            providerOptions: {
              'openai': {
                'outer': {
                  'default': true,
                  'shared': 'default',
                  'array': [1, 2],
                },
                'defaultOnly': 'yes',
              },
              'anthropic': {'cache': true},
            },
          ),
        ),
      );

      await wrapped.doGenerate(provider.LanguageModelCallOptions(
        prompt: prompt,
        temperature: 0.9,
        headers: const {
          'x-shared': 'call',
          'x-call': 'call',
        },
        providerOptions: const {
          'openai': {
            'outer': {
              'shared': 'call',
              'array': [3],
              'callOnly': true,
            },
            'callOnlyTop': 'yes',
          },
        },
        cancellation: controller.signal,
      ));

      final seen = scripted.receivedCallOptions.single;
      expect(seen.prompt, same(prompt));
      expect(seen.cancellation, same(controller.signal));
      expect(seen.maxOutputTokens, 128);
      expect(seen.temperature, 0.9);
      expect(seen.topP, 0.7);
      expect(seen.topK, 40);
      expect(seen.presencePenalty, 0.1);
      expect(seen.frequencyPenalty, 0.2);
      expect(seen.seed, 7);
      expect(seen.stopSequences, ['STOP']);
      expect(
        seen.responseFormat,
        const provider.ResponseFormatJson(name: 'default'),
      );
      expect(seen.tools, [defaultTool]);
      expect(seen.toolChoice, const provider.ToolChoiceAuto());
      expect(seen.reasoning, provider.ReasoningEffort.low);
      expect(seen.includeRawChunks, isTrue);
      expect(seen.headers, {
        'x-default': 'default',
        'x-shared': 'call',
        'x-call': 'call',
      });
      expect(seen.providerOptions, {
        'openai': {
          'outer': {
            'default': true,
            'shared': 'call',
            'array': [3],
            'callOnly': true,
          },
          'defaultOnly': 'yes',
          'callOnlyTop': 'yes',
        },
        'anthropic': {'cache': true},
      });
    });

    test('leaves metadata null when neither defaults nor params provide it',
        () async {
      final scripted = ScriptedModel(
        provider: 'scripted',
        modelId: 'm-1',
        turns: [textTurn('ok')],
      );
      final wrapped = ai.wrapLanguageModel(
        scripted,
        ai.defaultSettingsMiddleware(
          settings: const ai.DefaultLanguageModelSettings(),
        ),
      );

      await wrapped.doGenerate(
        const provider.LanguageModelCallOptions(prompt: prompt),
      );

      final seen = scripted.receivedCallOptions.single;
      expect(seen.headers, isNull);
      expect(seen.providerOptions, isNull);
    });
  });
}
