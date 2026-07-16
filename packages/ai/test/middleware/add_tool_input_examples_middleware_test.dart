import 'package:pigcode_ai/pigcode_ai.dart' as ai;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

void main() {
  const prompt = <provider.LanguageModelMessage>[
    provider.UserMessage([provider.TextPart('hi')]),
  ];
  const schema = provider.JsonSchema({
    'type': 'object',
    'properties': {
      'location': {'type': 'string'},
    },
  });

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

  group('addToolInputExamplesMiddleware', () {
    test('appends examples to function tool descriptions and removes them',
        () async {
      final scripted = ScriptedModel(turns: [textTurn('ok')]);
      final wrapped = ai.wrapLanguageModel(
        scripted,
        ai.addToolInputExamplesMiddleware(),
      );

      await wrapped.doGenerate(
        const provider.LanguageModelCallOptions(
          prompt: prompt,
          tools: [
            provider.FunctionTool(
              name: 'weather',
              description: 'Get the weather',
              inputSchema: schema,
              inputExamples: [
                {'location': 'San Francisco'},
                {'location': 'London'},
              ],
            ),
          ],
        ),
      );

      final tool = scripted.receivedCallOptions.single.tools!.single
          as provider.FunctionTool;
      expect(
        tool.description,
        'Get the weather\n\n'
        'Input Examples:\n'
        '{"location":"San Francisco"}\n'
        '{"location":"London"}',
      );
      expect(tool.inputExamples, isNull);
      expect(tool.inputSchema, schema);
    });

    test('supports custom prefix, formatter, and keeping inputExamples',
        () async {
      final scripted = ScriptedModel(turns: [textTurn('ok')]);
      final wrapped = ai.wrapLanguageModel(
        scripted,
        ai.addToolInputExamplesMiddleware(
          prefix: 'Example calls:',
          format: (example, index) => '${index + 1}. ${example['location']}',
          remove: false,
        ),
      );

      await wrapped.doGenerate(
        const provider.LanguageModelCallOptions(
          prompt: prompt,
          tools: [
            provider.FunctionTool(
              name: 'weather',
              inputSchema: schema,
              inputExamples: [
                {'location': 'Paris'},
                {'location': 'Tokyo'},
              ],
            ),
          ],
        ),
      );

      final tool = scripted.receivedCallOptions.single.tools!.single
          as provider.FunctionTool;
      expect(
        tool.description,
        'Example calls:\n'
        '1. Paris\n'
        '2. Tokyo',
      );
      expect(tool.inputExamples, [
        {'location': 'Paris'},
        {'location': 'Tokyo'},
      ]);
    });

    test('leaves tools without examples and provider tools unchanged',
        () async {
      final functionTool = const provider.FunctionTool(
        name: 'search',
        description: 'Search',
        inputSchema: provider.JsonSchema({'type': 'object'}),
      );
      final providerTool = const provider.ProviderTool(
        id: 'provider.search',
        name: 'providerSearch',
        args: {'mode': 'fast'},
      );
      final scripted = ScriptedModel(turns: [textTurn('ok')]);
      final wrapped = ai.wrapLanguageModel(
        scripted,
        ai.addToolInputExamplesMiddleware(),
      );

      await wrapped.doGenerate(
        provider.LanguageModelCallOptions(
          prompt: prompt,
          tools: [functionTool, providerTool],
        ),
      );

      expect(scripted.receivedCallOptions.single.tools, [
        functionTool,
        providerTool,
      ]);
    });
  });
}
