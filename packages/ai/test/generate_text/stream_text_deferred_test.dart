import 'package:pigcode_ai/src/generate_text/stop_condition.dart'
    show isStepCount;
import 'package:pigcode_ai/src/generate_text/stream_text.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

void main() {
  group('streamText provider 工具自动续接(deferred)', () {
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
        '① deferred 工具无同轮结果 → 续接;次轮结果解销后停止,'
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

      final result = streamText(
        model: model,
        prompt: 'run code',
        tools: deferredTools(),
        stopWhen: isStepCount(5),
      );
      await result.consumeStream();

      final steps = await result.steps;
      expect(steps, hasLength(2));
      expect(model.callCount, 2);
      expect(
        steps.last.content.whereType<provider.ToolResult>().single.toolCallId,
        'call-1',
      );
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

      final result = streamText(
        model: model,
        prompt: 'run code',
        tools: <String, Tool>{
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
      await result.consumeStream();

      expect(await result.steps, hasLength(1));
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

      final result = streamText(
        model: model,
        prompt: 'run code',
        tools: deferredTools(),
        stopWhen: isStepCount(1),
      );
      await result.consumeStream();

      expect(await result.steps, hasLength(1));
      expect(model.callCount, 1);
    });

    test('④ blocking(无 execute 悬置)与 pending 并存 → 仍续接', () async {
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

      final result = streamText(
        model: model,
        prompt: 'run code',
        tools: tools,
        stopWhen: isStepCount(5),
      );
      await result.consumeStream();

      expect(await result.steps, hasLength(2));
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

      final result = streamText(
        model: model,
        prompt: 'run code',
        tools: tools,
        stopWhen: isStepCount(5),
      );
      await result.consumeStream();

      expect(await result.steps, hasLength(1));
      expect(model.callCount, 1);
    });

    test('⑥ pending-only 续接的公开 responseMessages 只含 assistant 消息', () async {
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

      final result = streamText(
        model: model,
        prompt: 'run code',
        tools: deferredTools(),
        stopWhen: isStepCount(5),
      );
      await result.consumeStream();

      // 两步各贡献一条 assistant 消息;pending-only 步与末步均不产生
      // 空 ToolModelMessage。
      final responseMessages = await result.responseMessages;
      expect(
        responseMessages.whereType<AssistantModelMessage>(),
        hasLength(2),
      );
      expect(responseMessages.whereType<ToolModelMessage>(), isEmpty);
    });

    test('⑦ pending 支不受 finishReason 闸门约束:悬置轮 stop 仍续接', () async {
      // deferred 悬置步的 finishReason 未必是 toolCalls(spec §4.2):pending
      // 支与 client-complete 支平级 OR,锁定该旁路防未来误并回
      // isToolCallsFinish 闸门(与 tool_loop_test ⑦ 双路同型)。
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

      final result = streamText(
        model: model,
        prompt: 'run code',
        tools: deferredTools(),
        stopWhen: isStepCount(5),
      );
      await result.consumeStream();

      final steps = await result.steps;
      expect(steps, hasLength(2));
      expect(model.callCount, 2);
      expect(
        steps.last.content.whereType<provider.ToolResult>().single.toolCallId,
        'call-1',
      );
    });
  });
}
