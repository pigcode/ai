import 'package:pigcode_ai/src/generate_text/generate_text.dart';
import 'package:pigcode_ai/src/generate_text/stop_condition.dart'
    show isStepCount;
import 'package:pigcode_ai/src/generate_text/stream_text.dart';
import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

void main() {
  group('provider tool 端到端下发与执行', () {
    test('generateText 下发 provider 工具并执行 execute → tool_result 回传', () async {
      final calls = <Object?>[];
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'computer',
              input: '{"action":"screenshot"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 4),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('done')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 5),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        tools: {
          'computer': Tool.provider(
            const provider.ProviderTool(
              id: 'anthropic.computer_20250124',
              name: 'computer',
              args: <String, Object?>{
                'displayWidthPx': 1024,
                'displayHeightPx': 768,
              },
            ),
            execute: (input, options) async {
              calls.add(input);
              return 'screenshot-bytes';
            },
          ),
        },
        prompt: 'take a screenshot',
        stopWhen: isStepCount(2),
      );

      expect(calls.single, {'action': 'screenshot'});
      expect(result.text, 'done');

      final firstCallTools = model.receivedCallOptions.first.tools;
      expect(firstCallTools, isNotNull);
      final pt = firstCallTools!.whereType<provider.ProviderTool>().single;
      expect(pt.id, 'anthropic.computer_20250124');
      expect(pt.name, 'computer');
    });

    test('streamText 下发 provider 工具并执行 execute', () async {
      final calls = <Object?>[];
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'computer',
              input: '{"action":"screenshot"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 4),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('ok')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 5),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = streamText(
        model: model,
        tools: {
          'computer': Tool.provider(
            const provider.ProviderTool(
              id: 'anthropic.computer_20250124',
              name: 'computer',
              args: <String, Object?>{
                'displayWidthPx': 1024,
                'displayHeightPx': 768,
              },
            ),
            execute: (input, options) async {
              calls.add(input);
              return 'ok';
            },
          ),
        },
        prompt: 'x',
        stopWhen: isStepCount(2),
      );

      await result.stream.toList();

      expect(calls.single, {'action': 'screenshot'});

      final firstCallTools = model.receivedCallOptions.first.tools;
      expect(firstCallTools, isNotNull);
      final pt = firstCallTools!.whereType<provider.ProviderTool>().single;
      expect(pt.id, 'anthropic.computer_20250124');
      expect(pt.name, 'computer');
    });
  });
}
