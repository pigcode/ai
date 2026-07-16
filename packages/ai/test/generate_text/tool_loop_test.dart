import 'package:pigcode_ai/src/generate_text/stop_condition.dart'
    show isStepCount;
import 'package:pigcode_ai/src/generate_text/tool_loop.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

void main() {
  group('runToolLoopGenerate', () {
    test('single step text, no tools, no stopWhen', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('hello')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('hi')]),
        ],
      );

      expect(steps, hasLength(1));
      expect(steps.single.text, 'hello');
      expect(steps.single.toolCalls, isEmpty);
      expect(
        steps.single.finishReason.unified,
        provider.FinishReasonType.stop,
      );
      expect(model.callCount, 1);
    });

    test('forced tool loop: tool-call then text stop, 2 steps', () async {
      final calls = <String>[];
      final tools = <String, Tool>{
        'get_weather': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            calls.add(options.toolCallId);
            return 'sunny';
          },
        ),
      };

      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'get_weather',
              input: '{"city":"NYC"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 5),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('It is sunny in NYC.')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 8),
            outputTokens: provider.OutputTokens(total: 6),
          ),
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage(
            [provider.TextPart('What is the weather in NYC?')],
          ),
        ],
        tools: tools,
        stopWhen: isStepCount(5),
      );

      expect(steps, hasLength(2));
      expect(calls, ['call-1']);
      expect(steps.first.toolCalls, hasLength(1));
      expect(steps.first.toolResults, hasLength(1));
      expect(steps.first.toolResults.single.result, 'sunny');
      expect(steps.last.text, 'It is sunny in NYC.');
      expect(
        steps.last.finishReason.unified,
        provider.FinishReasonType.stop,
      );
    });

    test('tool execute receives messages without the system prompt', () async {
      List<provider.LanguageModelMessage>? seen;
      final tools = <String, Tool>{
        'get_weather': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            seen = options.messages;
            return 'sunny';
          },
        ),
      };

      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'get_weather',
              input: '{"city":"NYC"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 5),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('done')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 8),
            outputTokens: provider.OutputTokens(total: 6),
          ),
        ),
      ]);

      await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.SystemMessage('be terse'),
          const provider.UserMessage([provider.TextPart('weather?')]),
        ],
        tools: tools,
        stopWhen: isStepCount(5),
      );

      expect(seen, isNotNull);
      // v7:工具回调收到的 messages 不含 system prompt。
      expect(seen!.whereType<provider.SystemMessage>(), isEmpty);
      expect(seen!.whereType<provider.UserMessage>(), isNotEmpty);
    });

    test('isStepCount(1) truncates the loop after the first step', () async {
      final tools = <String, Tool>{
        'get_weather': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'sunny',
        ),
      };

      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'get_weather',
              input: '{"city":"NYC"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 5),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('unreachable')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('hi')]),
        ],
        tools: tools,
        stopWhen: isStepCount(1),
      );

      expect(steps, hasLength(1));
      expect(model.callCount, 1);
    });

    test('tool call without execute stops the loop', () async {
      final tools = <String, Tool>{
        'get_weather': const Tool(
          inputSchema: provider.JsonSchema({'type': 'object'}),
        ),
      };

      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'get_weather',
              input: '{"city":"NYC"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 5),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('hi')]),
        ],
        tools: tools,
        stopWhen: isStepCount(5),
      );

      expect(steps, hasLength(1));
      expect(steps.single.toolCalls, hasLength(1));
      expect(steps.single.toolResults, isEmpty);
      expect(model.callCount, 1);
    });

    test(
        'without stopWhen, a tool-calls finish still runs only a single '
        'step (v7: no stopWhen = single step, even with executable tool '
        'calls)', () async {
      final tools = <String, Tool>{
        'get_weather': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'sunny',
        ),
      };

      // 只脚本化一个回合:若循环误发起第二次模型调用,
      // ScriptedModel 会抛 StateError,测试即失败。
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'get_weather',
              input: '{"city":"NYC"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 5),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage(
            [provider.TextPart('What is the weather in NYC?')],
          ),
        ],
        tools: tools,
        // 故意不传 stopWhen。
      );

      expect(steps, hasLength(1));
      expect(model.callCount, 1);
      expect(steps.single.toolCalls, hasLength(1));
      expect(steps.single.toolResults, hasLength(1));
    });

    test(
        'toModelOutput returning ToolResultErrorText does not throw '
        'and yields a string tool result', () async {
      final tools = <String, Tool>{
        'get_weather': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'unused',
          toModelOutput: (input, output) =>
              const provider.ToolResultErrorText('weather service unavailable'),
        ),
      };

      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'get_weather',
              input: '{"city":"NYC"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 5),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('done')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('hi')]),
        ],
        tools: tools,
        stopWhen: isStepCount(5),
      );

      expect(steps, hasLength(2));
      expect(steps.first.toolResults, hasLength(1));
      expect(
        steps.first.toolResults.single.result,
        'weather service unavailable',
      );
    });

    test(
        'toModelOutput returning ToolResultErrorText is preserved as-is in '
        'the ToolResultPart fed into the next model turn (not flattened '
        'into ToolResultText/Json)', () async {
      final tools = <String, Tool>{
        'get_weather': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'unused',
          toModelOutput: (input, output) =>
              const provider.ToolResultErrorText('bad'),
        ),
      };

      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'get_weather',
              input: '{"city":"NYC"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 5),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('done')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('hi')]),
        ],
        tools: tools,
        stopWhen: isStepCount(5),
      );

      expect(model.receivedCallOptions, hasLength(2));
      final secondCallPrompt = model.receivedCallOptions[1].prompt;
      final toolMessage =
          secondCallPrompt.whereType<provider.ToolMessage>().single;
      final toolResultPart =
          toolMessage.content.whereType<provider.ToolResultPart>().single;

      expect(toolResultPart.output, isA<provider.ToolResultErrorText>());
      expect(
        (toolResultPart.output as provider.ToolResultErrorText).value,
        'bad',
      );
    });

    test(
        'a content item providerMetadata (e.g. openai reasoning item itemId/'
        'encryptedContent) is carried into the rebuilt assistant message fed '
        'into the next model turn (not dropped by _toAssistantMessage)',
        () async {
      final tools = <String, Tool>{
        'get_weather': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'sunny',
        ),
      };

      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ReasoningContent(
              'thinking',
              providerMetadata: {
                'openai': {
                  'itemId': 'rs_123',
                  'reasoningEncryptedContent': 'enc_abc',
                },
              },
            ),
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'get_weather',
              input: '{"city":"NYC"}',
              providerMetadata: {
                'openai': {'itemId': 'fc_1'},
              },
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 5),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('done')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage(
              [provider.TextPart('what is the weather')]),
        ],
        tools: tools,
        stopWhen: isStepCount(5),
      );

      expect(model.receivedCallOptions, hasLength(2));
      final secondCallPrompt = model.receivedCallOptions[1].prompt;
      final assistantMessage =
          secondCallPrompt.whereType<provider.AssistantMessage>().single;
      final reasoningPart =
          assistantMessage.content.whereType<provider.ReasoningPart>().single;
      final toolCallPart =
          assistantMessage.content.whereType<provider.ToolCallPart>().single;

      expect(reasoningPart.providerOptions, {
        'openai': {'itemId': 'rs_123', 'reasoningEncryptedContent': 'enc_abc'},
      });
      expect(toolCallPart.providerOptions, {
        'openai': {'itemId': 'fc_1'},
      });
    });

    test(
        'a provider-executed tool call is not re-executed locally '
        '(providerExecuted == true skips the local execute)', () async {
      var localExecuted = false;
      final tools = <String, Tool>{
        'x': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            localExecuted = true;
            return 'should not run';
          },
        ),
      };

      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'x',
              input: '{}',
              providerExecuted: true,
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('hi')]),
        ],
        tools: tools,
        // 故意不传 stopWhen:单步即可验证本地未重复执行。
      );

      expect(steps, hasLength(1));
      expect(localExecuted, isFalse);
      expect(steps.single.toolResults, isEmpty);
      expect(model.callCount, 1);
    });

    test(
        'StepResult.providerMetadata carries doGenerate result-level '
        'providerMetadata (non-streaming path)', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('hello')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
          ),
          providerMetadata: {
            'anthropic': {
              'container': {'id': 'container-1'},
            },
          },
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('hi')]),
        ],
      );

      expect(steps.single.providerMetadata, {
        'anthropic': {
          'container': {'id': 'container-1'},
        },
      });
    });
  });

  group('provider 工具自动续接(deferred)', () {
    const deferredToolCall = provider.ToolCall(
      toolCallId: 'call-1',
      toolName: 'code_exec',
      input: '{}',
      providerExecuted: true,
    );
    const deferredToolResult = provider.ToolResult(
      toolCallId: 'call-1',
      toolName: 'code_exec',
      result: 'deferred done',
    );
    const toolCallsFinish = provider.LanguageModelFinishReason(
      provider.FinishReasonType.toolCalls,
    );
    const stopFinish = provider.LanguageModelFinishReason(
      provider.FinishReasonType.stop,
    );
    const usage = provider.LanguageModelUsage(
      inputTokens: provider.InputTokens(total: 1),
      outputTokens: provider.OutputTokens(total: 1),
    );

    ToolSet deferredTools() => <String, Tool>{
          'code_exec': Tool.provider(
            const provider.ProviderTool(
              id: 'x.code_exec',
              name: 'code_exec',
              args: <String, Object?>{},
              supportsDeferredResults: true,
            ),
          ),
        };

    test(
        '① deferred 工具无同轮结果 → 续接;次轮结果到达解销后停止,'
        '次轮结果进 content,续接 prompt 无空 tool 消息', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [deferredToolCall],
          finishReason: toolCallsFinish,
          usage: usage,
        ),
        const ScriptedTurn(
          content: [deferredToolResult, provider.TextContent('done')],
          finishReason: stopFinish,
          usage: usage,
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('run code')]),
        ],
        tools: deferredTools(),
        stopWhen: isStepCount(5),
      );

      expect(steps, hasLength(2));
      expect(model.callCount, 2);
      // 跨轮 deferred 结果归位:次轮无配对 tool-call 的结果进当轮
      // StepResult.content,不抛错(维持双路静默透传的既有偏离)。
      expect(
        steps.last.content.whereType<provider.ToolResult>().single.toolCallId,
        'call-1',
      );
      // pending-only 续接的下一步 prompt:只追加 assistant 消息(其中含
      // providerExecuted 调用),无 tool role 消息。
      final secondPrompt = model.receivedCallOptions[1].prompt;
      final assistantMessage =
          secondPrompt.whereType<provider.AssistantMessage>().single;
      final toolCallPart =
          assistantMessage.content.whereType<provider.ToolCallPart>().single;
      expect(toolCallPart.toolCallId, 'call-1');
      expect(toolCallPart.providerExecuted, isTrue);
      expect(secondPrompt.whereType<provider.ToolMessage>(), isEmpty);
    });

    test('② 未标记工具无同轮结果 → 不续接(现状单步回归)', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [deferredToolCall],
          finishReason: toolCallsFinish,
          usage: usage,
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('run code')]),
        ],
        tools: <String, Tool>{
          // 同名工具但不标 supportsDeferredResults(默认 false)。
          'code_exec': Tool.provider(
            const provider.ProviderTool(
              id: 'x.code_exec',
              name: 'code_exec',
              args: <String, Object?>{},
            ),
          ),
        },
        stopWhen: isStepCount(5),
      );

      expect(steps, hasLength(1));
      expect(model.callCount, 1);
    });

    test('③ stopWhen 短路优先:pending 非空但 isStepCount(1) → 单步停止', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [deferredToolCall],
          finishReason: toolCallsFinish,
          usage: usage,
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('run code')]),
        ],
        tools: deferredTools(),
        stopWhen: isStepCount(1),
      );

      expect(steps, hasLength(1));
      expect(model.callCount, 1);
    });

    test('④ blocking(无 execute 悬置)与 pending 并存 → 仍续接(:9.4 边界)', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            deferredToolCall,
            provider.ToolCall(
              toolCallId: 'call-2',
              toolName: 'manual',
              input: '{}',
            ),
          ],
          finishReason: toolCallsFinish,
          usage: usage,
        ),
        const ScriptedTurn(
          content: [deferredToolResult, provider.TextContent('done')],
          finishReason: stopFinish,
          usage: usage,
        ),
      ]);

      final tools = deferredTools()
        ..['manual'] = const Tool(
          inputSchema: provider.JsonSchema({'type': 'object'}),
        );

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('run code')]),
        ],
        tools: tools,
        stopWhen: isStepCount(5),
      );

      expect(steps, hasLength(2));
      expect(model.callCount, 2);
    });

    test('⑤ blocking 且无 pending(deferred 结果同轮已到)→ 停止回归', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            deferredToolCall,
            deferredToolResult,
            provider.ToolCall(
              toolCallId: 'call-2',
              toolName: 'manual',
              input: '{}',
            ),
          ],
          finishReason: toolCallsFinish,
          usage: usage,
        ),
      ]);

      final tools = deferredTools()
        ..['manual'] = const Tool(
          inputSchema: provider.JsonSchema({'type': 'object'}),
        );

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('run code')]),
        ],
        tools: tools,
        stopWhen: isStepCount(5),
      );

      expect(steps, hasLength(1));
      expect(model.callCount, 1);
    });

    test('⑥ pending-only 续接的 responseMessages 只含 assistant 消息', () async {
      final observedResponseMessages = <List<ModelMessage>>[];
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [deferredToolCall],
          finishReason: toolCallsFinish,
          usage: usage,
        ),
        const ScriptedTurn(
          content: [deferredToolResult, provider.TextContent('done')],
          finishReason: stopFinish,
          usage: usage,
        ),
      ]);

      await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('run code')]),
        ],
        tools: deferredTools(),
        stopWhen: isStepCount(5),
        prepareStep: (options) {
          observedResponseMessages.add(options.responseMessages);
          return null;
        },
      );

      // 第二步 prepareStep 观测:pending-only 步只贡献一条 assistant 消息,
      // 无空 ToolModelMessage。
      expect(observedResponseMessages, hasLength(2));
      final afterPendingOnlyStep = observedResponseMessages[1];
      expect(
        afterPendingOnlyStep.whereType<AssistantModelMessage>(),
        hasLength(1),
      );
      expect(
        afterPendingOnlyStep.whereType<ToolModelMessage>(),
        isEmpty,
      );
    });

    test('⑦ pending 支不受 finishReason 闸门约束:悬置轮 stop 仍续接', () async {
      // deferred 悬置步的 finishReason 未必是 toolCalls(spec §4.2):pending
      // 支与 client-complete 支平级 OR,锁定该旁路防未来误并回
      // isToolCallsFinish 闸门。
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [deferredToolCall],
          finishReason: stopFinish,
          usage: usage,
        ),
        const ScriptedTurn(
          content: [deferredToolResult, provider.TextContent('done')],
          finishReason: stopFinish,
          usage: usage,
        ),
      ]);

      final steps = await runToolLoopGenerate(
        model: model,
        initialMessages: [
          const provider.UserMessage([provider.TextPart('run code')]),
        ],
        tools: deferredTools(),
        stopWhen: isStepCount(5),
      );

      expect(steps, hasLength(2));
      expect(model.callCount, 2);
      expect(
        steps.last.content.whereType<provider.ToolResult>().single.toolCallId,
        'call-1',
      );
    });
  });
}
