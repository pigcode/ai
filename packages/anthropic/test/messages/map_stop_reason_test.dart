import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('mapAnthropicStopReason', () {
    test('pause_turn / end_turn / stop_sequence 映射为 stop', () {
      for (final stopReason in ['pause_turn', 'end_turn', 'stop_sequence']) {
        final result = mapAnthropicStopReason(
          stopReason,
          isJsonResponseFromTool: false,
        );
        expect(result.unified, FinishReasonType.stop, reason: stopReason);
        expect(result.raw, stopReason);
      }
    });

    test('refusal 映射为 contentFilter', () {
      final result = mapAnthropicStopReason(
        'refusal',
        isJsonResponseFromTool: false,
      );
      expect(result.unified, FinishReasonType.contentFilter);
      expect(result.raw, 'refusal');
    });

    test('tool_use 且非 json 响应工具模式映射为 toolCalls', () {
      final result = mapAnthropicStopReason(
        'tool_use',
        isJsonResponseFromTool: false,
      );
      expect(result.unified, FinishReasonType.toolCalls);
      expect(result.raw, 'tool_use');
    });

    test('tool_use 且 json 响应工具模式映射为 stop', () {
      final result = mapAnthropicStopReason(
        'tool_use',
        isJsonResponseFromTool: true,
      );
      expect(result.unified, FinishReasonType.stop);
      expect(result.raw, 'tool_use');
    });

    test('max_tokens / model_context_window_exceeded 映射为 length', () {
      for (final stopReason in [
        'max_tokens',
        'model_context_window_exceeded',
      ]) {
        final result = mapAnthropicStopReason(
          stopReason,
          isJsonResponseFromTool: false,
        );
        expect(result.unified, FinishReasonType.length, reason: stopReason);
        expect(result.raw, stopReason);
      }
    });

    test('compaction 映射为 other', () {
      final result = mapAnthropicStopReason(
        'compaction',
        isJsonResponseFromTool: false,
      );
      expect(result.unified, FinishReasonType.other);
      expect(result.raw, 'compaction');
    });

    test('未知字符串映射为 other 且 raw 保留原文', () {
      final result = mapAnthropicStopReason(
        'whatever_else',
        isJsonResponseFromTool: false,
      );
      expect(result.unified, FinishReasonType.other);
      expect(result.raw, 'whatever_else');
    });

    test('null 映射为 other 且 raw 为 null', () {
      final result = mapAnthropicStopReason(
        null,
        isJsonResponseFromTool: false,
      );
      expect(result.unified, FinishReasonType.other);
      expect(result.raw, isNull);
    });
  });
}
