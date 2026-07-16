import 'package:pigcode_ai/src/generate_text/generate_text.dart';
import 'package:pigcode_ai/src/generate_text/stop_condition.dart'
    show isStepCount;
import 'package:pigcode_ai/src/generate_text/stream_text.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

/// 标 true 工厂形态的 provider 工具:镜像 anthropic 工厂产物形状(ai 测试
/// 不得依赖 anthropic 包,id 仅是字符串,契约字段即 T1/T11 工厂自带的标记)。
Tool _deferredCodeExecution() => Tool.provider(
      const provider.ProviderTool(
        id: 'anthropic.code_execution_20250825',
        name: 'code_execution',
        args: <String, Object?>{},
        supportsDeferredResults: true,
      ),
    );

const _turn1Metadata = <String, Map<String, Object?>>{
  'anthropic': <String, Object?>{
    'container': <String, Object?>{'id': 'cont_1'},
  },
};

List<ScriptedTurn> _turns() => const [
      // 第 1 步:providerExecuted 调用、无同轮结果 → pending 追踪(T6/T7);
      // 结果级 providerMetadata 供 StepResult 带出断言(T3)。
      ScriptedTurn(
        content: [
          provider.ToolCall(
            toolCallId: 'srvtoolu_1',
            toolName: 'code_execution',
            input: '{"code":"print(1)"}',
            providerExecuted: true,
          ),
        ],
        finishReason: provider.LanguageModelFinishReason(
          provider.FinishReasonType.toolCalls,
        ),
        usage: provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(total: 4),
          outputTokens: provider.OutputTokens(total: 2),
        ),
        providerMetadata: _turn1Metadata,
      ),
      // 第 2 步:deferred 结果跨轮到达(本轮无配对 tool-call)→ 解销并
      // 停止;结果静默透传进当轮 step 内容(报告 10 §8.9 零代码等价)。
      ScriptedTurn(
        content: [
          provider.ToolResult(
            toolCallId: 'srvtoolu_1',
            toolName: 'code_execution',
            result: <String, Object?>{
              'type': 'code_execution_result',
              'stdout': '1\n',
              'stderr': '',
              'return_code': 0,
            },
          ),
          provider.TextContent('done'),
        ],
        finishReason: provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        ),
        usage: provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(total: 5),
          outputTokens: provider.OutputTokens(total: 1),
        ),
      ),
    ];

void main() {
  group('provider 工具自动续接端到端(标 true 工厂形态)', () {
    test('generateText:无同轮结果 → 续接 → 次轮解销;providerMetadata 带出;无空 tool 消息',
        () async {
      final model = ScriptedModel(turns: _turns());
      final result = await generateText(
        model: model,
        tools: {'code_execution': _deferredCodeExecution()},
        prompt: 'run',
        stopWhen: isStepCount(3),
      );

      // 解销后停止:恰 2 步(stopWhen 允许 3 步,停在 2 证明由解销驱动)。
      expect(model.callCount, 2);
      expect(result.steps, hasLength(2));

      // StepResult.providerMetadata 带出(T3)。
      expect(result.steps.first.providerMetadata, _turn1Metadata);

      // pending-only 续接不产空 tool 消息:次轮 prompt 只追加 assistant。
      final secondPrompt = model.receivedCallOptions[1].prompt;
      expect(secondPrompt.whereType<provider.ToolMessage>(), isEmpty);
      expect(secondPrompt.last, isA<provider.AssistantMessage>());

      // 跨轮 deferred 结果进当轮 step 内容(不抛错、不丢弃)。
      expect(
        result.steps.last.content
            .whereType<provider.ToolResult>()
            .single
            .toolCallId,
        'srvtoolu_1',
      );

      // responseMessages 公开面同约束:无 tool role 消息。
      expect(result.responseMessages.whereType<ToolModelMessage>(), isEmpty);
      expect(result.text, 'done');
    });

    test('streamText:同构续接 + FinishPart providerMetadata 带出', () async {
      final model = ScriptedModel(turns: _turns());
      final result = streamText(
        model: model,
        tools: {'code_execution': _deferredCodeExecution()},
        prompt: 'run',
        stopWhen: isStepCount(3),
      );
      await result.stream.toList();

      expect(model.callCount, 2);
      final steps = await result.steps;
      expect(steps, hasLength(2));
      expect(steps.first.providerMetadata, _turn1Metadata);

      final secondPrompt = model.receivedCallOptions[1].prompt;
      expect(secondPrompt.whereType<provider.ToolMessage>(), isEmpty);
      expect(secondPrompt.last, isA<provider.AssistantMessage>());

      expect(
        steps.last.content.whereType<provider.ToolResult>().single.toolCallId,
        'srvtoolu_1',
      );
      expect(
        (await result.responseMessages).whereType<ToolModelMessage>(),
        isEmpty,
      );
    });
  });
}
