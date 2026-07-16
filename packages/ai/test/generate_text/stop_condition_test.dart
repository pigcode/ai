import 'package:pigcode_ai/src/generate_text/step_result.dart';
import 'package:pigcode_ai/src/generate_text/stop_condition.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

/// 构造一个最小可用的 [StepResult],用于驱动 stop-condition 断言;
/// 除测试关心的字段外均取最简值。
StepResult _step({
  List<provider.LanguageModelContent> content = const [],
}) {
  return StepResult(
    content: content,
    finishReason: const provider.LanguageModelFinishReason(
      provider.FinishReasonType.stop,
    ),
    usage: const provider.LanguageModelUsage(
      inputTokens: provider.InputTokens(),
      outputTokens: provider.OutputTokens(),
    ),
    response: null,
    executedToolResults: const [],
    performance: StepResultPerformance.empty(),
  );
}

provider.ToolCall _toolCall(String name) => provider.ToolCall(
      toolCallId: 'call-$name',
      toolName: name,
      input: '{}',
    );

void main() {
  group('isStepCount', () {
    test('步数小于 n 时返回 false', () async {
      final condition = isStepCount(3);
      final steps = [_step(), _step()];

      expect(await condition(steps), isFalse);
    });

    test('步数恰好等于 n 时返回 true(边界)', () async {
      final condition = isStepCount(3);
      final steps = [_step(), _step(), _step()];

      expect(await condition(steps), isTrue);
    });

    test('步数大于 n 时返回 false', () async {
      final condition = isStepCount(2);
      final steps = [_step(), _step(), _step()];

      expect(await condition(steps), isFalse);
    });

    test('空步骤列表且 n 为 0 时返回 true', () async {
      final condition = isStepCount(0);

      expect(await condition(const []), isTrue);
    });
  });

  group('isLoopFinished', () {
    test('始终返回 false', () async {
      final condition = isLoopFinished();

      expect(await condition(const []), isFalse);
      expect(await condition([_step()]), isFalse);
    });
  });

  group('hasToolCall', () {
    test('步骤为空时返回 false', () async {
      final condition = hasToolCall('search');

      expect(await condition(const []), isFalse);
    });

    test('最后一步包含匹配的工具调用时返回 true', () async {
      final condition = hasToolCall('search');
      final steps = [
        _step(),
        _step(content: [_toolCall('search')]),
      ];

      expect(await condition(steps), isTrue);
    });

    test('最后一步只包含不同名的工具调用时返回 false', () async {
      final condition = hasToolCall('search');
      final steps = [
        _step(content: [_toolCall('search')]),
        _step(content: [_toolCall('other')]),
      ];

      expect(await condition(steps), isFalse);
    });

    test('只有更早的步骤命中、最后一步未命中时返回 false', () async {
      final condition = hasToolCall('search');
      final steps = [
        _step(content: [_toolCall('search')]),
        _step(),
      ];

      expect(await condition(steps), isFalse);
    });

    test('最后一步包含任一匹配工具调用时返回 true', () async {
      final condition = hasToolCall('search', ['lookup']);
      final steps = [
        _step(content: [_toolCall('lookup')]),
      ];

      expect(await condition(steps), isTrue);
    });
  });
}
