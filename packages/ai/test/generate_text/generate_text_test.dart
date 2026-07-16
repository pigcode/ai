import 'package:pigcode_ai/src/generate_text/generate_text.dart';
import 'package:pigcode_ai/src/generate_text/output.dart';
import 'package:pigcode_ai/src/generate_text/prepare_step.dart';
import 'package:pigcode_ai/src/generate_text/step_result.dart';
import 'package:pigcode_ai/src/generate_text/tool_call_repair.dart';
import 'package:pigcode_ai/src/generate_text/tool_approval.dart';
import 'package:pigcode_ai/src/prompt/content_part.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/logging.dart';
import '../support/scripted_model.dart';

bool _stopAtTwoSteps(List<StepResult> steps) => steps.length >= 2;

void main() {
  group('generateText', () {
    test('单步文本结果:聚合 text/finishReason/usage/response 均来自唯一一步', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('你好')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 10),
            outputTokens: provider.OutputTokens(total: 5),
          ),
        ),
      ]);

      final result = await generateText(model: model, prompt: '你好吗');

      expect(result.steps, hasLength(1));
      expect(result.text, '你好');
      expect(result.finalStep, same(result.steps.single));
      expect(
        result.finishReason,
        const provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop),
      );
      expect(result.usage.inputTokens.total, 10);
      expect(result.usage.outputTokens.total, 5);
      expect(result.response, isNull); // ScriptedModel 不产出 response 元数据
      expect(result.toolCalls, isEmpty);
      expect(result.toolResults, isEmpty);
      expect(result.responseMessages, hasLength(1));
      expect(result.responseMessages.single, isA<AssistantModelMessage>());
    });

    test('StepResult.performance records response and tool timings', () async {
      final tools = <String, Tool>{
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return 'ok';
          },
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'lookup',
              input: '{}',
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
      ]);

      final result = await generateText(
        model: model,
        prompt: 'run lookup',
        tools: tools,
      );
      final performance = result.finalStep.performance;

      expect(performance.responseTime, greaterThanOrEqualTo(Duration.zero));
      expect(
          performance.stepTime,
          greaterThanOrEqualTo(
            performance.responseTime,
          ));
      expect(
        performance.toolExecutionTimes,
        containsPair(
            'call-1',
            greaterThanOrEqualTo(
              const Duration(milliseconds: 5),
            )),
      );
      expect(performance.outputTokensPerSecond, isNull);
      expect(performance.inputTokensPerSecond, isNull);
      expect(performance.timeToFirstOutput, isNull);
      expect(
          performance.effectiveOutputTokensPerSecond, greaterThanOrEqualTo(0));
      expect(
          performance.effectiveTotalTokensPerSecond, greaterThanOrEqualTo(0));
    });

    test(
        'instructions、headers、providerOptions 与 onStepEnd 会透传到'
        '底层模型调用', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('收到')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(),
            outputTokens: provider.OutputTokens(),
          ),
        ),
      ]);
      final endedSteps = <StepResult>[];

      final result = await generateText(
        model: model,
        prompt: '你好',
        instructions: '你是助手',
        headers: const {'x-trace-id': 'trace-1'},
        providerOptions: const {
          'openai': {'reasoningEffort': 'low'},
        },
        onStepEnd: endedSteps.add,
      );

      expect(endedSteps, [same(result.finalStep)]);
      final options = model.receivedCallOptions.single;
      expect(options.headers, {'x-trace-id': 'trace-1'});
      expect(options.providerOptions, {
        'openai': {'reasoningEffort': 'low'},
      });
      expect(options.prompt.first, isA<provider.SystemMessage>());
      expect((options.prompt.first as provider.SystemMessage).content, '你是助手');
    });

    test('onStart/onStepStart/onEnd observe the full generate lifecycle',
        () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'ok',
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'echo',
              input: '{}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 2),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('done')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);
      final events = <String>[];

      final result = await generateText(
        model: model,
        prompt: 'hi',
        tools: tools,
        stopWhen: _stopAtTwoSteps,
        onStart: (event) {
          events.add('start:${event.messages.length}:${event.model.modelId}');
        },
        onStepStart: (event) {
          events.add(
            'step-start:${event.stepNumber}:'
            '${event.steps.length}:${event.messages.length}',
          );
        },
        onStepEnd: (step) {
          events.add('step-end:${step.text}:${step.toolResults.length}');
        },
        onEnd: (event) {
          events.add(
            'end:${event.steps.length}:${event.text}:'
            '${event.usage.inputTokens.total}:'
            '${event.content.length}:${event.toolCalls.length}:'
            '${event.toolResults.length}',
          );
        },
      );

      expect(result.text, 'done');
      expect(events, [
        'start:1:scripted-model',
        'step-start:0:0:1',
        'step-end::1',
        'step-start:1:1:3',
        'step-end:done:0',
        'end:2:done:5:2:1:1',
      ]);
    });

    test('onStart cannot mutate invocation snapshots before the first request',
        () async {
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
      final messageOpenAiOptions = <String, Object?>{'message': 'original'};
      final messageProviderOptions = <String, provider.JsonObject>{
        'openai': messageOpenAiOptions,
      };
      final partOpenAiOptions = <String, Object?>{'part': 'original'};
      final partProviderOptions = <String, provider.JsonObject>{
        'openai': partOpenAiOptions,
      };
      final sourceMessages = <ModelMessage>[
        UserModelMessage(
          <UserContentPart>[
            TextPart('hi', providerOptions: partProviderOptions),
          ],
          providerOptions: messageProviderOptions,
        ),
      ];
      final headers = {'x-trace-id': 'trace-1'};
      final nestedOptions = <String, Object?>{'level': 1};
      final openAiOptions = <String, Object?>{
        'reasoningEffort': 'low',
        'nested': nestedOptions,
      };
      final providerOptions = <String, provider.JsonObject>{
        'openai': openAiOptions,
      };
      final stopSequences = ['STOP'];
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
        ),
      };

      await generateText(
        model: model,
        messages: sourceMessages,
        headers: headers,
        providerOptions: providerOptions,
        stopSequences: stopSequences,
        tools: tools,
        onStart: (event) {
          final message = event.messages.single as UserModelMessage;
          expect(
            () => message.content.add(const TextPart('event-mutated')),
            throwsUnsupportedError,
          );
          expect(
            () => message.providerOptions!['openai']!['message'] =
                'event-mutated',
            throwsUnsupportedError,
          );
          final textPart = message.content.single as TextPart;
          expect(
            () =>
                textPart.providerOptions!['openai']!['part'] = 'event-mutated',
            throwsUnsupportedError,
          );

          (sourceMessages.single as UserModelMessage).content[0] =
              const TextPart('source-mutated');
          messageOpenAiOptions['message'] = 'source-mutated';
          partOpenAiOptions['part'] = 'source-mutated';
          headers['x-trace-id'] = 'mutated';
          openAiOptions['reasoningEffort'] = 'high';
          nestedOptions['level'] = 2;
          providerOptions['anthropic'] = {'cacheControl': true};
          stopSequences.clear();
          tools.clear();
        },
      );

      final options = model.receivedCallOptions.single;
      final prompt = options.prompt.single as provider.UserMessage;
      expect((prompt.content.single as provider.TextPart).text, 'hi');
      expect(prompt.providerOptions, {
        'openai': {'message': 'original'},
      });
      expect(
        (prompt.content.single as provider.TextPart).providerOptions,
        {
          'openai': {'part': 'original'},
        },
      );
      expect(options.headers, {'x-trace-id': 'trace-1'});
      expect(options.providerOptions, {
        'openai': {
          'reasoningEffort': 'low',
          'nested': {'level': 1},
        },
      });
      expect(options.stopSequences, ['STOP']);
      expect(
        options.tools!.whereType<provider.FunctionTool>().map((t) => t.name),
        ['echo'],
      );
    });

    test(
        'headers/providerOptions 会在调用时刻快照,后续修改 caller-owned maps '
        '不影响底层模型调用', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('收到')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(),
            outputTokens: provider.OutputTokens(),
          ),
        ),
      ]);
      final headers = {'x-trace-id': 'trace-1'};
      final nestedOptions = <String, Object?>{'level': 1};
      final listOptions = <Object?>['a'];
      final openAiOptions = <String, Object?>{
        'reasoningEffort': 'low',
        'nested': nestedOptions,
        'items': listOptions,
      };
      final providerOptions = <String, provider.JsonObject>{
        'openai': openAiOptions,
      };

      final resultFuture = generateText(
        model: model,
        prompt: '你好',
        headers: headers,
        providerOptions: providerOptions,
      );
      headers['x-trace-id'] = 'mutated';
      headers['x-extra'] = 'extra';
      openAiOptions['reasoningEffort'] = 'high';
      nestedOptions['level'] = 2;
      listOptions.add('b');
      providerOptions['anthropic'] = {'cacheControl': true};

      await resultFuture;

      final options = model.receivedCallOptions.single;
      expect(options.headers, {'x-trace-id': 'trace-1'});
      expect(options.providerOptions, {
        'openai': {
          'reasoningEffort': 'low',
          'nested': {'level': 1},
          'items': ['a'],
        },
      });
      expect(() => options.headers!['x-new'] = 'new', throwsUnsupportedError);
      final sentOpenAiOptions = options.providerOptions!['openai']!;
      expect(
        () => sentOpenAiOptions['reasoningEffort'] = 'medium',
        throwsUnsupportedError,
      );
      expect(
        () =>
            (sentOpenAiOptions['nested'] as Map<String, Object?>)['level'] = 3,
        throwsUnsupportedError,
      );
      expect(
        () => (sentOpenAiOptions['items'] as List<Object?>).add('c'),
        throwsUnsupportedError,
      );
    });

    test(
        'toModelOutput 返回 ToolResultErrorText 时,结果 API 的 '
        'ToolResult.isError 应为 true(而非默认丢失错误标记)', () async {
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
      ]);

      final result = await generateText(
        model: model,
        prompt: '天气如何',
        tools: tools,
        // 未传 stopWhen:单步收尾,结果直接可断言。
      );

      expect(result.toolResults, hasLength(1));
      expect(result.toolResults.single.isError, isTrue);
    });

    test('多步工具循环结果:顶层内容/工具/告警/usage 聚合所有步骤', () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async =>
              (input as Map<String, Object?>)['text'],
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'echo',
              input: '{"text":"回声"}',
            ),
            provider.SourceContent.url(
              id: 'source-1',
              url: 'https://example.com/source',
              title: 'source',
            ),
            provider.FileContent(
              data: provider.FileDataBase64('ZmlsZQ=='),
              mediaType: 'text/plain',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 8),
            outputTokens: provider.OutputTokens(total: 2),
          ),
          warnings: [provider.UnsupportedWarning('temperature')],
        ),
        const ScriptedTurn(
          content: [provider.TextContent('完成')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 12),
            outputTokens: provider.OutputTokens(total: 4),
          ),
          warnings: [provider.UnsupportedWarning('topK')],
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: '请用工具回声',
        tools: tools,
        stopWhen: _stopAtTwoSteps,
      );

      expect(result.steps, hasLength(2));
      expect(result.text, '完成');
      expect(result.content, hasLength(4));
      expect(result.files.single.mediaType, 'text/plain');
      expect(result.sources.single.id, 'source-1');
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.toolName, 'echo');
      expect(result.toolResults, hasLength(1));
      expect(result.toolResults.single.result, '回声');
      expect(result.warnings, [
        const provider.UnsupportedWarning('temperature'),
        const provider.UnsupportedWarning('topK'),
      ]);
      expect(result.steps.first.toolCalls, hasLength(1));
      expect(result.steps.first.toolResults, hasLength(1));
      expect(result.steps.first.toolResults.single.result, '回声');
      expect(result.usage.inputTokens.total, 20); // 8 + 12
      expect(result.usage.outputTokens.total, 6); // 2 + 4
      expect(result.responseMessages, hasLength(greaterThanOrEqualTo(2)));
    });

    test(
        'provider 侧已执行的 ToolResult 会被保留进重建的历史消息,供下一步'
        '模型请求读取(而非在 _toAssistantMessage 重建时被丢弃)', () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async =>
              (input as Map<String, Object?>)['text'],
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            // provider 侧已执行的调用及其自带结果(本地循环应跳过执行,
            // 但仍需把该结果重建进下一步的历史消息)。
            provider.ToolCall(
              toolCallId: 'call-provider',
              toolName: 'search',
              input: '{}',
              providerExecuted: true,
            ),
            provider.ToolResult(
              toolCallId: 'call-provider',
              toolName: 'search',
              result: {'hits': 3},
            ),
            // 本地可执行的调用,确保本步命中 stopWhen 之前的续接条件。
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'echo',
              input: '{"text":"回声"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 8),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('完成')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      await generateText(
        model: model,
        prompt: '搜索并回声',
        tools: tools,
        stopWhen: _stopAtTwoSteps,
      );

      expect(model.receivedCallOptions, hasLength(2));
      // 快照语义:第一次调用的 prompt 是当时的不可变快照,不因后续追加工具消息
      // 而被原地改动(若共享同一可变列表,[0].prompt 会与 [1] 一样长)。
      expect(
        model.receivedCallOptions[0].prompt.length,
        lessThan(model.receivedCallOptions[1].prompt.length),
      );
      final secondPrompt = model.receivedCallOptions[1].prompt;
      final assistantMessage =
          secondPrompt.whereType<provider.AssistantMessage>().single;
      final toolResultPart =
          assistantMessage.content.whereType<provider.ToolResultPart>().single;

      expect(toolResultPart.toolCallId, 'call-provider');
      expect(toolResultPart.toolName, 'search');
      expect(toolResultPart.output, isA<provider.ToolResultJson>());
      expect(
        (toolResultPart.output as provider.ToolResultJson).value,
        {'hits': 3},
      );
    });

    test(
        'provider 侧已执行的 ToolResult 会被保留进公开的 responseMessages,'
        '供调用方续接进下一轮请求(而非在 _stepResponseMessages 重建时被丢弃)', () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async =>
              (input as Map<String, Object?>)['text'],
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            // provider 侧已执行的调用及其自带结果(本地循环应跳过执行,
            // 但仍需把该结果重建进公开的 responseMessages)。
            provider.ToolCall(
              toolCallId: 'call-provider',
              toolName: 'search',
              input: '{}',
              providerExecuted: true,
            ),
            provider.ToolResult(
              toolCallId: 'call-provider',
              toolName: 'search',
              result: {'hits': 3},
            ),
            // 本地可执行的调用,确保本步命中 stopWhen 之前的续接条件。
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'echo',
              input: '{"text":"回声"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 8),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('完成')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: '搜索并回声',
        tools: tools,
        stopWhen: _stopAtTwoSteps,
      );

      final assistantMessage =
          result.responseMessages.whereType<AssistantModelMessage>().first;
      final toolResultPart =
          assistantMessage.content.whereType<ToolResultPart>().single;

      expect(toolResultPart.toolCallId, 'call-provider');
      expect(toolResultPart.toolName, 'search');
      expect(toolResultPart.output, isA<provider.ToolResultJson>());
      expect(
        (toolResultPart.output as provider.ToolResultJson).value,
        {'hits': 3},
      );
    });

    test(
        '内容项的 providerMetadata(如 reasoning item 的 openai itemId/'
        'encryptedContent)会被携带进 responseMessages 重建的 part.providerOptions,'
        '供工具续接请求回传(而非在 _stepResponseMessages 重建时被丢弃)', () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async =>
              (input as Map<String, Object?>)['text'],
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
              toolName: 'echo',
              input: '{"text":"回声"}',
              providerMetadata: {
                'openai': {'itemId': 'fc_1'},
              },
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 8),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('完成')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: '推理并回声',
        tools: tools,
        stopWhen: _stopAtTwoSteps,
      );

      final assistantMessage =
          result.responseMessages.whereType<AssistantModelMessage>().first;
      final reasoningPart =
          assistantMessage.content.whereType<ReasoningPart>().single;
      final toolCallPart =
          assistantMessage.content.whereType<ToolCallPart>().single;

      expect(reasoningPart.providerOptions, {
        'openai': {'itemId': 'rs_123', 'reasoningEncryptedContent': 'enc_abc'},
      });
      expect(toolCallPart.providerOptions, {
        'openai': {'itemId': 'fc_1'},
      });

      // 续接请求(第二次模型调用)的 prompt 中,重建的 assistant 消息同样
      // 携带该 providerOptions——覆盖「模型侧真正读取到什么」而非只覆盖
      // 公开的 responseMessages 快照。
      final secondPrompt = model.receivedCallOptions[1].prompt;
      final rebuiltAssistant =
          secondPrompt.whereType<provider.AssistantMessage>().single;
      final rebuiltReasoning =
          rebuiltAssistant.content.whereType<provider.ReasoningPart>().single;
      expect(rebuiltReasoning.providerOptions, {
        'openai': {'itemId': 'rs_123', 'reasoningEncryptedContent': 'enc_abc'},
      });
    });

    test('透传 prompt 字符串:标准化为单条 user 消息并转发给模型', () async {
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

      await generateText(model: model, prompt: '单条 prompt');

      final sentPrompt = model.receivedCallOptions.single.prompt;
      expect(sentPrompt, hasLength(1));
      expect(sentPrompt.single, isA<provider.UserMessage>());
    });

    test(
        'the tool set is snapshotted at loop start: clearing the caller-owned '
        'tools map while the model is running does not drop the advertised '
        'tool from execution', () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'R',
        ),
      };
      // 模型运行期间(工具循环已拍快照之后)清空 caller 的 tools map。
      final model = ToolCallOnInvokeModel(
        toolCallId: 'c1',
        toolName: 'echo',
        input: '{}',
        onInvoke: tools.clear,
      );

      final result =
          await generateText(model: model, prompt: 'x', tools: tools);

      // 快照生效:echo 仍按名命中并执行(结果 'R'),而非因原 map 被清空被当作
      // blocking 从而无结果。
      expect(result.steps.single.toolResults, hasLength(1));
      expect(result.steps.single.toolResults.single.result, 'R');
    });

    test(
        'stopWhen receives a read-only steps snapshot: a predicate that '
        'mutates it is rejected and cannot corrupt loop state', () async {
      // 一个「有 bug」的 stopWhen:试图清空收到的 steps。
      var invoked = false;
      bool clearingStop(List<StepResult> steps) {
        invoked = true;
        steps.clear();
        return true;
      }

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

      // 谓词拿到的是 List.unmodifiable 快照:clear() 抛 UnsupportedError,证明它
      // 无法改动循环内部的 steps 累加器(而非静默污染最终结果)。
      await expectLater(
        generateText(model: model, prompt: 'x', stopWhen: clearingStop),
        throwsUnsupportedError,
      );
      expect(invoked, isTrue);
    });

    test(
        'stopWhen cannot corrupt a step by mutating its inner content list: '
        'StepResult exposes frozen lists', () async {
      var invoked = false;
      bool innerMutatingStop(List<StepResult> steps) {
        invoked = true;
        steps.last.content.clear(); // 内层 content 已冻结 → UnsupportedError
        return true;
      }

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

      await expectLater(
        generateText(model: model, prompt: 'x', stopWhen: innerMutatingStop),
        throwsUnsupportedError,
      );
      expect(invoked, isTrue);
    });

    test(
        'a list-valued stopSequences is snapshotted at invocation: clearing '
        'the caller-owned list after generateText() is called does not change '
        'the stop sequences sent to the model', () async {
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
      final stopSequences = ['STOP'];
      final future =
          generateText(model: model, prompt: 'x', stopSequences: stopSequences);
      // 同步前缀已在循环开始时快照;此刻清空原列表不应影响本次请求。
      stopSequences.clear();

      await future;

      expect(model.receivedCallOptions.single.stopSequences, ['STOP']);
    });

    test(
        'ToolResultContentOutput file items keep their data payload in the '
        'flattened tool result (not just mediaType/filename)', () async {
      final tools = <String, Tool>{
        'gen_file': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'ignored',
          toModelOutput: (input, output) => provider.ToolResultContentOutput([
            provider.ToolResultFileItem(
              data: provider.FileDataBase64('AAA='),
              mediaType: 'image/png',
              filename: 'a.png',
            ),
          ]),
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'c1',
              toolName: 'gen_file',
              input: '{}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result =
          await generateText(model: model, prompt: 'x', tools: tools);
      final flattened =
          result.toolResults.single.result as Map<String, Object?>;
      final items = flattened['items'] as List<Object?>;
      final fileItem = items.single as Map<String, Object?>;

      expect(fileItem['type'], 'file');
      expect(fileItem['mediaType'], 'image/png');
      expect(fileItem['filename'], 'a.png');
      // 关键:data 载荷被保留(此前会丢失)。
      expect(fileItem['data'], provider.FileDataBase64('AAA='));
    });

    test(
        'toolApproval userApproval emits an approval request and does not '
        'execute the tool', () async {
      var executed = false;
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":"a.txt"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'delete it',
        tools: {
          'delete_file': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async {
              executed = true;
              return 'deleted';
            },
          ),
        },
        toolApproval: const {
          'delete_file': ToolApprovalStatus.userApproval,
        },
      );

      expect(executed, isFalse);
      expect(result.steps.single.toolResults, isEmpty);
      final request = result.steps.single.content
          .whereType<provider.ToolApprovalRequest>()
          .single;
      expect(request.toolCallId, 'call-delete');
      final assistant =
          result.responseMessages.whereType<AssistantModelMessage>().single;
      final requestPart =
          assistant.content.whereType<ToolApprovalRequestPart>().single;
      expect(requestPart.approvalId, request.approvalId);
      expect(requestPart.toolCallId, 'call-delete');
    });

    test(
        'per-tool toolApproval function can request user approval and does '
        'not execute the tool', () async {
      var executed = false;
      Object? receivedInput;
      SingleToolApprovalOptions? receivedOptions;
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":"a.txt"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'delete it',
        tools: {
          'delete_file': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async {
              executed = true;
              return 'deleted';
            },
          ),
        },
        toolApproval: {
          'delete_file': (
            provider.JsonValue input,
            SingleToolApprovalOptions options,
          ) {
            receivedInput = input;
            receivedOptions = options;
            return ToolApprovalStatus.userApproval;
          },
        },
      );

      expect(executed, isFalse);
      expect(receivedInput, {'path': 'a.txt'});
      expect(receivedOptions?.toolCallId, 'call-delete');
      expect(receivedOptions?.messages.single, isA<provider.UserMessage>());
      final request = result.steps.single.content
          .whereType<provider.ToolApprovalRequest>()
          .single;
      expect(request.toolCallId, 'call-delete');
    });

    test(
        'provider approval request blocks local execution until caller resumes',
        () async {
      var executed = false;
      const request = provider.ToolApprovalRequest(
        approvalId: 'provider-approval',
        toolCallId: 'call-delete',
        providerMetadata: {
          'openai': {'itemId': 'approval_item_1'},
        },
      );
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":"a.txt"}',
            ),
            request,
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'delete it',
        tools: {
          'delete_file': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async {
              executed = true;
              return 'deleted';
            },
          ),
        },
      );

      expect(executed, isFalse);
      expect(result.steps.single.toolResults, isEmpty);
      final stepRequest =
          result.steps.single.content.whereType<provider.ToolApprovalRequest>();
      expect(stepRequest, [request]);
      final assistant =
          result.responseMessages.whereType<AssistantModelMessage>().single;
      expect(
        assistant.content
            .whereType<ToolApprovalRequestPart>()
            .single
            .approvalId,
        request.approvalId,
      );
      expect(result.responseMessages.whereType<ToolModelMessage>(), isEmpty);
    });

    test('approved provider approval request reuses the provider approval id',
        () async {
      var executed = false;
      const request = provider.ToolApprovalRequest(
        approvalId: 'provider-approval',
        toolCallId: 'call-delete',
      );
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":"a.txt"}',
            ),
            request,
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'delete it',
        tools: {
          'delete_file': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async {
              executed = true;
              return 'deleted';
            },
          ),
        },
        toolApproval: const {
          'delete_file': ToolApprovalStatus.approved(),
        },
      );

      expect(executed, isTrue);
      expect(
        result.steps.single.content.whereType<provider.ToolApprovalRequest>(),
        [request],
      );
      final approvalResponse = result.steps.single.toolApprovalResponses.single;
      expect(approvalResponse.approvalId, request.approvalId);
      expect(approvalResponse.providerOptions, request.providerMetadata);
      final toolMessage =
          result.responseMessages.whereType<ToolModelMessage>().single;
      final responsePart =
          toolMessage.content.whereType<ToolApprovalResponsePart>().single;
      expect(responsePart.approvalId, request.approvalId);
      expect(responsePart.providerOptions, request.providerMetadata);
    });

    test(
        'toolApproval denied records an approval response and returns an '
        'execution-denied tool result without executing the tool', () async {
      var executed = false;
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":"a.txt"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'delete it',
        tools: {
          'delete_file': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async {
              executed = true;
              return 'deleted';
            },
          ),
        },
        toolApproval: const {
          'delete_file': ToolApprovalStatus.denied(reason: 'blocked'),
        },
      );

      expect(executed, isFalse);
      expect(result.steps.single.toolResults, hasLength(1));
      expect(result.steps.single.toolResults.single.result, 'blocked');
      expect(
        result.steps.single.toolResultOutputs.single,
        const provider.ToolResultExecutionDenied(reason: 'blocked'),
      );
      final toolMessage =
          result.responseMessages.whereType<ToolModelMessage>().single;
      final approvalResponse =
          toolMessage.content.whereType<ToolApprovalResponsePart>().single;
      expect(approvalResponse.approved, isFalse);
      expect(approvalResponse.reason, 'blocked');
      final toolResult = toolMessage.content.whereType<ToolResultPart>().single;
      expect(
        toolResult.output,
        const provider.ToolResultExecutionDenied(reason: 'blocked'),
      );
    });

    test(
        'toolApproval denied can continue and feed execution-denied results '
        'back to the next model step', () async {
      var executed = false;
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":"a.txt"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('denied handled')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'delete it',
        tools: {
          'delete_file': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async {
              executed = true;
              return 'deleted';
            },
          ),
        },
        toolApproval: const {
          'delete_file': ToolApprovalStatus.denied(reason: 'blocked'),
        },
        stopWhen: _stopAtTwoSteps,
      );

      expect(executed, isFalse);
      expect(result.steps, hasLength(2));
      expect(result.text, 'denied handled');
      final secondPrompt = model.receivedCallOptions[1].prompt;
      final toolMessage = secondPrompt.whereType<provider.ToolMessage>().single;
      expect(
        toolMessage.content.whereType<provider.ToolApprovalResponsePart>(),
        hasLength(1),
      );
      expect(
        toolMessage.content.whereType<provider.ToolResultPart>().single.output,
        const provider.ToolResultExecutionDenied(reason: 'blocked'),
      );
    });

    test(
        'a resumed approved ToolApprovalResponsePart executes the matching '
        'tool before the next model call and feeds the result into prompt',
        () async {
      final executions = <Object?>[];
      late List<provider.LanguageModelMessage> executeMessages;
      final firstModel = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":"a.txt"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);
      final tools = <String, Tool>{
        'delete_file': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            executions.add(input);
            executeMessages = options.messages;
            return 'deleted';
          },
        ),
      };

      final first = await generateText(
        model: firstModel,
        prompt: 'delete it',
        tools: tools,
        toolApproval: const {
          'delete_file': ToolApprovalStatus.userApproval,
        },
      );
      final approvalId = first.responseMessages
          .whereType<AssistantModelMessage>()
          .single
          .content
          .whereType<ToolApprovalRequestPart>()
          .single
          .approvalId;
      expect(executions, isEmpty);

      final secondModel = ScriptedModel(turns: [
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

      final second = await generateText(
        model: secondModel,
        messages: [
          UserModelMessage.text('delete it'),
          ...first.responseMessages,
          ToolModelMessage([
            ToolApprovalResponsePart(
              approvalId: approvalId,
              approved: true,
              reason: 'ok',
            ),
          ]),
        ],
        tools: tools,
      );

      expect(second.text, 'done');
      expect(executions, [
        {'path': 'a.txt'},
      ]);
      expect(executeMessages, hasLength(1));
      expect(executeMessages.single, isA<provider.UserMessage>());
      final prompt = secondModel.receivedCallOptions.single.prompt;
      final toolMessage = prompt.whereType<provider.ToolMessage>().last;
      final toolResult =
          toolMessage.content.whereType<provider.ToolResultPart>().single;
      expect(toolResult.toolCallId, 'call-delete');
      expect(toolResult.toolName, 'delete_file');
      expect(toolResult.output, const provider.ToolResultText('deleted'));
      final responseToolMessage =
          second.responseMessages.whereType<ToolModelMessage>().single;
      expect(
        responseToolMessage.content.whereType<ToolResultPart>().single.output,
        const provider.ToolResultText('deleted'),
      );
    });

    test(
        'resumed approved tool approval repairs invalid input before executing',
        () async {
      var repairCalled = false;
      final executions = <Object?>[];
      final firstModel = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":1}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final first = await generateText(
        model: firstModel,
        prompt: 'delete it',
        tools: {
          'delete_file': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async => 'unused',
          ),
        },
        toolApproval: const {
          'delete_file': ToolApprovalStatus.userApproval,
        },
      );
      final approvalId = first.responseMessages
          .whereType<AssistantModelMessage>()
          .single
          .content
          .whereType<ToolApprovalRequestPart>()
          .single
          .approvalId;
      final secondModel = ScriptedModel(turns: [
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

      await generateText(
        model: secondModel,
        messages: [
          UserModelMessage.text('delete it'),
          ...first.responseMessages,
          ToolModelMessage([
            ToolApprovalResponsePart(
              approvalId: approvalId,
              approved: true,
              reason: 'ok',
            ),
          ]),
        ],
        tools: {
          'delete_file': Tool(
            inputSchema: const provider.JsonSchema({
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
              },
              'required': ['path'],
            }),
            execute: (input, options) async {
              executions.add(input);
              return 'deleted';
            },
          ),
        },
        repairToolCall: (options) {
          repairCalled = true;
          expect(options.error, isA<InvalidToolInputError>());
          return provider.ToolCall(
            toolCallId: options.toolCall.toolCallId,
            toolName: options.toolCall.toolName,
            input: '{"path":"a.txt"}',
          );
        },
      );

      expect(repairCalled, isTrue);
      expect(executions, [
        {'path': 'a.txt'},
      ]);
    });

    test(
        'resumed approval recheck input mutations do not change executed input',
        () async {
      final executions = <Object?>[];
      final approvalInputs = <Object?>[];
      final firstModel = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":"a.txt"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);
      final tools = <String, Tool>{
        'delete_file': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            executions.add(input);
            return 'deleted';
          },
        ),
      };

      final first = await generateText(
        model: firstModel,
        prompt: 'delete it',
        tools: tools,
        toolApproval: const {
          'delete_file': ToolApprovalStatus.userApproval,
        },
      );
      final approvalId = first.responseMessages
          .whereType<AssistantModelMessage>()
          .single
          .content
          .whereType<ToolApprovalRequestPart>()
          .single
          .approvalId;

      final secondModel = ScriptedModel(turns: [
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

      await generateText(
        model: secondModel,
        messages: [
          UserModelMessage.text('delete it'),
          ...first.responseMessages,
          ToolModelMessage([
            ToolApprovalResponsePart(
              approvalId: approvalId,
              approved: true,
              reason: 'client approved',
            ),
          ]),
        ],
        tools: tools,
        toolApproval: {
          'delete_file': (
            provider.JsonValue input,
            SingleToolApprovalOptions options,
          ) {
            final inputMap = input as Map<String, Object?>;
            inputMap['path'] = 'b.txt';
            approvalInputs.add(Map<String, Object?>.from(inputMap));
            return const ToolApprovalStatus.approved(reason: 'still allowed');
          },
        },
      );

      expect(approvalInputs, [
        {'path': 'b.txt'},
      ]);
      expect(executions, [
        {'path': 'a.txt'},
      ]);
    });

    test(
        'provider-executed resumed approval is forwarded without local '
        'tool execution', () async {
      final model = ScriptedModel(turns: [
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

      final result = await generateText(
        model: model,
        messages: [
          UserModelMessage.text('search it'),
          const AssistantModelMessage([
            ToolCallPart(
              toolCallId: 'call-mcp',
              toolName: 'mcp.search',
              input: {'query': 'dart ai sdk'},
              providerExecuted: true,
            ),
            ToolApprovalRequestPart(
              approvalId: 'approval-1',
              toolCallId: 'call-mcp',
            ),
          ]),
          const ToolModelMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval-1',
              approved: true,
              reason: 'client approved',
            ),
          ]),
        ],
      );

      expect(result.text, 'done');
      final prompt = model.receivedCallOptions.single.prompt;
      final toolMessage = prompt.whereType<provider.ToolMessage>().single;
      expect(
        toolMessage.content.whereType<provider.ToolApprovalResponsePart>(),
        hasLength(1),
      );
      expect(toolMessage.content.whereType<provider.ToolResultPart>(), isEmpty);
    });

    test(
        'provider-executed approval request uses toolApproval without local '
        'tool execution', () async {
      const approvalMetadata = {
        'openai': {'itemId': 'approval-1'},
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-mcp',
              toolName: 'mcp.search',
              input: '{"query":"dart ai sdk"}',
              providerExecuted: true,
              isDynamic: true,
              providerMetadata: approvalMetadata,
            ),
            provider.ToolApprovalRequest(
              approvalId: 'approval-1',
              toolCallId: 'call-mcp',
              providerMetadata: approvalMetadata,
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
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

      final result = await generateText(
        model: model,
        prompt: 'search it',
        toolApproval: const {
          'mcp.search': ToolApprovalStatus.approved(reason: 'allowed'),
        },
        stopWhen: _stopAtTwoSteps,
      );

      expect(result.text, 'done');
      expect(result.steps, hasLength(2));
      expect(result.steps.first.toolResults, isEmpty);
      final approvalResponse = result.steps.first.toolApprovalResponses.single;
      expect(approvalResponse.approved, isTrue);
      expect(approvalResponse.reason, 'allowed');
      expect(approvalResponse.providerOptions, approvalMetadata);

      expect(model.receivedCallOptions, hasLength(2));
      final toolMessage = model.receivedCallOptions[1].prompt
          .whereType<provider.ToolMessage>()
          .single;
      expect(
        toolMessage.content.whereType<provider.ToolApprovalResponsePart>(),
        hasLength(1),
      );
      expect(toolMessage.content.whereType<provider.ToolResultPart>(), isEmpty);
    });

    test('resumed approved tool approval is rechecked against current policy',
        () async {
      final executions = <Object?>[];
      final firstModel = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":"a.txt"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);
      final tools = <String, Tool>{
        'delete_file': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            executions.add(input);
            return 'deleted';
          },
        ),
      };

      final first = await generateText(
        model: firstModel,
        prompt: 'delete it',
        tools: tools,
        toolApproval: const {
          'delete_file': ToolApprovalStatus.userApproval,
        },
      );
      final approvalId = first.responseMessages
          .whereType<AssistantModelMessage>()
          .single
          .content
          .whereType<ToolApprovalRequestPart>()
          .single
          .approvalId;
      final secondModel = ScriptedModel(turns: [
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

      final second = await generateText(
        model: secondModel,
        messages: [
          UserModelMessage.text('delete it'),
          ...first.responseMessages,
          ToolModelMessage([
            ToolApprovalResponsePart(
              approvalId: approvalId,
              approved: true,
              reason: 'client approved',
            ),
          ]),
        ],
        tools: tools,
        toolApproval: const {
          'delete_file': ToolApprovalStatus.denied(reason: 'policy changed'),
        },
      );

      expect(second.text, 'done');
      expect(executions, isEmpty);
      final prompt = secondModel.receivedCallOptions.single.prompt;
      final toolMessage = prompt.whereType<provider.ToolMessage>().last;
      final toolResult =
          toolMessage.content.whereType<provider.ToolResultPart>().single;
      expect(toolResult.toolCallId, 'call-delete');
      expect(
        toolResult.output,
        const provider.ToolResultExecutionDenied(reason: 'policy changed'),
      );
      final responseToolMessage =
          second.responseMessages.whereType<ToolModelMessage>().single;
      expect(
        responseToolMessage.content.whereType<ToolResultPart>().single.output,
        const provider.ToolResultExecutionDenied(reason: 'policy changed'),
      );
    });

    test(
        'resumed approval recheck does not reuse approval reason when current '
        'denial has no reason', () async {
      final model = ScriptedModel(turns: [
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
      final tools = <String, Tool>{
        'delete_file': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            fail('denied resumed approvals must not execute tools');
          },
        ),
      };

      final result = await generateText(
        model: model,
        messages: [
          UserModelMessage.text('delete it'),
          const AssistantModelMessage([
            ToolCallPart(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: {'path': 'a.txt'},
            ),
            ToolApprovalRequestPart(
              approvalId: 'approval-1',
              toolCallId: 'call-delete',
            ),
          ]),
          const ToolModelMessage([
            ToolApprovalResponsePart(
              approvalId: 'approval-1',
              approved: true,
              reason: 'client approved',
            ),
          ]),
        ],
        tools: tools,
        toolApproval: const {
          'delete_file': ToolApprovalStatus.denied(),
        },
      );

      expect(result.text, 'done');
      final prompt = model.receivedCallOptions.single.prompt;
      final toolMessage = prompt.whereType<provider.ToolMessage>().last;
      expect(
        toolMessage.content.whereType<provider.ToolResultPart>().single.output,
        const provider.ToolResultExecutionDenied(),
      );
      final responseToolMessage =
          result.responseMessages.whereType<ToolModelMessage>().single;
      expect(
        responseToolMessage.content.whereType<ToolResultPart>().single.output,
        const provider.ToolResultExecutionDenied(),
      );
    });

    test('approved resumed tool approval fails when the tool is unavailable',
        () async {
      final firstModel = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":"a.txt"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final first = await generateText(
        model: firstModel,
        prompt: 'delete it',
        tools: {
          'delete_file': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async => 'deleted',
          ),
        },
        toolApproval: const {
          'delete_file': ToolApprovalStatus.userApproval,
        },
      );
      final approvalId = first.responseMessages
          .whereType<AssistantModelMessage>()
          .single
          .content
          .whereType<ToolApprovalRequestPart>()
          .single
          .approvalId;
      final secondModel = ScriptedModel(turns: [
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

      await expectLater(
        generateText(
          model: secondModel,
          messages: [
            UserModelMessage.text('delete it'),
            ...first.responseMessages,
            ToolModelMessage([
              ToolApprovalResponsePart(
                approvalId: approvalId,
                approved: true,
              ),
            ]),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'representable non-text content (reasoning/file/reasoning-file/custom) '
        'is reconstructed into the next turn assistant prompt message',
        () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'r',
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ReasoningContent('thinking'),
            provider.FileContent(
              data: provider.FileDataBase64('AAA='),
              mediaType: 'image/png',
            ),
            provider.ReasoningFileContent(
              data: provider.FileDataBase64('BBB='),
              mediaType: 'application/json',
            ),
            provider.CustomContentBlock('ns.custom'),
            provider.ToolCall(toolCallId: 'c1', toolName: 'echo', input: '{}'),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
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

      await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        stopWhen: _stopAtTwoSteps,
      );

      // 第二次调用的 prompt 含 step1 重建的 assistant 消息,非文本内容被保留。
      final assistant = model.receivedCallOptions[1].prompt
          .whereType<provider.AssistantMessage>()
          .single;

      expect(
        assistant.content.whereType<provider.ReasoningPart>().single.text,
        'thinking',
      );
      final filePart = assistant.content.whereType<provider.FilePart>().single;
      expect(filePart.mediaType, 'image/png');
      expect(filePart.data, provider.FileDataBase64('AAA='));
      final reasoningFile =
          assistant.content.whereType<provider.ReasoningFilePart>().single;
      expect(reasoningFile.mediaType, 'application/json');
      expect(
        assistant.content.whereType<provider.CustomPart>().single.kind,
        'ns.custom',
      );
    });

    test(
        'representable non-text content (reasoning/file/reasoning-file/custom) '
        'is preserved in the public responseMessages continuation path',
        () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ReasoningContent('thinking'),
            provider.FileContent(
              data: provider.FileDataBase64('AAA='),
              mediaType: 'image/png',
            ),
            provider.ReasoningFileContent(
              data: provider.FileDataBase64('BBB='),
              mediaType: 'application/json',
            ),
            provider.CustomContentBlock('ns.custom'),
            provider.TextContent('answer'),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(model: model, prompt: 'x');

      // 公开续接路径:responseMessages 的 assistant 消息保留非文本 part
      // (用户面类型,供调用方直接续接进下一轮请求)。
      final assistant =
          result.responseMessages.whereType<AssistantModelMessage>().single;
      expect(
        assistant.content.whereType<ReasoningPart>().single.text,
        'thinking',
      );
      final filePart = assistant.content.whereType<FilePart>().single;
      expect(filePart.mediaType, 'image/png');
      expect(filePart.data, const DataBase64('AAA='));
      final reasoningFile =
          assistant.content.whereType<ReasoningFilePart>().single;
      expect(reasoningFile.mediaType, 'application/json');
      expect(reasoningFile.data, const DataBase64('BBB='));
      expect(
        assistant.content.whereType<CustomPart>().single.kind,
        'ns.custom',
      );
    });

    test(
        'the advertised tools list on call options is frozen: a provider or '
        'middleware cannot mutate it in place and pollute later steps',
        () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'r',
        ),
      };
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

      await generateText(model: model, prompt: 'x', tools: tools);

      // provider/中间件对 options.tools 的原地改动会响亮失败,而非静默污染
      // 后续步的广告集。
      final sentTools = model.receivedCallOptions.single.tools!;
      expect(() => sentTools.clear(), throwsUnsupportedError);
    });

    test('activeTools limits the tools advertised to the model', () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'echoed',
        ),
        'search': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'searched',
        ),
      };
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

      await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        activeTools: const ['echo'],
      );

      expect(
        model.receivedCallOptions.single.tools!
            .whereType<provider.FunctionTool>()
            .map((tool) => tool.name),
        ['echo'],
      );
    });

    test('activeTools drops stale forced tool choices', () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'echoed',
        ),
        'search': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'searched',
        ),
      };
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

      await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        activeTools: const ['echo'],
        toolChoice: const provider.ToolChoiceTool('search'),
      );

      expect(model.receivedCallOptions.single.toolChoice, isNull);
    });

    test('toolOrder sends listed tools first and appends the rest by name',
        () async {
      final tools = <String, Tool>{
        'zebra': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'zebra',
        ),
        'alpha': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'alpha',
        ),
        'middle': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'middle',
        ),
      };
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

      await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        toolOrder: const ['middle'],
      );

      expect(
        model.receivedCallOptions.single.tools!
            .whereType<provider.FunctionTool>()
            .map((tool) => tool.name),
        ['middle', 'alpha', 'zebra'],
      );
    });

    test('prepareStep can change active tools between steps', () async {
      final tools = <String, Tool>{
        'search': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'search result',
        ),
        'analyze': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'analysis',
        ),
      };
      final seenStepNumbers = <int>[];
      final seenStepCounts = <int>[];
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'search',
              input: '{}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
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

      await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        stopWhen: _stopAtTwoSteps,
        prepareStep: (options) {
          seenStepNumbers.add(options.stepNumber);
          seenStepCounts.add(options.steps.length);
          return PrepareStepResult(
            activeTools:
                options.stepNumber == 0 ? const ['search'] : const ['analyze'],
          );
        },
      );

      expect(seenStepNumbers, [0, 1]);
      expect(seenStepCounts, [0, 1]);
      expect(
        model.receivedCallOptions[0].tools!
            .whereType<provider.FunctionTool>()
            .map((tool) => tool.name),
        ['search'],
      );
      expect(
        model.receivedCallOptions[1].tools!
            .whereType<provider.FunctionTool>()
            .map((tool) => tool.name),
        ['analyze'],
      );
    });

    test('prepareStep can override tool order for the current step', () async {
      final tools = <String, Tool>{
        'zebra': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'zebra',
        ),
        'alpha': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'alpha',
        ),
        'middle': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'middle',
        ),
      };
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

      await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        prepareStep: (options) => PrepareStepResult(
          toolOrder: const ['middle'],
        ),
      );

      expect(
        model.receivedCallOptions.single.tools!
            .whereType<provider.FunctionTool>()
            .map((tool) => tool.name),
        ['middle', 'alpha', 'zebra'],
      );
    });

    test('runtime and tool contexts carry forward through prepareStep',
        () async {
      final toolContexts = <Object?>[];
      final tools = <String, Tool>{
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          contextSchema: const provider.JsonSchema({
            'type': 'object',
            'properties': {
              'apiKey': {'type': 'string'},
            },
            'required': ['apiKey'],
          }),
          execute: (input, options) async {
            toolContexts.add(options.context);
            return 'lookup result';
          },
        ),
      };
      final seenRuntimeContexts = <Map<String, Object?>>[];
      final seenToolsContexts = <Map<String, Object?>>[];
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'lookup',
              input: '{}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
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

      final result = await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        runtimeContext: const {'phase': 'initial'},
        toolsContext: const {
          'lookup': {'apiKey': 'initial-key'},
        },
        stopWhen: _stopAtTwoSteps,
        prepareStep: (options) {
          seenRuntimeContexts.add(options.runtimeContext);
          seenToolsContexts.add(options.toolsContext);
          return switch (options.stepNumber) {
            0 => PrepareStepResult(
                runtimeContext: const {'phase': 'tool'},
                toolsContext: const {
                  'lookup': {'apiKey': 'tool-key'},
                },
              ),
            1 => PrepareStepResult(
                runtimeContext: const {'phase': 'final'},
              ),
            _ => null,
          };
        },
      );

      expect(seenRuntimeContexts, const [
        {'phase': 'initial'},
        {'phase': 'tool'},
      ]);
      expect(seenToolsContexts, const [
        {
          'lookup': {'apiKey': 'initial-key'},
        },
        {
          'lookup': {'apiKey': 'tool-key'},
        },
      ]);
      expect(toolContexts, const [
        {'apiKey': 'tool-key'},
      ]);
      expect(result.steps[0].runtimeContext, const {'phase': 'tool'});
      expect(result.steps[0].toolsContext, const {
        'lookup': {'apiKey': 'tool-key'},
      });
      expect(result.finalStep.runtimeContext, const {'phase': 'final'});
      expect(result.finalStep.toolsContext, const {
        'lookup': {'apiKey': 'tool-key'},
      });
    });

    test('tool context schema is validated before execution', () async {
      var executed = false;
      final tools = <String, Tool>{
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          contextSchema: const provider.JsonSchema({
            'type': 'object',
            'properties': {
              'apiKey': {'type': 'string'},
            },
            'required': ['apiKey'],
          }),
          execute: (input, options) async {
            executed = true;
            return 'lookup result';
          },
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'lookup',
              input: '{}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      await expectLater(
        generateText(
          model: model,
          prompt: 'x',
          tools: tools,
          toolsContext: const {
            'lookup': {'apiKey': 123},
          },
        ),
        throwsA(isA<provider.TypeValidationError>()),
      );
      expect(executed, isFalse);
    });

    test('repairToolCall can repair malformed JSON before execution', () async {
      provider.JsonValue? executedInput;
      ToolCallRepairOptions? seenOptions;
      final tools = <String, Tool>{
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
            'required': ['city'],
          }),
          execute: (input, options) async {
            executedInput = input;
            return 'sunny';
          },
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'lookup',
              input: 'not json',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        instructions: 'use tools carefully',
        prompt: 'weather?',
        tools: tools,
        repairToolCall: (options) async {
          seenOptions = options;
          expect(options.instructions, 'use tools carefully');
          expect(options.messages, hasLength(1));
          expect(options.toolCall.toolName, 'lookup');
          expect(options.toolCall.input, 'not json');
          expect(options.tools, equals(tools));
          expect(options.inputSchema(toolName: 'lookup'),
              tools['lookup']!.inputSchema);
          expect(options.error, isA<InvalidToolInputError>());
          return const provider.ToolCall(
            toolCallId: 'call-1',
            toolName: 'lookup',
            input: '{"city":"Paris"}',
          );
        },
      );

      expect(seenOptions, isNotNull);
      expect(executedInput, {'city': 'Paris'});
      expect(result.toolCalls.single.input, '{"city":"Paris"}');
      expect(result.toolResults.single.result, 'sunny');
    });

    test('repairToolCall repairs input before dynamic tool approval', () async {
      provider.JsonValue? approvalInput;
      provider.JsonValue? executedInput;
      final tools = <String, Tool>{
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
            'required': ['city'],
          }),
          execute: (input, options) async {
            executedInput = input;
            return 'approved';
          },
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'lookup',
              input: 'not json',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        toolApproval: {
          'lookup':
              (provider.JsonValue input, SingleToolApprovalOptions options) {
            approvalInput = input;
            return const ToolApprovalStatus.approved(reason: 'ok');
          },
        },
        repairToolCall: (options) => const provider.ToolCall(
          toolCallId: 'call-1',
          toolName: 'lookup',
          input: '{"city":"Paris"}',
        ),
      );

      expect(approvalInput, {'city': 'Paris'});
      expect(executedInput, {'city': 'Paris'});
      expect(result.toolResults.single.result, 'approved');
    });

    test('repairToolCall repairs input before global tool approval', () async {
      String? approvalInput;
      provider.JsonValue? executedInput;
      final tools = <String, Tool>{
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            executedInput = input;
            return 'approved';
          },
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'lookup',
              input: 'not json',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        toolApproval: (ToolApprovalOptions options) {
          approvalInput = options.toolCall.input;
          return const ToolApprovalStatus.approved(reason: 'ok');
        },
        repairToolCall: (options) => const provider.ToolCall(
          toolCallId: 'call-1',
          toolName: 'lookup',
          input: '{"city":"Paris"}',
        ),
      );

      expect(approvalInput, '{"city":"Paris"}');
      expect(executedInput, {'city': 'Paris'});
      expect(result.toolResults.single.result, 'approved');
    });

    test('repairToolCall surfaces repaired unknown tool names', () async {
      final tools = <String, Tool>{
        'known_tool': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'unused',
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'unknown_tool',
              input: '{}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      await expectLater(
        generateText(
          model: model,
          prompt: 'x',
          tools: tools,
          repairToolCall: (options) => provider.ToolCall(
            toolCallId: options.toolCall.toolCallId,
            toolName: 'still_unknown',
            input: '{}',
          ),
        ),
        throwsA(
          isA<NoSuchToolError>()
              .having((error) => error.toolName, 'toolName', 'still_unknown'),
        ),
      );
    });

    test('repairToolCall rechecks approval after changing tool identity',
        () async {
      var safeExecuted = false;
      var deleteExecuted = false;
      final tools = <String, Tool>{
        'safe_tool': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            safeExecuted = true;
            return 'safe';
          },
        ),
        'delete_file': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            deleteExecuted = true;
            return 'deleted';
          },
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'safe_tool',
              input: 'not json',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        toolApproval: {
          'delete_file': const ToolApprovalStatus.denied(reason: 'dangerous'),
        },
        repairToolCall: (options) => provider.ToolCall(
          toolCallId: options.toolCall.toolCallId,
          toolName: 'delete_file',
          input: '{}',
        ),
      );

      expect(safeExecuted, isFalse);
      expect(deleteExecuted, isFalse);
      expect(result.toolCalls.single.toolName, 'delete_file');
      expect(result.toolResults.single.toolName, 'delete_file');
      expect(result.toolResults.single.result, 'dangerous');
    });

    test('toolApproval userApproval is resolved after repairToolCall parsing',
        () async {
      var repairCalled = false;
      final tools = <String, Tool>{
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'unused',
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'lookup',
              input: 'not json',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        toolApproval: {
          'lookup': ToolApprovalStatus.userApproval,
        },
        repairToolCall: (options) {
          repairCalled = true;
          return const provider.ToolCall(
            toolCallId: 'call-1',
            toolName: 'lookup',
            input: '{}',
          );
        },
      );
      final assistant =
          result.responseMessages.whereType<AssistantModelMessage>().single;

      expect(repairCalled, isTrue);
      expect(result.toolCalls.single.input, '{}');
      expect(result.toolResults, isEmpty);
      expect(assistant.content.whereType<ToolCallPart>().single.input,
          <String, Object?>{});
    });

    test('repairToolCall does not repair non-executable tool calls', () async {
      var repairCalled = false;
      final tools = <String, Tool>{
        'client_tool': const Tool(
          inputSchema: provider.JsonSchema({'type': 'object'}),
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'client_tool',
              input: 'not json',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        repairToolCall: (options) {
          repairCalled = true;
          return const provider.ToolCall(
            toolCallId: 'call-1',
            toolName: 'client_tool',
            input: '{}',
          );
        },
      );

      expect(repairCalled, isFalse);
      expect(result.toolCalls.single.input, 'not json');
      expect(result.toolResults, isEmpty);
      expect(
        result.finishReason.unified,
        provider.FinishReasonType.toolCalls,
      );
    });

    test('toolApproval denial is resolved before repairToolCall parsing',
        () async {
      var repairCalled = false;
      final tools = <String, Tool>{
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'unused',
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'lookup',
              input: 'not json',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        toolApproval: {
          'lookup': const ToolApprovalStatus.denied(reason: 'blocked'),
        },
        repairToolCall: (options) {
          repairCalled = true;
          return const provider.ToolCall(
            toolCallId: 'call-1',
            toolName: 'lookup',
            input: '{}',
          );
        },
      );

      expect(repairCalled, isFalse);
      expect(result.toolResults.single.result, 'blocked');
    });

    test('prepareStep messages override becomes the next step prompt',
        () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'echoed',
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'echo',
              input: '{}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
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

      await generateText(
        model: model,
        prompt: 'original',
        tools: tools,
        stopWhen: _stopAtTwoSteps,
        prepareStep: (options) {
          if (options.stepNumber != 1) {
            return null;
          }
          return PrepareStepResult(
            messages: [
              UserModelMessage.text('compacted'),
            ],
          );
        },
      );

      final secondPrompt = model.receivedCallOptions[1].prompt;
      expect(secondPrompt, hasLength(1));
      final user = secondPrompt.single as provider.UserMessage;
      expect((user.content.single as provider.TextPart).text, 'compacted');
    });

    test(
        'prompt message content lists are frozen: a provider or middleware '
        'cannot mutate message internals shared across steps', () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'r',
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(toolCallId: 'c1', toolName: 'echo', input: '{}'),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
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

      await generateText(
        model: model,
        prompt: 'x',
        tools: tools,
        stopWhen: _stopAtTwoSteps,
      );

      // 第二次调用的 prompt 含 user/assistant/tool 三类消息;其内容列表均已在
      // 构造处冻结,原地改动响亮失败,不会污染循环历史或已保留的快照。
      final secondPrompt = model.receivedCallOptions[1].prompt;
      final user = secondPrompt.whereType<provider.UserMessage>().single;
      expect(() => user.content.clear(), throwsUnsupportedError);
      final assistant =
          secondPrompt.whereType<provider.AssistantMessage>().single;
      expect(() => assistant.content.clear(), throwsUnsupportedError);
      final toolMessage = secondPrompt.whereType<provider.ToolMessage>().single;
      expect(() => toolMessage.content.clear(), throwsUnsupportedError);
    });

    test(
        'GenerateTextResult.steps is frozen: a caller cannot mutate the '
        'returned list and silently change the derived aggregates', () async {
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

      final result = await generateText(model: model, prompt: 'x');

      // 与流式结果的不可变 steps 快照对齐:返回后结果稳定,改动响亮失败。
      expect(() => result.steps.clear(), throwsUnsupportedError);
    });

    test(
        'provider warnings from doGenerate are preserved on '
        'StepResult.warnings and the top-level result.warnings', () async {
      final records = captureWarningLogs();
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
          warnings: [provider.UnsupportedWarning('topK')],
        ),
      ]);

      final result = await generateText(model: model, prompt: 'x');

      // 非流式调用方可感知被忽略/降级的选项(与流式 StartStepPart.warnings
      // 对称;此前建步时被丢弃)。
      expect(
        result.steps.single.warnings,
        [const provider.UnsupportedWarning('topK')],
      );
      expect(
        result.warnings,
        [const provider.UnsupportedWarning('topK')],
      );
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning (scripted / scripted-model): '
            'The feature "topK" is not supported.',
      ]);
    });

    test(
        'a tool returning null keeps null in toolResults.result '
        '(not coerced to an empty object)', () async {
      final tools = <String, Tool>{
        'nullable': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => null,
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'c1',
              toolName: 'nullable',
              input: '{}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result =
          await generateText(model: model, prompt: 'x', tools: tools);

      // null 是合法工具结果(v7 JSONValue 含 null):原样保留,不再被
      // 规范化成 {} 导致与 responseMessages 观察到的输出不一致。
      expect(result.toolResults, hasLength(1));
      expect(result.toolResults.single.result, isNull);
    });

    test('empty tool input is normalized for response messages', () async {
      provider.JsonValue? executedInput;
      final tools = <String, Tool>{
        'no_args': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            executedInput = input;
            return 'done';
          },
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'c1',
              toolName: 'no_args',
              input: '  ',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result =
          await generateText(model: model, prompt: 'x', tools: tools);
      final assistant =
          result.responseMessages.whereType<AssistantModelMessage>().single;

      expect(executedInput, <String, Object?>{});
      expect(result.toolCalls.single.input, '{}');
      expect(assistant.content.whereType<ToolCallPart>().single.input,
          <String, Object?>{});
    });
  });

  group('generateText output', () {
    test('defaults output to text', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('hello')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(model: model, prompt: 'say hello');

      expect(result.text, 'hello');
      expect(result.output, 'hello');
      expect(model.receivedCallOptions.single.responseFormat, isNull);
    });

    test('object output sends json response format and parses final text',
        () async {
      const schema = provider.JsonSchema({
        'type': 'object',
        'properties': {
          'value': {'type': 'string'},
        },
        'required': ['value'],
        'additionalProperties': false,
      });
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('{"value":"ok"}')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'make object',
        output: Output.object(schema: schema),
      );

      expect(result.text, '{"value":"ok"}');
      expect(result.output, {'value': 'ok'});
      final format = model.receivedCallOptions.single.responseFormat;
      expect(format, isA<provider.ResponseFormatJson>());
      expect((format as provider.ResponseFormatJson).schema, schema);
    });

    test('json output preserves a null completion value', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('null')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'make json null',
        output: Output.json(),
      );

      expect(result.output, isNull);
      expect(
        model.receivedCallOptions.single.responseFormat,
        isA<provider.ResponseFormatJson>(),
      );
    });

    test('does not parse output when final finish reason is toolCalls',
        () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'tool',
              input: '{}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'call tool',
        output: Output.object(
          schema: const provider.JsonSchema({'type': 'object'}),
        ),
      );

      expect(
        () => result.output,
        throwsA(isA<provider.NoOutputGeneratedError>()),
      );
    });

    test('does not parse output when final finish reason is length', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('truncated')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.length,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'say hello',
      );

      expect(
        () => result.output,
        throwsA(isA<provider.NoOutputGeneratedError>()),
      );
    });

    test('does not parse output when final finish reason is contentFilter',
        () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('filtered')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.contentFilter,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = await generateText(
        model: model,
        prompt: 'say hello',
      );

      expect(
        () => result.output,
        throwsA(isA<provider.NoOutputGeneratedError>()),
      );
    });

    test('object output invalid JSON throws NoObjectGeneratedError', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('not json')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);
      final endedText = <String>[];

      await expectLater(
        generateText(
          model: model,
          prompt: 'make object',
          output: Output.object(
            schema: const provider.JsonSchema({'type': 'object'}),
          ),
          onEnd: (event) {
            endedText.add(event.text);
          },
        ),
        throwsA(
          isA<provider.NoObjectGeneratedError>().having(
            (error) => error.cause,
            'cause',
            isA<provider.JsonParseError>(),
          ),
        ),
      );
      expect(endedText, ['not json']);
    });

    test(
        'object output parse errors carry aggregate usage across tool-loop '
        'steps', () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'ok',
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'echo',
              input: '{}',
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
          content: [provider.TextContent('not json')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 6),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
      ]);

      await expectLater(
        generateText(
          model: model,
          prompt: 'make object',
          tools: tools,
          stopWhen: _stopAtTwoSteps,
          output: Output.object(
            schema: const provider.JsonSchema({'type': 'object'}),
          ),
        ),
        throwsA(
          isA<provider.NoObjectGeneratedError>()
              .having(
                (error) => error.usage?.inputTokens.total,
                'input tokens',
                10,
              )
              .having(
                (error) => error.usage?.outputTokens.total,
                'output tokens',
                3,
              ),
        ),
      );
    });
  });
}
