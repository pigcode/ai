import 'dart:async';

import 'package:pigcode_ai/src/generate_text/step_result.dart';
import 'package:pigcode_ai/src/generate_text/stop_condition.dart'
    show isStepCount;
import 'package:pigcode_ai/src/generate_text/output.dart';
import 'package:pigcode_ai/src/generate_text/prepare_step.dart';
import 'package:pigcode_ai/src/generate_text/stream_text.dart';
import 'package:pigcode_ai/src/generate_text/text_stream_part.dart';
import 'package:pigcode_ai/src/generate_text/tool_call_repair.dart';
import 'package:pigcode_ai/src/generate_text/tool_approval.dart';
import 'package:pigcode_ai/src/prompt/content_part.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:test/test.dart';

import '../support/logging.dart';
import '../support/scripted_model.dart';

void main() {
  // Compatibility fixture (unit): P1-CORE-08
  // Compatibility fixture (unit): P1-CORE-09
  // Compatibility fixture (unit): P1-CORE-10
  group('streamText', () {
    test(
        'StepResult.providerMetadata carries FinishPart providerMetadata '
        '(streaming path)', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('hi')],
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

      final result = streamText(model: model, prompt: 'hi');
      await result.consumeStream();

      final step = (await result.steps).single;
      expect(step.providerMetadata, {
        'anthropic': {
          'container': {'id': 'container-1'},
        },
      });
    });

    test('textStream yields only text deltas in order', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('Hello, world!')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 5),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
      ]);

      final result = streamText(model: model, prompt: 'hi');

      final deltas = await result.textStream.toList();
      expect(deltas, ['Hello, world!']);
      expect(await result.text, 'Hello, world!');
    });

    test('full stream ordering: start, text parts, finish-step, finish',
        () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('Hi')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = streamText(model: model, prompt: 'hi');
      final parts = await result.stream.toList();

      expect(parts.first, isA<StartPart>());
      expect(parts.last, isA<FinishPart>());
      final typeOrder = parts.map((p) => p.runtimeType).toList();
      expect(typeOrder, [
        StartPart,
        StartStepPart,
        TextStartPart,
        TextDeltaPart,
        TextEndPart,
        FinishStepPart,
        FinishPart,
      ]);
    });

    test('steps / finalStep / finishReason / usage Futures aggregate',
        () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('Hi')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = streamText(model: model, prompt: 'hi');

      final steps = await result.steps;
      expect(steps, hasLength(1));
      expect(steps.single.text, 'Hi');
      expect(await result.finalStep, same(steps.single));
      expect(
        (await result.finishReason).unified,
        provider.FinishReasonType.stop,
      );
      expect((await result.usage).inputTokens.total, 3);
      expect((await result.usage).outputTokens.total, 1);
    });

    test('StepResult.performance records streaming output timings', () async {
      final result = streamText(
        model: _DelayedOutputStreamModel(),
        prompt: 'hi',
      );

      await result.stream.drain<void>();
      final step = (await result.steps).single;
      final performance = step.performance;
      final timeToFirstOutput = performance.timeToFirstOutput!;

      expect(timeToFirstOutput,
          greaterThanOrEqualTo(const Duration(milliseconds: 5)));
      expect(performance.outputTokensPerSecond, greaterThanOrEqualTo(0));
      expect(performance.inputTokensPerSecond, greaterThanOrEqualTo(0));
      expect(performance.responseTime, greaterThanOrEqualTo(timeToFirstOutput));
      expect(
          performance.stepTime,
          greaterThanOrEqualTo(
            performance.responseTime,
          ));
      expect(performance.timeBetweenOutputChunks, isNotNull);
      expect(performance.timeBetweenOutputChunks!.min,
          greaterThanOrEqualTo(const Duration(milliseconds: 5)));
    });

    test('StartStepPart carries the warnings received from StreamStart',
        () async {
      final records = captureWarningLogs();
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('Hi')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
          ),
          warnings: [
            provider.UnsupportedWarning('topK'),
          ],
        ),
      ]);

      final result = streamText(model: model, prompt: 'hi');
      final parts = await result.stream.toList();

      final startStep = parts.whereType<StartStepPart>().single;
      expect(startStep.warnings, [const provider.UnsupportedWarning('topK')]);
      // 聚合亦保留:StepResult.warnings 与非流式 doGenerate 路径对称。
      final steps = await result.steps;
      expect(
        steps.single.warnings,
        [const provider.UnsupportedWarning('topK')],
      );
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning (scripted / scripted-model): '
            'The feature "topK" is not supported.',
      ]);
    });

    test(
        'tool loop runs across stream steps and consumeStream resolves futures',
        () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'echo',
              input: '{"value":"hi"}',
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
            inputTokens: provider.InputTokens(total: 4),
            outputTokens: provider.OutputTokens(total: 1),
          ),
          warnings: [provider.UnsupportedWarning('temperature')],
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
          warnings: [provider.UnsupportedWarning('topK')],
        ),
      ]);

      final result = streamText(
        model: model,
        prompt: 'call echo',
        tools: {
          'echo': Tool(
            inputSchema: const provider.JsonSchema(<String, Object?>{
              'type': 'object',
            }),
            execute: (input, options) async => 'hi',
          ),
        },
        stopWhen: isStepCount(2),
      );

      await result.consumeStream();

      final steps = await result.steps;
      expect(steps, hasLength(2));
      expect(steps.first.toolCalls, hasLength(1));
      expect(steps.first.toolResults, hasLength(1));
      expect(await result.text, 'done');
      expect(await result.content, hasLength(4));
      expect((await result.files).single.mediaType, 'text/plain');
      expect((await result.sources).single.id, 'source-1');
      expect(await result.toolCalls, hasLength(1));
      expect((await result.toolCalls).single.toolName, 'echo');
      expect(await result.toolResults, hasLength(1));
      expect((await result.toolResults).single.result, 'hi');
      expect(await result.warnings, [
        const provider.UnsupportedWarning('temperature'),
        const provider.UnsupportedWarning('topK'),
      ]);
      expect(
        (await result.finishReason).unified,
        provider.FinishReasonType.stop,
      );
      expect((await result.usage).inputTokens.total, 10);
      expect((await result.usage).outputTokens.total, 3);
    });

    test(
        'result.text is the final step text only (intermediate pre-tool-call '
        'narration is not concatenated); textStream still has all deltas',
        () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'r',
        ),
      };
      final model = ScriptedModel(turns: [
        // 步 1:工具调用前的中间叙述 + 工具调用。
        const ScriptedTurn(
          content: [
            provider.TextContent('narration'),
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
        // 步 2:最终回答。
        const ScriptedTurn(
          content: [provider.TextContent('final')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        stopWhen: isStepCount(2),
      );
      final deltas = await result.textStream.toList();

      // 与 generateText.text 一致(v7 last-step 语义):只取末步,不把
      // 'narration' 拼进最终回答。
      expect(await result.text, 'final');
      // 全部步骤的文本增量仍可经 textStream 获得。
      expect(deltas.join(), 'narrationfinal');
    });

    test(
        'a ResponseMetadata stream part is merged into the step response '
        '(id/modelId carried through)', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('Hi')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
          ),
          responseMetadata: provider.ResponseMetadata(
            id: 'resp-1',
            modelId: 'scripted-model-v2',
          ),
        ),
      ]);

      final result = streamText(model: model, prompt: 'hi');
      await result.consumeStream();

      final steps = await result.steps;
      expect(steps.single.response?.id, 'resp-1');
      expect(steps.single.response?.modelId, 'scripted-model-v2');
    });

    test(
        'a split ResponseMetadata chunk is merged with streamResult.response '
        'so neither headers/body nor id/modelId are lost', () async {
      final result = streamText(
        model: ResponseSplitStreamModel(),
        prompt: 'hi',
      );
      await result.consumeStream();

      final steps = await result.steps;
      final response = steps.single.response;
      expect(response, isNotNull);
      // 来自流内 `ResponseMetadata` 分块。
      expect(response!.id, 'resp-1');
      expect(response.modelId, 'split-model-v2');
      // 来自 `doStream` 返回值的 `LanguageModelStreamResult.response`。
      expect(response.headers, {'x-request-id': 'req-abc'});
      expect(response.body, {'raw': 'body'});
    });

    test(
        'a provider-executed tool call is not re-executed locally in the '
        'stream engine (providerExecuted == true skips the local execute)',
        () async {
      var localExecuted = false;
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

      final result = streamText(
        model: model,
        prompt: 'hi',
        tools: {
          'x': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async {
              localExecuted = true;
              return 'should not run';
            },
          ),
        },
        // 故意不传 stopWhen:单步即可验证本地未重复执行。
      );

      await result.consumeStream();

      final steps = await result.steps;
      expect(steps, hasLength(1));
      expect(localExecuted, isFalse);
      expect(steps.single.toolResults, isEmpty);
      expect(model.callCount, 1);
    });

    test(
        'without stopWhen, a tool-calls finish still runs only a single '
        'step (v7: no stopWhen = single step, even with executable tool '
        'calls)', () async {
      // 只脚本化一个回合:若循环误发起第二次模型调用,
      // ScriptedModel 会在流被消费时抛 StateError,测试即失败。
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
      ]);

      final result = streamText(
        model: model,
        prompt: 'call echo',
        tools: {
          'echo': Tool(
            inputSchema: const provider.JsonSchema(<String, Object?>{
              'type': 'object',
            }),
            execute: (input, options) async => 'hi',
          ),
        },
        // 故意不传 stopWhen。
      );

      await result.consumeStream();

      final steps = await result.steps;
      expect(steps, hasLength(1));
      expect(model.callCount, 1);
      expect(steps.single.toolCalls, hasLength(1));
      expect(steps.single.toolResults, hasLength(1));
    });

    test(
        'toolApproval userApproval emits an approval request stream part and '
        'does not execute the tool', () async {
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

      final result = streamText(
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

      final parts = await result.stream.toList();
      final requestPart =
          parts.whereType<ToolApprovalRequestStreamPart>().single;
      expect(requestPart.request.toolCallId, 'call-delete');
      expect(executed, isFalse);

      final steps = await result.steps;
      expect(steps.single.toolResults, isEmpty);
      final stepRequest =
          steps.single.content.whereType<provider.ToolApprovalRequest>().single;
      expect(stepRequest.approvalId, requestPart.request.approvalId);

      final responseMessages = await result.responseMessages;
      final assistant =
          responseMessages.whereType<AssistantModelMessage>().single;
      expect(
        assistant.content
            .whereType<ToolApprovalRequestPart>()
            .single
            .approvalId,
        requestPart.request.approvalId,
      );
    });

    test(
        'per-tool toolApproval function emits approval request stream part and '
        'does not execute the tool', () async {
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

      final result = streamText(
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

      final parts = await result.stream.toList();
      final requestPart =
          parts.whereType<ToolApprovalRequestStreamPart>().single;
      expect(requestPart.request.toolCallId, 'call-delete');
      expect(executed, isFalse);
      expect(receivedInput, {'path': 'a.txt'});
      expect(receivedOptions?.toolCallId, 'call-delete');
      expect(receivedOptions?.messages.single, isA<provider.UserMessage>());
    });

    test(
        'a resumed approved ToolApprovalResponsePart executes the matching '
        'tool before the next streamed model call and feeds the result into '
        'prompt', () async {
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

      final first = streamText(
        model: firstModel,
        prompt: 'delete it',
        tools: tools,
        toolApproval: const {
          'delete_file': ToolApprovalStatus.userApproval,
        },
      );
      await first.consumeStream();
      final firstResponseMessages = await first.responseMessages;
      final approvalId = firstResponseMessages
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
      final second = streamText(
        model: secondModel,
        messages: [
          UserModelMessage.text('delete it'),
          ...firstResponseMessages,
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

      final parts = await second.stream.toList();

      expect(await second.text, 'done');
      expect(executions, [
        {'path': 'a.txt'},
      ]);
      final streamedToolResult =
          parts.whereType<ToolResultStreamPart>().single.toolResult;
      expect(streamedToolResult.toolCallId, 'call-delete');
      expect(streamedToolResult.toolName, 'delete_file');
      expect(streamedToolResult.result, 'deleted');
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
          (await second.responseMessages).whereType<ToolModelMessage>().single;
      expect(
        responseToolMessage.content.whereType<ToolResultPart>().single.output,
        const provider.ToolResultText('deleted'),
      );
    });

    test(
        'resumed approved streamed tool approval repairs invalid input before '
        'executing', () async {
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

      final first = streamText(
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
      await first.consumeStream();
      final firstResponseMessages = await first.responseMessages;
      final approvalId = firstResponseMessages
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

      final second = streamText(
        model: secondModel,
        messages: [
          UserModelMessage.text('delete it'),
          ...firstResponseMessages,
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

      final parts = await second.stream.toList();

      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(repairCalled, isTrue);
      expect(executions, [
        {'path': 'a.txt'},
      ]);
    });

    test(
        'resumed approval recheck input mutations do not change executed input '
        'for streamed calls', () async {
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

      final first = streamText(
        model: firstModel,
        prompt: 'delete it',
        tools: tools,
        toolApproval: const {
          'delete_file': ToolApprovalStatus.userApproval,
        },
      );
      await first.consumeStream();
      final firstResponseMessages = await first.responseMessages;
      final approvalId = firstResponseMessages
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

      final second = streamText(
        model: secondModel,
        messages: [
          UserModelMessage.text('delete it'),
          ...firstResponseMessages,
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

      await second.consumeStream();

      expect(approvalInputs, [
        {'path': 'b.txt'},
      ]);
      expect(executions, [
        {'path': 'a.txt'},
      ]);
    });

    test(
        'provider-executed resumed approval is forwarded without local '
        'tool execution for streamed calls', () async {
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

      final result = streamText(
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
      await result.consumeStream();

      expect(await result.text, 'done');
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
        'tool execution for streamed calls', () async {
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

      final result = streamText(
        model: model,
        prompt: 'search it',
        toolApproval: const {
          'mcp.search': ToolApprovalStatus.approved(reason: 'allowed'),
        },
        stopWhen: isStepCount(2),
      );
      final parts = await result.stream.toList();

      expect(await result.text, 'done');
      expect(await result.steps, hasLength(2));
      expect(parts.whereType<ToolResultStreamPart>(), isEmpty);
      final approvalPart =
          parts.whereType<ToolApprovalResponseStreamPart>().single;
      expect(approvalPart.response.approved, isTrue);
      expect(approvalPart.response.reason, 'allowed');
      expect(approvalPart.response.providerOptions, approvalMetadata);

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

    test(
        'resumed approved tool approval is rechecked against current policy '
        'for streamed calls', () async {
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

      final first = streamText(
        model: firstModel,
        prompt: 'delete it',
        tools: tools,
        toolApproval: const {
          'delete_file': ToolApprovalStatus.userApproval,
        },
      );
      await first.consumeStream();
      final firstResponseMessages = await first.responseMessages;
      final approvalId = firstResponseMessages
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

      final second = streamText(
        model: secondModel,
        messages: [
          UserModelMessage.text('delete it'),
          ...firstResponseMessages,
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

      final parts = await second.stream.toList();

      expect(await second.text, 'done');
      expect(executions, isEmpty);
      final streamedToolResult =
          parts.whereType<ToolResultStreamPart>().single.toolResult;
      expect(streamedToolResult.toolCallId, 'call-delete');
      expect(streamedToolResult.toolName, 'delete_file');
      expect(streamedToolResult.result, 'policy changed');
      expect(streamedToolResult.isError, isNull);
      final prompt = secondModel.receivedCallOptions.single.prompt;
      final toolMessage = prompt.whereType<provider.ToolMessage>().last;
      final toolResult =
          toolMessage.content.whereType<provider.ToolResultPart>().single;
      expect(
        toolResult.output,
        const provider.ToolResultExecutionDenied(reason: 'policy changed'),
      );
      final responseToolMessage =
          (await second.responseMessages).whereType<ToolModelMessage>().single;
      expect(
        responseToolMessage.content.whereType<ToolResultPart>().single.output,
        const provider.ToolResultExecutionDenied(reason: 'policy changed'),
      );
    });

    test(
        'resumed approval recheck does not reuse approval reason when current '
        'denial has no reason for streamed calls', () async {
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

      final result = streamText(
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
      final parts = await result.stream.toList();

      expect(await result.text, 'done');
      final streamedToolResult =
          parts.whereType<ToolResultStreamPart>().single.toolResult;
      expect(streamedToolResult.result, 'Tool execution denied');
      expect(streamedToolResult.isError, isNull);
      final prompt = model.receivedCallOptions.single.prompt;
      final toolMessage = prompt.whereType<provider.ToolMessage>().last;
      expect(
        toolMessage.content.whereType<provider.ToolResultPart>().single.output,
        const provider.ToolResultExecutionDenied(),
      );
      final responseToolMessage =
          (await result.responseMessages).whereType<ToolModelMessage>().single;
      expect(
        responseToolMessage.content.whereType<ToolResultPart>().single.output,
        const provider.ToolResultExecutionDenied(),
      );
    });

    test('approved resumed tool approval errors when the tool is unavailable',
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
      final first = streamText(
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
      await first.consumeStream();
      final firstResponseMessages = await first.responseMessages;
      final approvalId = firstResponseMessages
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

      final second = streamText(
        model: secondModel,
        messages: [
          UserModelMessage.text('delete it'),
          ...firstResponseMessages,
          ToolModelMessage([
            ToolApprovalResponsePart(
              approvalId: approvalId,
              approved: true,
            ),
          ]),
        ],
      );

      final parts = await second.stream.toList();

      expect(parts.last, isA<ErrorPart>());
      expect((parts.last as ErrorPart).error, isA<StateError>());
      expect(secondModel.receivedCallOptions, isEmpty);
    });

    test('provider streamed ToolApprovalRequest is forwarded as a stream part',
        () async {
      const request = provider.ToolApprovalRequest(
        approvalId: 'provider-approval',
        toolCallId: 'call-delete',
        providerMetadata: {
          'openai': {'itemId': 'approval_item_1'},
        },
      );
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [request],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = streamText(model: model, prompt: 'delete it');

      final parts = await result.stream.toList();
      expect(
        parts.whereType<ToolApprovalRequestStreamPart>().single.request,
        request,
      );
      final stepRequest = (await result.steps)
          .single
          .content
          .whereType<provider.ToolApprovalRequest>()
          .single;
      expect(stepRequest, request);
      final assistant = (await result.responseMessages)
          .whereType<AssistantModelMessage>()
          .single;
      expect(
        assistant.content
            .whereType<ToolApprovalRequestPart>()
            .single
            .approvalId,
        request.approvalId,
      );
    });

    test(
        'provider streamed ToolApprovalRequest blocks local execution until '
        'caller resumes', () async {
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

      final result = streamText(
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

      final parts = await result.stream.toList();

      expect(executed, isFalse);
      expect(parts.whereType<ToolApprovalRequestStreamPart>().single.request,
          request);
      expect(parts.whereType<ToolResultStreamPart>(), isEmpty);
      final steps = await result.steps;
      expect(steps.single.toolResults, isEmpty);
      expect(
        steps.single.content.whereType<provider.ToolApprovalRequest>().single,
        request,
      );
      final assistant = (await result.responseMessages)
          .whereType<AssistantModelMessage>()
          .single;
      expect(
        assistant.content
            .whereType<ToolApprovalRequestPart>()
            .single
            .approvalId,
        request.approvalId,
      );
      expect((await result.responseMessages).whereType<ToolModelMessage>(),
          isEmpty);
    });

    test(
        'approved provider ToolApprovalRequest reuses the provider approval id',
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

      final result = streamText(
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

      final parts = await result.stream.toList();

      expect(executed, isTrue);
      expect(
        parts
            .whereType<ToolApprovalRequestStreamPart>()
            .map((part) => part.request.approvalId),
        [request.approvalId],
      );
      expect(
        parts.whereType<ToolApprovalResponseStreamPart>().single.response,
        provider.ToolApprovalResponsePart(
          approvalId: request.approvalId,
          approved: true,
          providerOptions: request.providerMetadata,
        ),
      );
      final steps = await result.steps;
      final approvalResponse = steps.single.toolApprovalResponses.single;
      expect(
        approvalResponse,
        provider.ToolApprovalResponsePart(
          approvalId: request.approvalId,
          approved: true,
          providerOptions: request.providerMetadata,
        ),
      );
      expect(
        steps.single.content.whereType<provider.ToolApprovalRequest>(),
        [request],
      );
    });

    test(
        'toolApproval denied can continue and feed execution-denied results '
        'back to the next streamed model step', () async {
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

      final result = streamText(
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
        stopWhen: isStepCount(2),
      );

      await result.consumeStream();

      expect(executed, isFalse);
      expect(await result.text, 'denied handled');
      final steps = await result.steps;
      expect(steps, hasLength(2));
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
        'toModelOutput returning ToolResultErrorText is preserved as-is in '
        'the ToolResultPart fed into the next model turn (not flattened '
        'into ToolResultText/Json)', () async {
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

      final result = streamText(
        model: model,
        prompt: 'hi',
        tools: {
          'get_weather': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async => 'unused',
            toModelOutput: (input, output) =>
                const provider.ToolResultErrorText('bad'),
          ),
        },
        stopWhen: isStepCount(5),
      );

      await result.consumeStream();

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
        'toModelOutput returning ToolResultErrorText sets isError:true on '
        'the result-API ToolResult (both the executed step toolResults and '
        'the streamed ToolResultStreamPart)', () async {
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

      final result = streamText(
        model: model,
        prompt: 'hi',
        tools: {
          'get_weather': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async => 'unused',
            toModelOutput: (input, output) =>
                const provider.ToolResultErrorText('bad'),
          ),
        },
        // 故意不传 stopWhen:单步收尾即可断言。
      );

      final parts = await result.stream.toList();
      final streamedToolResult =
          parts.whereType<ToolResultStreamPart>().single.toolResult;
      expect(streamedToolResult.isError, isTrue);

      final steps = await result.steps;
      expect(steps.single.toolResults.single.isError, isTrue);
    });

    test(
        'provider.RawPart in doStream is forwarded as RawStreamPart '
        '(includeRawChunks), preserving arrival order', () async {
      final result = streamText(model: RawChunkStreamModel(), prompt: 'hi');

      final parts = await result.stream.toList();
      final textEndIndex = parts.indexWhere((p) => p is TextEndPart);
      final rawIndex = parts.indexWhere((p) => p is RawStreamPart);

      expect(rawIndex, greaterThan(-1));
      expect(rawIndex, greaterThan(textEndIndex));
      expect(
        (parts[rawIndex] as RawStreamPart).rawValue,
        {'raw': 'chunk-1'},
      );
    });

    test(
        'provider 侧已执行的 ToolResult 会被保留进重建的历史消息,供下一步'
        '模型请求读取(而非在 _toAssistantMessage 重建时被丢弃)', () async {
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

      final result = streamText(
        model: model,
        prompt: '搜索并回声',
        tools: {
          'echo': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async =>
                (input as Map<String, Object?>)['text'],
          ),
        },
        stopWhen: isStepCount(5),
      );

      await result.consumeStream();

      expect(model.receivedCallOptions, hasLength(2));
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

      final result = streamText(
        model: model,
        prompt: '搜索并回声',
        tools: {
          'echo': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async =>
                (input as Map<String, Object?>)['text'],
          ),
        },
        stopWhen: isStepCount(5),
      );

      await result.consumeStream();

      final responseMessages = await result.responseMessages;
      final assistantMessage =
          responseMessages.whereType<AssistantModelMessage>().first;
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
        '内容项的 providerMetadata(如 tool-call/自定义内容块的 openai itemId)'
        '会被携带进续接的历史消息与公开 responseMessages 的 part.providerOptions'
        '(而非在 _toAssistantMessage/_stepResponseMessages 重建时被丢弃)。'
        '取 ToolCall/CustomContentBlock(经流式聚合原样透传,不经过'
        'Start/Delta/End 分块拼接缓冲)以隔离本修复范围之外的分块拼接行为', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.CustomContentBlock(
              'openai.reasoning_summary',
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

      final result = streamText(
        model: model,
        prompt: '推理并回声',
        tools: {
          'echo': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async =>
                (input as Map<String, Object?>)['text'],
          ),
        },
        stopWhen: isStepCount(5),
      );

      await result.consumeStream();

      // 内部续接路径(下一步模型请求实际读到的历史消息)。
      final secondPrompt = model.receivedCallOptions[1].prompt;
      final rebuiltAssistant =
          secondPrompt.whereType<provider.AssistantMessage>().single;
      final rebuiltCustom =
          rebuiltAssistant.content.whereType<provider.CustomPart>().single;
      final rebuiltToolCall =
          rebuiltAssistant.content.whereType<provider.ToolCallPart>().single;
      expect(rebuiltCustom.providerOptions, {
        'openai': {'itemId': 'rs_123', 'reasoningEncryptedContent': 'enc_abc'},
      });
      expect(rebuiltToolCall.providerOptions, {
        'openai': {'itemId': 'fc_1'},
      });

      // 公开续接路径(responseMessages,供调用方自行续接)。
      final responseMessages = await result.responseMessages;
      final assistantMessage =
          responseMessages.whereType<AssistantModelMessage>().first;
      final customPart =
          assistantMessage.content.whereType<CustomPart>().single;
      final toolCallPart =
          assistantMessage.content.whereType<ToolCallPart>().single;
      expect(customPart.providerOptions, {
        'openai': {'itemId': 'rs_123', 'reasoningEncryptedContent': 'enc_abc'},
      });
      expect(toolCallPart.providerOptions, {
        'openai': {'itemId': 'fc_1'},
      });
    });

    test(
        'StartStepPart.request carries streamResult.request from doStream '
        '(debug/replay metadata is not dropped)', () async {
      final parts = await streamText(
        model: RequestMetadataStreamModel(),
        prompt: 'hi',
      ).stream.toList();

      final startStep = parts.whereType<StartStepPart>().single;
      expect(startStep.request, isNotNull);
      expect(startStep.request!.body, {'model': 'request-metadata-model'});
    });

    test(
        'instructions、headers、providerOptions、include.rawChunks 与 '
        'onStepEnd 会透传到每步底层模型调用', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('Hi')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);
      final endedSteps = <StepResult>[];

      final result = streamText(
        model: model,
        prompt: 'hi',
        instructions: '你是助手',
        headers: const {'x-trace-id': 'trace-1'},
        providerOptions: const {
          'openai': {'reasoningEffort': 'low'},
        },
        include: const StreamTextInclude(rawChunks: true),
        onStepEnd: endedSteps.add,
      );
      await result.consumeStream();

      final steps = await result.steps;
      expect(endedSteps, [same(steps.single)]);
      final options = model.receivedCallOptions.single;
      expect(options.headers, {'x-trace-id': 'trace-1'});
      expect(options.providerOptions, {
        'openai': {'reasoningEffort': 'low'},
      });
      expect(options.includeRawChunks, isTrue);
      expect(options.prompt.first, isA<provider.SystemMessage>());
      expect((options.prompt.first as provider.SystemMessage).content, '你是助手');
    });

    test('onStart/onStepStart/onEnd observe the full stream lifecycle',
        () async {
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

      final result = streamText(
        model: model,
        prompt: 'hi',
        tools: {
          'echo': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async => 'ok',
          ),
        },
        stopWhen: isStepCount(2),
        onStart: (event) {
          events.add('start:${event.messages.length}:${event.model.modelId}');
          final message = event.messages.single as UserModelMessage;
          expect(
            () => message.content.add(const TextPart('event-mutated')),
            throwsUnsupportedError,
          );
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

      await result.consumeStream();

      expect(await result.text, 'done');
      expect(events, [
        'start:1:scripted-model',
        'step-start:0:0:1',
        'step-end::1',
        'step-start:1:1:3',
        'step-end:done:0',
        'end:2:done:5:2:1:1',
      ]);
    });

    test(
        'headers/providerOptions are snapshotted at invocation time before '
        'the deferred driver runs', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('Hi')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
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

      final result = streamText(
        model: model,
        prompt: 'hi',
        headers: headers,
        providerOptions: providerOptions,
      );
      headers['x-trace-id'] = 'mutated';
      headers['x-extra'] = 'extra';
      openAiOptions['reasoningEffort'] = 'high';
      nestedOptions['level'] = 2;
      listOptions.add('b');
      providerOptions['anthropic'] = {'cacheControl': true};

      await result.consumeStream();

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
  });

  group('streamText output', () {
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

      final result = streamText(model: model, prompt: 'say hello');
      await result.consumeStream();

      expect(await result.text, 'hello');
      expect(await result.output, 'hello');
      expect(model.receivedCallOptions.single.responseFormat, isNull);
    });

    test('output rejects final text when final finish reason is toolCalls',
        () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.TextContent('thinking first'),
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

      final result = streamText(model: model, prompt: 'call tool');
      await result.consumeStream();

      expect(
        result.output,
        throwsA(isA<provider.NoOutputGeneratedError>()),
      );
    });

    test('output rejects final text when final finish reason is length',
        () async {
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

      final result = streamText(model: model, prompt: 'say hello');
      await result.consumeStream();

      expect(
        result.output,
        throwsA(isA<provider.NoOutputGeneratedError>()),
      );
    });

    test('output rejects final text when final finish reason is contentFilter',
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

      final result = streamText(model: model, prompt: 'say hello');
      await result.consumeStream();

      expect(
        result.output,
        throwsA(isA<provider.NoOutputGeneratedError>()),
      );
    });

    test('object output parses final streamed text', () async {
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

      final result = streamText(
        model: model,
        prompt: 'make object',
        output: Output.object(schema: schema),
      );
      await result.consumeStream();

      expect(await result.output, {'value': 'ok'});
      final format = model.receivedCallOptions.single.responseFormat;
      expect(format, isA<provider.ResponseFormatJson>());
    });

    test('partialOutputStream emits object partials', () async {
      const schema = provider.JsonSchema({
        'type': 'object',
        'properties': {
          'value': {'type': 'string'},
        },
      });
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('{"value":"hello"}')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = streamText(
        model: model,
        prompt: 'make object',
        output: Output.object(schema: schema),
      );

      final partials = await result.partialOutputStream.toList();
      expect(partials, contains(equals({'value': 'hello'})));
    });

    test('array output supports elementStream', () async {
      const elementSchema = provider.JsonSchema({
        'type': 'object',
        'properties': {
          'content': {'type': 'string'},
        },
        'required': ['content'],
        'additionalProperties': false,
      });
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.TextContent(
              '{"elements":[{"content":"a"},{"content":"b"}]}',
            ),
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

      final result = streamText(
        model: model,
        prompt: 'make array',
        output: Output.array(element: elementSchema),
      );

      expect(await result.elementStream.toList(), [
        {'content': 'a'},
        {'content': 'b'},
      ]);
    });

    test('object partials reset at step boundaries', () async {
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
          content: [
            provider.TextContent('thinking first'),
            provider.ToolCall(
                toolCallId: 'call-1', toolName: 'echo', input: '{}'),
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

      final result = streamText(
        model: model,
        prompt: 'make object',
        tools: {
          'echo': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async => 'done',
          ),
        },
        stopWhen: isStepCount(2),
        output: Output.object(schema: schema),
      );

      final partials = await result.partialOutputStream.toList();
      expect(await result.output, {'value': 'ok'});
      expect(partials, contains(equals({'value': 'ok'})));
    });

    test('array elementStream resets at step boundaries', () async {
      const elementSchema = provider.JsonSchema({
        'type': 'object',
        'properties': {
          'content': {'type': 'string'},
        },
        'required': ['content'],
        'additionalProperties': false,
      });
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.TextContent(
              '{"elements":[{"content":"draft"}]}',
            ),
            provider.ToolCall(
                toolCallId: 'call-1', toolName: 'echo', input: '{}'),
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
          content: [
            provider.TextContent(
              '{"elements":[{"content":"final"}]}',
            ),
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

      final result = streamText(
        model: model,
        prompt: 'make array',
        tools: {
          'echo': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async => 'done',
          ),
        },
        stopWhen: isStepCount(2),
        output: Output.array(element: elementSchema),
      );

      expect(await result.output, [
        {'content': 'final'},
      ]);
      expect(await result.elementStream.toList(), [
        {'content': 'draft'},
        {'content': 'final'},
      ]);
    });

    test('object partials are emitted before the final step finishes',
        () async {
      const schema = provider.JsonSchema({
        'type': 'object',
        'properties': {
          'value': {'type': 'string'},
        },
        'required': ['value'],
        'additionalProperties': false,
      });
      final model = GatedJsonStreamModel('{"value":"live"}');

      final result = streamText(
        model: model,
        prompt: 'make object',
        output: Output.object(schema: schema),
      );

      final partial = await result.partialOutputStream.first.timeout(
        const Duration(seconds: 1),
      );
      expect(partial, {'value': 'live'});
      expect(model.finishReleased, isFalse);

      model.releaseFinish();
      await result.consumeStream();
    });

    test('array elements are emitted before the final step finishes', () async {
      const elementSchema = provider.JsonSchema({
        'type': 'object',
        'properties': {
          'content': {'type': 'string'},
        },
        'required': ['content'],
        'additionalProperties': false,
      });
      final model = GatedJsonStreamModel(
        '{"elements":[{"content":"live"}]}',
      );

      final result = streamText(
        model: model,
        prompt: 'make array',
        output: Output.array(element: elementSchema),
      );

      final element = await result.elementStream.first.timeout(
        const Duration(seconds: 1),
      );
      expect(element, {'content': 'live'});
      expect(model.finishReleased, isFalse);

      model.releaseFinish();
      await result.consumeStream();
    });

    test('output parse failure does not rewrite provider stream into ErrorPart',
        () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('{')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = streamText(
        model: model,
        prompt: 'bad json',
        output: Output.json(),
      );

      final parts = await result.stream.toList();
      expect(parts.whereType<ErrorPart>(), isEmpty);
      await expectLater(
        result.output,
        throwsA(isA<provider.NoObjectGeneratedError>()),
      );
    });

    test(
        'output parse errors carry aggregate usage across streamed tool-loop '
        'steps', () async {
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
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
        const ScriptedTurn(
          content: [provider.TextContent('{')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 7),
            outputTokens: provider.OutputTokens(total: 2),
          ),
        ),
      ]);

      final result = streamText(
        model: model,
        prompt: 'bad json',
        tools: {
          'echo': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async => 'ok',
          ),
        },
        stopWhen: isStepCount(2),
        output: Output.json(),
      );

      await result.consumeStream();
      await expectLater(
        result.output,
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

      final result = streamText(
        model: model,
        prompt: 'make null',
        output: Output.json(),
      );
      final partials = await result.partialOutputStream.toList();

      expect(partials, hasLength(1));
      expect(partials.single, isNull);
      expect(await result.output, isNull);
    });
  });

  group('streamText error is terminal', () {
    test('ErrorPart is the last stream part; no FinishPart follows', () async {
      final parts = await streamText(
        model: ErrorStreamModel(),
        prompt: 'hi',
      ).stream.toList();

      // ErrorPart 是终端事件:其后不得再有分块(尤其不得追加 FinishPart)。
      expect(parts.whereType<ErrorPart>(), hasLength(1));
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('onError is invoked exactly once and the stream ends with ErrorPart',
        () async {
      final errors = <Object?>[];

      final parts = await streamText(
        model: ErrorStreamModel(),
        prompt: 'hi',
        onError: errors.add,
      ).stream.toList();

      expect(errors, ['boom']);
      expect(parts.last, isA<ErrorPart>());
      expect((parts.last as ErrorPart).error, 'boom');
    });

    test('onEnd failures are reported through the stream error path', () async {
      final failure = StateError('onEnd failed');
      final errors = <Object?>[];
      final result = streamText(
        model: ScriptedModel(turns: [
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
        ]),
        prompt: 'hi',
        onEnd: (_) {
          throw failure;
        },
        onError: errors.add,
      );

      final parts = await result.stream.toList();

      expect(parts.whereType<FinishPart>(), isEmpty);
      expect(parts.last, isA<ErrorPart>());
      expect((parts.last as ErrorPart).error, same(failure));
      expect(errors, [same(failure)]);
      expect(await result.text, 'done');
      expect(
        await result.finishReason,
        const provider.LanguageModelFinishReason(
          provider.FinishReasonType.error,
        ),
      );
      expect(
        result.output,
        throwsA(isA<provider.NoOutputGeneratedError>()),
      );
    });

    test(
        'a provider-errored stream resolves the aggregate finishReason to '
        'error (not the last/default step reason)', () async {
      final result = streamText(model: ErrorStreamModel(), prompt: 'hi');
      await result.consumeStream();

      // 因 ErrorPart 终结:聚合 finishReason 为 error,而非默认 stop。
      expect(
        await result.finishReason,
        const provider.LanguageModelFinishReason(
          provider.FinishReasonType.error,
        ),
      );
    });

    test('a provider-errored stream does not expose output', () async {
      final result = streamText(model: TextThenErrorStreamModel(), prompt: 'x');
      await result.consumeStream();

      expect(
        result.output,
        throwsA(isA<provider.NoOutputGeneratedError>()),
      );
    });

    test(
        'text produced before a terminal ErrorPart is preserved in '
        'result.text/steps as an error step (not dropped)', () async {
      final result = streamText(model: TextThenErrorStreamModel(), prompt: 'x');
      final parts = await result.stream.toList();

      // 流已投递部分文本、并以 ErrorPart 终结(无 FinishPart)。
      expect(
        parts.whereType<TextDeltaPart>().map((p) => p.delta).join(),
        'partial',
      );
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<FinishPart>(), isEmpty);

      // 聚合保留错误前的部分文本:一步 error StepResult。
      expect(await result.text, 'partial');
      final steps = await result.steps;
      expect(steps, hasLength(1));
      expect(steps.single.text, 'partial');
      expect(
        steps.single.finishReason,
        const provider.LanguageModelFinishReason(
          provider.FinishReasonType.error,
        ),
      );
    });

    test(
        'text streamed without a closing TextEnd before a terminal ErrorPart '
        'is still flushed into result.text/steps', () async {
      final result =
          streamText(model: OpenTextThenErrorStreamModel(), prompt: 'x');
      final parts = await result.stream.toList();

      // 流已投递部分文本(未闭合),并以 ErrorPart 终结。
      expect(
        parts.whereType<TextDeltaPart>().map((p) => p.delta).join(),
        'partial',
      );
      expect(parts.last, isA<ErrorPart>());

      // 报错时冲刷了未闭合缓冲:部分文本仍保留进聚合(一步 error）。
      expect(await result.text, 'partial');
      final steps = await result.steps;
      expect(steps, hasLength(1));
      expect(steps.single.text, 'partial');
      expect(
        steps.single.finishReason,
        const provider.LanguageModelFinishReason(
          provider.FinishReasonType.error,
        ),
      );
    });

    test(
        'reasoning streamed without a closing ReasoningEnd before a terminal '
        'ErrorPart is still flushed into the error step content', () async {
      final result = streamText(
        model: OpenReasoningThenErrorStreamModel(),
        prompt: 'x',
      );
      await result.consumeStream();

      final steps = await result.steps;
      expect(steps, hasLength(1));
      expect(
        steps.single.content.whereType<provider.ReasoningContent>().single.text,
        'partial-think',
      );
      expect(
        steps.single.finishReason,
        const provider.LanguageModelFinishReason(
          provider.FinishReasonType.error,
        ),
      );
    });

    test(
        'a throwing tool execute still records the completed provider turn '
        'as an error step (stream aggregates keep pre-error progress)',
        () async {
      final errors = <Object?>[];
      final tools = <String, Tool>{
        'boom': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => throw StateError('tool failed'),
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.TextContent('before'),
            provider.ToolCall(toolCallId: 'c1', toolName: 'boom', input: '{}'),
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        onError: errors.add,
      );
      final parts = await result.stream.toList();

      // error-as-terminal:以 ErrorPart 收尾、无 FinishPart,onError 收到工具异常。
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<FinishPart>(), isEmpty);
      expect(errors.single, isA<StateError>());

      // 已完成的 provider 回合固化为一步 error:错误前文本保留进聚合,
      // 与 provider ErrorPart 路径一致(不再整步丢失)。
      final steps = await result.steps;
      expect(steps, hasLength(1));
      expect(steps.single.text, 'before');
      expect(
        steps.single.finishReason,
        const provider.LanguageModelFinishReason(
          provider.FinishReasonType.error,
        ),
      );
      expect(await result.text, 'before');
    });

    test(
        'a throwing toolApproval function still records the completed provider '
        'turn as an error step', () async {
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
      final result = streamText(
        model: model,
        prompt: 'delete it',
        tools: {
          'delete_file': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async => 'deleted',
          ),
        },
        toolApproval: (ToolApprovalOptions options) {
          throw StateError('approval failed');
        },
      );

      final parts = await result.stream.toList();

      expect(parts.whereType<ToolCallStreamPart>(), hasLength(1));
      expect(parts.last, isA<ErrorPart>());
      expect((parts.last as ErrorPart).error, isA<StateError>());
      final steps = await result.steps;
      expect(steps, hasLength(1));
      expect(
        steps.single.finishReason,
        const provider.LanguageModelFinishReason(
          provider.FinishReasonType.error,
        ),
      );
      expect(steps.single.content.whereType<provider.ToolCall>(), hasLength(1));
      final responseMessages = await result.responseMessages;
      final assistant =
          responseMessages.whereType<AssistantModelMessage>().single;
      expect(assistant.content.whereType<ToolCallPart>(), hasLength(1));
    });

    test('repairToolCall can repair unknown streamed tool names', () async {
      provider.JsonValue? executedInput;
      ToolCallRepairOptions? seenOptions;
      final tools = <String, Tool>{
        'correct_tool': Tool(
          inputSchema: const provider.JsonSchema({
            'type': 'object',
            'properties': {
              'value': {'type': 'string'},
            },
            'required': ['value'],
          }),
          execute: (input, options) async {
            executedInput = input;
            return '${(input as Map<String, Object?>)['value']}-result';
          },
        ),
      };
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'unknown_tool',
              input: '{"value":"test"}',
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        repairToolCall: (options) async {
          seenOptions = options;
          expect(options.toolCall.toolName, 'unknown_tool');
          expect(options.error, isA<NoSuchToolError>());
          return provider.ToolCall(
            toolCallId: options.toolCall.toolCallId,
            toolName: 'correct_tool',
            input: options.toolCall.input,
          );
        },
      );
      final parts = await result.stream.toList();
      final steps = await result.steps;

      expect(seenOptions, isNotNull);
      expect(executedInput, {'value': 'test'});
      expect(
        parts.whereType<ToolCallStreamPart>().single.toolCall.toolName,
        'correct_tool',
      );
      expect(steps.single.toolCalls.single.toolName, 'correct_tool');
      expect(steps.single.toolResults.single.result, 'test-result');
    });

    test(
        'repairToolCall throwing for unknown streamed tool surfaces as '
        'terminal error', () async {
      final repairFailure = StateError('repair failed');
      final tools = <String, Tool>{
        'correct_tool': Tool(
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        repairToolCall: (options) => throw repairFailure,
      );
      final parts = await result.stream.toList();
      final steps = await result.steps;

      final streamToolCall = parts.whereType<ToolCallStreamPart>().single;
      expect(streamToolCall.toolCall.toolName, 'unknown_tool');
      expect(parts.last, isA<ErrorPart>());
      final terminalError = (parts.last as ErrorPart).error;
      expect(terminalError, isA<ToolCallRepairError>());
      expect((terminalError as ToolCallRepairError).cause, same(repairFailure));
      expect(
          steps.single.content.whereType<provider.ToolCall>().single.toolName,
          'unknown_tool');
      expect(
        steps.single.finishReason.unified,
        provider.FinishReasonType.error,
      );
    });

    test(
        'invalid repaired unknown streamed tool input surfaces as terminal '
        'error', () async {
      var executed = false;
      final tools = <String, Tool>{
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            executed = true;
            return 'unused';
          },
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        repairToolCall: (options) => provider.ToolCall(
          toolCallId: options.toolCall.toolCallId,
          toolName: 'lookup',
          input: 'not json',
        ),
      );
      final parts = await result.stream.toList();
      final steps = await result.steps;

      expect(executed, isFalse);
      final streamToolCall = parts.whereType<ToolCallStreamPart>().single;
      expect(streamToolCall.toolCall.toolName, 'unknown_tool');
      expect(parts.last, isA<ErrorPart>());
      expect((parts.last as ErrorPart).error, isA<InvalidToolInputError>());
      expect(
          steps.single.content.whereType<provider.ToolCall>().single.toolName,
          'unknown_tool');
      expect(
        steps.single.finishReason.unified,
        provider.FinishReasonType.error,
      );
    });

    test(
        'repairToolCall returning null still records the streamed tool call '
        'before surfacing an input error', () async {
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        repairToolCall: (options) => null,
      );
      final parts = await result.stream.toList();
      final steps = await result.steps;

      expect(
        parts.whereType<ToolCallStreamPart>().single.toolCall.input,
        'not json',
      );
      expect(parts.last, isA<ErrorPart>());
      expect((parts.last as ErrorPart).error, isA<InvalidToolInputError>());
      expect(steps.single.content.whereType<provider.ToolCall>().single.input,
          'not json');
      expect(
        steps.single.finishReason.unified,
        provider.FinishReasonType.error,
      );
    });

    test(
        'repairToolCall repairs input before dynamic streamed tool approval '
        'and emit', () async {
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

      final result = streamText(
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
      final parts = await result.stream.toList();
      final steps = await result.steps;

      expect(approvalInput, {'city': 'Paris'});
      expect(executedInput, {'city': 'Paris'});
      expect(
        parts.whereType<ToolCallStreamPart>().single.toolCall.input,
        '{"city":"Paris"}',
      );
      expect(steps.single.toolCalls.single.input, '{"city":"Paris"}');
      expect(steps.single.toolResults.single.result, 'approved');
    });

    test(
        'repairToolCall repairs input before global streamed tool approval '
        'and emit', () async {
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

      final result = streamText(
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
      final parts = await result.stream.toList();
      final steps = await result.steps;

      expect(approvalInput, '{"city":"Paris"}');
      expect(executedInput, {'city': 'Paris'});
      expect(
        parts.whereType<ToolCallStreamPart>().single.toolCall.input,
        '{"city":"Paris"}',
      );
      expect(steps.single.toolResults.single.result, 'approved');
    });

    test(
        'repairToolCall rechecks approval after changing streamed tool identity',
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

      final result = streamText(
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
      final parts = await result.stream.toList();
      final steps = await result.steps;

      expect(safeExecuted, isFalse);
      expect(deleteExecuted, isFalse);
      final streamToolCall = parts.whereType<ToolCallStreamPart>().single;
      expect(streamToolCall.toolCall.toolName, 'delete_file');
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(steps.single.toolCalls.single.toolName, 'delete_file');
      expect(steps.single.toolResults.single.toolName, 'delete_file');
      expect(steps.single.toolResults.single.result, 'dangerous');
    });

    test('empty streamed tool input is normalized for response messages',
        () async {
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

      final result = streamText(model: model, prompt: 'x', tools: tools);
      await result.stream.toList();
      final steps = await result.steps;
      final responseMessages = await result.responseMessages;
      final assistant =
          responseMessages.whereType<AssistantModelMessage>().single;

      expect(executedInput, <String, Object?>{});
      expect(steps.single.toolCalls.single.input, '{}');
      expect(assistant.content.whereType<ToolCallPart>().single.input,
          <String, Object?>{});
    });

    test(
        'toolApproval userApproval is resolved after streamed repairToolCall '
        'parsing', () async {
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

      final result = streamText(
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
      final parts = await result.stream.toList();
      final steps = await result.steps;
      final responseMessages = await result.responseMessages;
      final assistant =
          responseMessages.whereType<AssistantModelMessage>().single;

      expect(repairCalled, isTrue);
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.whereType<ToolCallStreamPart>().single.toolCall.input, '{}');
      expect(steps.single.toolCalls.single.input, '{}');
      expect(steps.single.toolResults, isEmpty);
      expect(assistant.content.whereType<ToolCallPart>().single.input,
          <String, Object?>{});
    });

    test(
        'toolApproval denial is resolved before streamed repairToolCall parsing',
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

      final result = streamText(
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
      final parts = await result.stream.toList();
      final steps = await result.steps;

      expect(repairCalled, isFalse);
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(steps.single.toolResults.single.result, 'blocked');
    });

    test(
        'an invalid prompt (both prompt and messages provided) does not '
        'throw synchronously; it surfaces as a terminal ErrorPart on the '
        'stream and fires onError once', () async {
      final errors = <Object?>[];

      // 同时提供 prompt 与 messages 属于非法输入(标准化阶段互斥校验),
      // 但 streamText() 本身必须同步返回,不得抛出——校验错误应移到驱动
      // 循环的 async try 块内,作为流上的终端 ErrorPart 出现。
      late final StreamTextResult<String, String, Never> result;
      expect(
        () => result = streamText(
          model: ScriptedModel(turns: const []),
          prompt: 'x',
          messages: [UserModelMessage.text('hi')],
          onError: errors.add,
        ),
        returnsNormally,
      );

      final parts = await result.stream.toList();

      expect(parts.last, isA<ErrorPart>());
      expect(
          (parts.last as ErrorPart).error, isA<provider.InvalidPromptError>());
      expect(parts.whereType<FinishPart>(), isEmpty);
      expect(errors, hasLength(1));
      expect(errors.single, isA<provider.InvalidPromptError>());

      // Future 访问器仍需在 finally 块中正常解析(聚合 completer 不受
      // 提前抛出的校验错误影响)。
      expect(await result.text, isEmpty);
      expect(await result.steps, isEmpty);
      // 因错误终结(catch 路径):聚合 finishReason 为 error,而非默认 stop。
      expect(
        await result.finishReason,
        const provider.LanguageModelFinishReason(
          provider.FinishReasonType.error,
        ),
      );
    });

    test(
        'messages mutated synchronously after streamText() returns does not '
        'affect the already-snapshotted prompt (a call valid at invocation '
        'stays valid; validation reads the immutable snapshot)', () async {
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
      final messages = <ModelMessage>[UserModelMessage.text('hi')];

      final result = streamText(model: model, messages: messages);
      // streamText() 同步返回后、驱动 microtask 运行前,同步把 caller 的列表
      // 改成「非法」状态(混入 system 消息 → 若校验读的是原列表会触发
      // InvalidPromptError)。快照已在 streamText() 内捕获,本调用不受影响。
      messages.add(const SystemModelMessage('sys'));

      final parts = await result.stream.toList();

      // 未被后置改动污染:无 ErrorPart,正常以 FinishPart 收尾。
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.whereType<FinishPart>(), hasLength(1));
      // 模型收到的是快照时刻的单条 user prompt(system 未混入)。
      final sentPrompt = model.receivedCallOptions.single.prompt;
      expect(sentPrompt, hasLength(1));
      expect(sentPrompt.single, isA<provider.UserMessage>());
    });

    test(
        'a message content list mutated synchronously after streamText() '
        'returns does not change the prompt sent to the model (conversion '
        'materializes an immutable snapshot at invocation time)', () async {
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
      // caller 持有某条消息的内部 content 子列表,并在 streamText() 返回后改动它。
      final parts = <UserContentPart>[TextPart('a')];
      final result = streamText(
        model: model,
        messages: [UserModelMessage(parts)],
      );
      parts.add(TextPart('b'));

      await result.consumeStream();

      // 发给模型的是调用时刻转换出的不可变快照:只含 'a',不受后置 add('b') 影响
      // (外层 list 冻结之外,消息内部 content 亦被转换固化)。
      final sentPrompt = model.receivedCallOptions.single.prompt;
      final userMessage = sentPrompt.single as provider.UserMessage;
      expect(userMessage.content, hasLength(1));
      expect((userMessage.content.single as provider.TextPart).text, 'a');
    });
  });

  group('streamText tool set snapshot', () {
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

      final result = streamText(model: model, prompt: 'x', tools: tools);
      final steps = await result.steps;

      // 快照生效:echo 仍按名命中并执行(结果 'R'),而非因原 map 被清空被当作
      // blocking 从而无结果。
      expect(steps.single.toolResults, hasLength(1));
      expect(steps.single.toolResults.single.result, 'R');
    });

    test(
        'clearing the caller-owned tools map synchronously after streamText() '
        'returns (before the deferred driver runs) does not drop the tool: '
        'the snapshot is taken at invocation time, not inside the driver',
        () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'R',
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
      ]);

      final result = streamText(model: model, prompt: 'x', tools: tools);
      // streamText() 已同步返回、驱动 microtask 尚未运行:此刻清空原 map。
      tools.clear();

      final steps = await result.steps;

      // 调用时刻已拍快照,echo 仍执行(结果 'R'),不受返回后清空影响。
      expect(steps.single.toolResults, hasLength(1));
      expect(steps.single.toolResults.single.result, 'R');
    });

    test(
        'nested runtime and tool contexts are snapshotted before the deferred '
        'driver runs', () async {
      final toolContexts = <Object?>[];
      final runtimeDetails = <String, Object?>{
        'phase': 'initial',
        'tags': <Object?>['one'],
      };
      final runtimeContext = <String, Object?>{
        'request': runtimeDetails,
      };
      final toolDetails = <String, Object?>{
        'apiKey': 'initial-key',
        'scopes': <Object?>['read'],
      };
      final toolsContext = <String, Object?>{
        'echo': toolDetails,
      };
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async {
            toolContexts.add(options.context);
            return 'R';
          },
        ),
      };
      final seenRuntimeContexts = <Map<String, Object?>>[];
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
      ]);

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        runtimeContext: runtimeContext,
        toolsContext: toolsContext,
        prepareStep: (options) {
          seenRuntimeContexts.add(options.runtimeContext);
          return null;
        },
      );
      runtimeDetails['phase'] = 'mutated';
      (runtimeDetails['tags'] as List<Object?>).add('two');
      runtimeContext['extra'] = true;
      toolDetails['apiKey'] = 'mutated-key';
      (toolDetails['scopes'] as List<Object?>).add('write');
      toolsContext['other'] = {'apiKey': 'other'};

      final steps = await result.steps;

      expect(seenRuntimeContexts, const [
        {
          'request': {
            'phase': 'initial',
            'tags': ['one'],
          },
        },
      ]);
      expect(toolContexts, const [
        {
          'apiKey': 'initial-key',
          'scopes': ['read'],
        },
      ]);
      expect(steps.single.runtimeContext, const {
        'request': {
          'phase': 'initial',
          'tags': ['one'],
        },
      });
      expect(steps.single.toolsContext, const {
        'echo': {
          'apiKey': 'initial-key',
          'scopes': ['read'],
        },
      });
      final stepRuntimeContext =
          steps.single.runtimeContext['request']! as Map<String, Object?>;
      expect(
        () => stepRuntimeContext['phase'] = 'later',
        throwsUnsupportedError,
      );
      expect(
        () => (stepRuntimeContext['tags'] as List<Object?>).add('later'),
        throwsUnsupportedError,
      );
      final stepToolContext =
          steps.single.toolsContext['echo']! as Map<String, Object?>;
      expect(
        () => stepToolContext['apiKey'] = 'later',
        throwsUnsupportedError,
      );
      expect(
        () => (stepToolContext['scopes'] as List<Object?>).add('admin'),
        throwsUnsupportedError,
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

      final result = streamText(model: model, prompt: 'x', tools: tools);
      await result.consumeStream();

      // provider/中间件对 options.tools 的原地改动会响亮失败,而非静默污染
      // 后续步的广告集。
      final sentTools = model.receivedCallOptions.single.tools!;
      expect(() => sentTools.clear(), throwsUnsupportedError);
    });

    test('activeTools limits the tools advertised to the streamed model',
        () async {
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        activeTools: const ['echo'],
      );
      await result.consumeStream();

      expect(
        model.receivedCallOptions.single.tools!
            .whereType<provider.FunctionTool>()
            .map((tool) => tool.name),
        ['echo'],
      );
    });

    test('activeTools drops stale forced tool choices for streamed calls',
        () async {
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        activeTools: const ['echo'],
        toolChoice: const provider.ToolChoiceTool('search'),
      );
      await result.consumeStream();

      expect(model.receivedCallOptions.single.toolChoice, isNull);
    });

    test('toolOrder sends listed tools first for streamed calls', () async {
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        toolOrder: const ['middle'],
      );
      await result.consumeStream();

      expect(
        model.receivedCallOptions.single.tools!
            .whereType<provider.FunctionTool>()
            .map((tool) => tool.name),
        ['middle', 'alpha', 'zebra'],
      );
    });

    test('prepareStep can override tool order for streamed calls', () async {
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        prepareStep: (options) => PrepareStepResult(
          toolOrder: const ['middle'],
        ),
      );
      await result.consumeStream();

      expect(
        model.receivedCallOptions.single.tools!
            .whereType<provider.FunctionTool>()
            .map((tool) => tool.name),
        ['middle', 'alpha', 'zebra'],
      );
    });

    test('prepareStep can override messages for streamed later steps',
        () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'echoed',
        ),
      };
      final seenStepNumbers = <int>[];
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

      final result = streamText(
        model: model,
        prompt: 'original',
        tools: tools,
        stopWhen: isStepCount(2),
        prepareStep: (options) {
          seenStepNumbers.add(options.stepNumber);
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
      await result.consumeStream();

      expect(seenStepNumbers, [0, 1]);
      final secondPrompt = model.receivedCallOptions[1].prompt;
      expect(secondPrompt, hasLength(1));
      final user = secondPrompt.single as provider.UserMessage;
      expect((user.content.single as provider.TextPart).text, 'compacted');
    });

    test('runtime and tool contexts carry forward through streamed steps',
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        runtimeContext: const {'phase': 'initial'},
        toolsContext: const {
          'lookup': {'apiKey': 'initial-key'},
        },
        stopWhen: isStepCount(2),
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
      await result.consumeStream();
      final steps = await result.steps;

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
      expect(steps[0].runtimeContext, const {'phase': 'tool'});
      expect(steps[0].toolsContext, const {
        'lookup': {'apiKey': 'tool-key'},
      });
      expect((await result.finalStep).runtimeContext, const {'phase': 'final'});
      expect((await result.finalStep).toolsContext, const {
        'lookup': {'apiKey': 'tool-key'},
      });
    });
  });

  group('streamText prompt message freezing', () {
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        stopWhen: isStepCount(2),
      );
      await result.consumeStream();

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
  });

  group('streamText stopWhen snapshot', () {
    test(
        'stopWhen receives a read-only steps snapshot: a predicate that '
        'mutates it surfaces as a terminal ErrorPart (loop state is not '
        'corrupted)', () async {
      final errors = <Object?>[];
      bool clearingStop(List<StepResult> steps) {
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

      final result = streamText(
        model: model,
        prompt: 'x',
        stopWhen: clearingStop,
        onError: errors.add,
      );
      final parts = await result.stream.toList();

      // 谓词对只读快照 clear() 抛 UnsupportedError → 驱动内捕获为终端 ErrorPart
      // (error-as-terminal:其后无 FinishPart),循环内部 steps 未被污染。
      expect(parts.last, isA<ErrorPart>());
      expect((parts.last as ErrorPart).error, isA<UnsupportedError>());
      expect(parts.whereType<FinishPart>(), isEmpty);
      expect(errors.single, isA<UnsupportedError>());
    });

    test(
        'a list-valued stopWhen is snapshotted at invocation: clearing the '
        'caller-owned list after streamText() returns does not change the '
        'stopping behavior', () async {
      final tools = <String, Tool>{
        'echo': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'r',
        ),
      };
      final model = ScriptedModel(turns: [
        // step 1:工具调用 → 执行 → isStepCount(2) 未满足 → 续。
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
        // step 2:文本 → isStepCount(2) 满足 → 停。
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

      // 列表推断为 List<StopCondition>,可增删。
      final stopWhen = [isStepCount(2)];
      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        stopWhen: stopWhen,
      );
      // 返回后、驱动运行前清空原列表:若未快照,驱动会看到空停条件 → 单步收尾。
      stopWhen.clear();

      final steps = await result.steps;
      // 快照保留了 isStepCount(2):循环跑满两步。
      expect(steps, hasLength(2));
    });
  });

  group('streamText step framing', () {
    test(
        'a late StreamStart after content does not emit a second '
        'StartStepPart (step framing is not duplicated)', () async {
      final result = streamText(model: LateStreamStartModel(), prompt: 'x');
      final parts = await result.stream.toList();

      // 兜底已补发一个 StartStepPart;迟到的 StreamStart 不应再补一个。
      expect(parts.whereType<StartStepPart>(), hasLength(1));
    });
  });

  group('streamText stopSequences snapshot', () {
    test(
        'a list-valued stopSequences is snapshotted at invocation: clearing '
        'the caller-owned list after streamText() returns does not change the '
        'stop sequences sent to the model', () async {
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
      final result =
          streamText(model: model, prompt: 'x', stopSequences: stopSequences);
      // streamText() 已同步返回、驱动 microtask 尚未运行:此刻清空原列表。
      stopSequences.clear();

      await result.consumeStream();

      // 驱动用的是调用时刻的快照,停用词仍为 ['STOP']。
      expect(model.receivedCallOptions.single.stopSequences, ['STOP']);
    });
  });

  group('streamText preserves streamed content', () {
    test(
        'a streamed non-text LanguageModelContent (SourceContent) is kept in '
        'step content instead of being dropped at the default branch',
        () async {
      final result = streamText(model: SourceContentStreamModel(), prompt: 'x');
      final steps = await result.steps;

      // 与非流式 result.content 一致:内容型分块被保留进 step.content。
      final sources =
          steps.single.content.whereType<provider.SourceContent>().toList();
      expect(sources, hasLength(1));
      expect(sources.single.id, 's1');
      // Source metadata is preserved but is not semantic generated content;
      // it must not satisfy first/chunk timeout or performance clocks.
      expect(steps.single.performance.timeToFirstOutput, isNull);
      expect(steps.single.performance.outputTokensPerSecond, isNull);
      expect(steps.single.performance.timeBetweenOutputChunks, isNull);
    });

    test(
        'streamed reasoning (ReasoningStart/Delta/End) is preserved as '
        'ReasoningContent in step content and responseMessages', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ReasoningContent('think'),
            provider.TextContent('ok'),
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

      final result = streamText(model: model, prompt: 'x');
      await result.consumeStream();

      final steps = await result.steps;
      expect(
        steps.single.content.whereType<provider.ReasoningContent>().single.text,
        'think',
      );
      // 推理不混入文本聚合。
      expect(await result.text, 'ok');
      // 公开续接路径同样保留(用户面 ReasoningPart)。
      final assistant = (await result.responseMessages)
          .whereType<AssistantModelMessage>()
          .single;
      expect(
        assistant.content.whereType<ReasoningPart>().single.text,
        'think',
      );
    });

    test(
        'stream event providerMetadata (ReasoningStart/End, TextStart/End) '
        'is captured into the aggregated content item and carried through '
        'to the rebuilt assistant message providerOptions (End overrides '
        'Start when both are non-null, per upstream merge semantics)',
        () async {
      final model = MetadataOnStartAndEndStreamModel();

      final result = streamText(model: model, prompt: 'x');
      await result.consumeStream();

      final steps = await result.steps;
      final reasoningContent =
          steps.single.content.whereType<provider.ReasoningContent>().single;
      expect(reasoningContent.text, 'think');
      expect(reasoningContent.providerMetadata, {
        'openai': {'itemId': 'rs_1', 'reasoningEncryptedContent': 'enc'},
      });

      final textContent =
          steps.single.content.whereType<provider.TextContent>().single;
      expect(textContent.text, 'ok');
      expect(textContent.providerMetadata, {
        'openai': {'itemId': 'msg_1', 'refined': true},
      });

      // 端到端:经 _toAssistantMessage 重建的续接历史消息里,part 的
      // providerOptions 同值(而非 End 的 metadata 在重建时丢失)。
      final assistant = (await result.responseMessages)
          .whereType<AssistantModelMessage>()
          .single;
      final reasoningPart = assistant.content.whereType<ReasoningPart>().single;
      expect(reasoningPart.providerOptions, {
        'openai': {'itemId': 'rs_1', 'reasoningEncryptedContent': 'enc'},
      });
      final textPart = assistant.content.whereType<TextPart>().single;
      expect(textPart.providerOptions, {
        'openai': {'itemId': 'msg_1', 'refined': true},
      });
    });

    test('public stream forwards text and reasoning providerMetadata',
        () async {
      final model = MetadataOnStartAndEndStreamModel();

      final parts = await streamText(model: model, prompt: 'x').stream.toList();

      expect(
        parts.whereType<ReasoningStartPart>().single,
        const ReasoningStartPart(
          'reasoning-0',
          providerMetadata: {
            'openai': {'itemId': 'rs_1'},
          },
        ),
      );
      expect(
        parts.whereType<ReasoningDeltaPart>().single,
        const ReasoningDeltaPart('reasoning-0', 'think'),
      );
      expect(
        parts.whereType<ReasoningEndPart>().single,
        const ReasoningEndPart(
          'reasoning-0',
          providerMetadata: {
            'openai': {
              'itemId': 'rs_1',
              'reasoningEncryptedContent': 'enc',
            },
          },
        ),
      );
      expect(
        parts.whereType<TextStartPart>().single,
        const TextStartPart(
          'text-0',
          providerMetadata: {
            'openai': {'itemId': 'msg_1'},
          },
        ),
      );
      expect(
        parts.whereType<TextDeltaPart>().single,
        const TextDeltaPart('text-0', 'ok'),
      );
      expect(
        parts.whereType<TextEndPart>().single,
        const TextEndPart(
          'text-0',
          providerMetadata: {
            'openai': {'itemId': 'msg_1', 'refined': true},
          },
        ),
      );
    });
  });

  group('streamText tool result content', () {
    test(
        'ToolResultContentOutput file items keep their data payload in the '
        'streamed tool result (not just mediaType/filename)', () async {
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

      final result = streamText(model: model, prompt: 'x', tools: tools);
      final steps = await result.steps;
      final flattened =
          steps.single.toolResults.single.result as Map<String, Object?>;
      final items = flattened['items'] as List<Object?>;
      final fileItem = items.single as Map<String, Object?>;

      // 关键:流式路径同样保留 data 载荷。
      expect(fileItem['data'], provider.FileDataBase64('AAA='));
    });

    test(
        'a tool returning null keeps null in the streamed toolResults.result '
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

      final result = streamText(model: model, prompt: 'x', tools: tools);
      final steps = await result.steps;

      // 流式路径同样原样保留 null(与非流式一致)。
      expect(steps.single.toolResults, hasLength(1));
      expect(steps.single.toolResults.single.result, isNull);
    });
  });

  group('streamText continued assistant content', () {
    test(
        'representable non-text content (file/reasoning-file/custom) produced '
        'with a tool call is reconstructed into the next turn prompt',
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

      final result = streamText(
        model: model,
        prompt: 'x',
        tools: tools,
        stopWhen: isStepCount(2),
      );
      await result.consumeStream();

      // 第二次调用的 prompt 含 step1 重建的 assistant 消息,非文本内容被保留。
      final assistant = model.receivedCallOptions[1].prompt
          .whereType<provider.AssistantMessage>()
          .single;
      final filePart = assistant.content.whereType<provider.FilePart>().single;
      expect(filePart.data, provider.FileDataBase64('AAA='));
      expect(
        assistant.content
            .whereType<provider.ReasoningFilePart>()
            .single
            .mediaType,
        'application/json',
      );
      expect(
        assistant.content.whereType<provider.CustomPart>().single.kind,
        'ns.custom',
      );
    });

    test(
        'representable non-text content (file/reasoning-file/custom) is '
        'preserved in the public responseMessages continuation path', () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.FileContent(
              data: provider.FileDataBase64('AAA='),
              mediaType: 'image/png',
            ),
            provider.ReasoningFileContent(
              data: provider.FileDataBase64('BBB='),
              mediaType: 'application/json',
            ),
            provider.CustomContentBlock('ns.custom'),
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

      final result = streamText(model: model, prompt: 'x');
      await result.consumeStream();

      // 公开续接路径:responseMessages 的 assistant 消息保留非文本 part
      // (用户面类型,供调用方直接续接进下一轮请求)。
      final assistant = (await result.responseMessages)
          .whereType<AssistantModelMessage>()
          .single;
      final filePart = assistant.content.whereType<FilePart>().single;
      expect(filePart.mediaType, 'image/png');
      expect(filePart.data, const DataBase64('AAA='));
      expect(
        assistant.content.whereType<ReasoningFilePart>().single.data,
        const DataBase64('BBB='),
      );
      expect(
        assistant.content.whereType<CustomPart>().single.kind,
        'ns.custom',
      );
    });
  });

  group('preliminary ToolResult replacement', () {
    test(
        'a preliminary ToolResult followed by a final ToolResult for the '
        'same toolCallId emits both as stream events, but the accumulated '
        'step content/toolResults/responseMessages keep only the final one',
        () async {
      final model = ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-1',
              toolName: 'search',
              input: '{}',
              providerExecuted: true,
            ),
            // provider 侧先流出一个可替换的部分结果……
            provider.ToolResult(
              toolCallId: 'call-1',
              toolName: 'search',
              result: 'partial',
              preliminary: true,
            ),
            // ……随后流出同一 toolCallId 的最终结果,应替换掉上面那条。
            provider.ToolResult(
              toolCallId: 'call-1',
              toolName: 'search',
              result: 'final',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 3),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]);

      final result = streamText(model: model, prompt: 'hi');

      final parts = await result.stream.toList();

      // (a) 流上仍能看到两个独立的 ToolResultStreamPart 事件。
      final streamedResults =
          parts.whereType<ToolResultStreamPart>().map((p) => p.toolResult);
      expect(streamedResults, hasLength(2));
      expect(streamedResults.map((r) => r.result), ['partial', 'final']);

      // (b) 累积的 StepResult.content/toolResults 中,该 toolCallId 只剩一条,
      // 且值为最终结果。
      final steps = await result.steps;
      final step = steps.single;
      final accumulatedResults =
          step.content.whereType<provider.ToolResult>().where(
                (r) => r.toolCallId == 'call-1',
              );
      expect(accumulatedResults, hasLength(1));
      expect(accumulatedResults.single.result, 'final');

      // (c) responseMessages 中重建的 assistant 消息也只含最终结果。
      final responseMessages = await result.responseMessages;
      final assistantMessage =
          responseMessages.whereType<AssistantModelMessage>().single;
      final toolResultParts = assistantMessage.content
          .whereType<ToolResultPart>()
          .where((p) => p.toolCallId == 'call-1');
      expect(toolResultParts, hasLength(1));
      expect(
        (toolResultParts.single.output as provider.ToolResultJson).value,
        'final',
      );
    });
  });

  group('StreamTextResult buffered replay', () {
    ScriptedModel singleTurnModel() => ScriptedModel(turns: [
          const ScriptedTurn(
            content: [provider.TextContent('Hello, world!')],
            finishReason: provider.LanguageModelFinishReason(
              provider.FinishReasonType.stop,
            ),
            usage: provider.LanguageModelUsage(
              inputTokens: provider.InputTokens(total: 5),
              outputTokens: provider.OutputTokens(total: 2),
            ),
          ),
        ]);

    test(
        'late subscription after awaiting a Future accessor still yields '
        'the full ordered part sequence', () async {
      final result = streamText(model: singleTurnModel(), prompt: 'hi');

      // 先消费 Future 访问器,此时驱动循环大概率已经跑完并把分块写进缓冲。
      final text = await result.text;
      expect(text, 'Hello, world!');

      // 之后才订阅 `.stream`:buffered-replay 必须重放完整分块序列。
      final parts = await result.stream.toList();
      expect(parts, isNotEmpty);
      expect(parts.first, isA<StartPart>());
      expect(parts.last, isA<FinishPart>());
      expect(parts.whereType<TextDeltaPart>(), isNotEmpty);
      expect(
        parts.whereType<TextDeltaPart>().map((p) => p.delta).join(),
        'Hello, world!',
      );
    });

    test(
        'subscription after an intervening microtask/event-loop turn '
        'still receives the full sequence', () async {
      final result = streamText(model: singleTurnModel(), prompt: 'hi');

      // 让出事件循环,使驱动循环有机会开始(甚至跑完)产出分块。
      await Future<void>.delayed(Duration.zero);

      final parts = await result.stream.toList();
      expect(parts.first, isA<StartPart>());
      expect(parts.last, isA<FinishPart>());
      expect(
        parts.whereType<TextDeltaPart>().map((p) => p.delta).join(),
        'Hello, world!',
      );
    });

    test(
        'stream can be consumed twice; both consumptions yield the full '
        'sequence', () async {
      final result = streamText(model: singleTurnModel(), prompt: 'hi');

      final firstConsumption = await result.stream.toList();
      final secondConsumption = await result.stream.toList();

      expect(firstConsumption, isNotEmpty);
      expect(secondConsumption, firstConsumption);
    });
  });
}

