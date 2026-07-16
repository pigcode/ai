import 'package:pigcode_ai/src/agent/tool_loop_agent.dart';
import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

void main() {
  group('ToolLoopAgent', () {
    test('generate defaults to a multi-step tool loop', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'echo',
              input: '{"value":"hi"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 4),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('done')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 6),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        tools: {
          'echo': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async =>
                (input as Map<String, Object?>)['value'],
          ),
        },
      );

      final result = await agent.generate(prompt: 'call echo');

      expect(result.steps, hasLength(2));
      expect(result.text, 'done');
      expect(result.toolResults.single.result, 'hi');
      expect(model.callCount, 2);
    });

    test('generate applies settings and per-call callbacks in order', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('ok')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);
      final events = <String>[];
      final agent = ToolLoopAgent(
        model: model,
        instructions: 'agent instructions',
        headers: const {'x-agent': '1'},
        providerOptions: const {
          'openai': {'setting': 'agent'},
        },
        onStart: (event) {
          events.add('agent-start:${event.messages.length}');
        },
        onStepEnd: (step) {
          events.add('agent-step-end:${step.text}');
        },
        onEnd: (event) {
          events.add('agent-end:${event.text}');
        },
      );

      await agent.generate(
        prompt: 'hello',
        onStart: (event) {
          events.add('call-start:${event.messages.length}');
        },
        onStepEnd: (step) {
          events.add('call-step-end:${step.text}');
        },
        onEnd: (event) {
          events.add('call-end:${event.text}');
        },
      );

      final options = model.receivedCallOptions.single;
      expect(options.headers, {'x-agent': '1'});
      expect(options.providerOptions, {
        'openai': {'setting': 'agent'},
      });
      expect(options.prompt.first, isA<provider.SystemMessage>());
      expect(
        (options.prompt.first as provider.SystemMessage).content,
        'agent instructions',
      );
      expect(events, [
        'agent-start:1',
        'call-start:1',
        'agent-step-end:ok',
        'call-step-end:ok',
        'agent-end:ok',
        'call-end:ok',
      ]);
    });

    test('generate forwards per-call language model options', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('ok')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(),
            outputTokens: provider.OutputTokens(),
          ),
        ),
      ]);
      final controller = provider.CancellationController();
      final agent = ToolLoopAgent(
        model: model,
        maxOutputTokens: 10,
        temperature: 0.1,
        stopSequences: const ['agent-stop'],
        reasoning: provider.ReasoningEffort.low,
      );

      await agent.generate(
        prompt: 'hello',
        maxOutputTokens: 20,
        temperature: 0.2,
        topP: 0.3,
        topK: 0.4,
        presencePenalty: 0.5,
        frequencyPenalty: 0.6,
        seed: 7,
        stopSequences: const ['call-stop'],
        toolChoice: const provider.ToolChoiceNone(),
        reasoning: provider.ReasoningEffort.high,
        cancellation: controller.signal,
      );

      final options = model.receivedCallOptions.single;
      expect(options.maxOutputTokens, 20);
      expect(options.temperature, 0.2);
      expect(options.topP, 0.3);
      expect(options.topK, 0.4);
      expect(options.presencePenalty, 0.5);
      expect(options.frequencyPenalty, 0.6);
      expect(options.seed, 7);
      expect(options.stopSequences, ['call-stop']);
      expect(options.toolChoice, const provider.ToolChoiceNone());
      expect(options.reasoning, provider.ReasoningEffort.high);
      expect(options.cancellation, same(controller.signal));
    });

    test('generate merges agent metadata with per-call overrides', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('ok')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(),
            outputTokens: provider.OutputTokens(),
          ),
        ),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        headers: const {
          'x-agent': 'agent',
          'x-shared': 'agent',
        },
        providerOptions: const {
          'openai': {
            'outer': {
              'agent': true,
              'shared': 'agent',
              'array': [1, 2],
            },
            'agentOnly': 'yes',
          },
          'anthropic': {'cache': true},
        },
      );

      await agent.generate(
        prompt: 'hello',
        headers: const {
          'x-shared': 'call',
          'x-call': 'call',
        },
        providerOptions: const {
          'openai': {
            'outer': {
              'shared': 'call',
              'array': [3],
              'call': true,
            },
            'callOnly': 'yes',
          },
          'xai': {'reasoning': 'high'},
        },
      );

      final options = model.receivedCallOptions.single;
      expect(options.headers, {
        'x-agent': 'agent',
        'x-shared': 'call',
        'x-call': 'call',
      });
      expect(options.providerOptions, {
        'openai': {
          'outer': {
            'agent': true,
            'shared': 'call',
            'array': [3],
            'call': true,
          },
          'agentOnly': 'yes',
          'callOnly': 'yes',
        },
        'anthropic': {'cache': true},
        'xai': {'reasoning': 'high'},
      });
    });

    test('stream defaults to a multi-step tool loop', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'echo',
              input: '{"value":"hi"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 4),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('stream-done')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 6),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
      ]);
      final events = <String>[];
      final agent = ToolLoopAgent(
        model: model,
        tools: {
          'echo': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async =>
                (input as Map<String, Object?>)['value'],
          ),
        },
        onStepEnd: (step) {
          events.add('agent-step:${step.text}:${step.toolResults.length}');
        },
      );

      final result = agent.stream(
        prompt: 'call echo',
        onStepEnd: (step) {
          events.add('call-step:${step.text}:${step.toolResults.length}');
        },
      );
      await result.consumeStream();

      final steps = await result.steps;
      expect(steps, hasLength(2));
      expect(await result.text, 'stream-done');
      expect((await result.toolResults).single.result, 'hi');
      expect(model.callCount, 2);
      expect(events, [
        'agent-step::1',
        'call-step::1',
        'agent-step:stream-done:0',
        'call-step:stream-done:0',
      ]);
    });

    test('stream merges agent metadata with per-call overrides', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('stream-ok')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(),
            outputTokens: provider.OutputTokens(),
          ),
        ),
      ]);
      final controller = provider.CancellationController();
      final agent = ToolLoopAgent(
        model: model,
        headers: const {
          'x-agent': 'agent',
          'x-shared': 'agent',
        },
        providerOptions: const {
          'openai': {
            'outer': {
              'agent': true,
              'shared': 'agent',
            },
          },
        },
      );

      final result = agent.stream(
        prompt: 'hello',
        headers: const {
          'x-shared': 'call',
          'x-call': 'call',
        },
        providerOptions: const {
          'openai': {
            'outer': {
              'shared': 'call',
              'call': true,
            },
          },
        },
        cancellation: controller.signal,
      );
      await result.consumeStream();

      final options = model.receivedCallOptions.single;
      expect(options.headers, {
        'x-agent': 'agent',
        'x-shared': 'call',
        'x-call': 'call',
      });
      expect(options.providerOptions, {
        'openai': {
          'outer': {
            'agent': true,
            'shared': 'call',
            'call': true,
          },
        },
      });
      expect(options.cancellation, same(controller.signal));
    });
  });
}