final class _DelayedOutputStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'delayed-output';

  @override
  String get modelId => 'delayed-output-model';

  @override
  Map<String, List<RegExp>> get supportedUrls => const {};

  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) async =>
      throw UnimplementedError();

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async =>
      lm.LanguageModelStreamResult(stream: _stream());

  Stream<lm.LanguageModelStreamPart> _stream() async* {
    yield lm.StreamStart(const []);
    yield lm.TextStart('text-0');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    yield lm.TextDelta('text-0', 'he');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    yield lm.TextDelta('text-0', 'llo');
    yield lm.TextEnd('text-0');
    yield const lm.FinishPart(
      usage: lm.LanguageModelUsage(
        inputTokens: lm.InputTokens(total: 4),
        outputTokens: lm.OutputTokens(total: 2),
      ),
      finishReason: lm.LanguageModelFinishReason(
        lm.FinishReasonType.stop,
      ),
    );
  }
}

final class GatedJsonStreamModel implements lm.LanguageModel {
  GatedJsonStreamModel(this.text);

  final String text;
  final Completer<void> _finishGate = Completer<void>();

  bool get finishReleased => _finishGate.isCompleted;

  void releaseFinish() {
    if (!_finishGate.isCompleted) {
      _finishGate.complete();
    }
  }

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'gated-json';

  @override
  String get modelId => 'gated-json-model';

  @override
  Map<String, List<RegExp>> get supportedUrls => const {};

  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) async =>
      throw UnimplementedError();

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async {
    return lm.LanguageModelStreamResult(stream: _stream());
  }

  Stream<lm.LanguageModelStreamPart> _stream() async* {
    yield lm.StreamStart(const []);
    yield lm.TextStart('text-0');
    yield lm.TextDelta('text-0', text);
    await _finishGate.future;
    yield lm.TextEnd('text-0');
    yield const lm.FinishPart(
      usage: lm.LanguageModelUsage(
        inputTokens: lm.InputTokens(total: 1),
        outputTokens: lm.OutputTokens(total: 1),
      ),
      finishReason: lm.LanguageModelFinishReason(
        lm.FinishReasonType.stop,
      ),
    );
  }
}
