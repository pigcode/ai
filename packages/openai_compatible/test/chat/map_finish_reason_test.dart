import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('mapOpenAiCompatibleFinishReason', () {
    test('stop', () {
      final result = mapOpenAiCompatibleFinishReason('stop');
      expect(result.unified, FinishReasonType.stop);
      expect(result.raw, 'stop');
    });

    test('length', () {
      expect(
        mapOpenAiCompatibleFinishReason('length').unified,
        FinishReasonType.length,
      );
    });

    test('content_filter', () {
      expect(
        mapOpenAiCompatibleFinishReason('content_filter').unified,
        FinishReasonType.contentFilter,
      );
    });

    test('function_call 与 tool_calls 都映射为 toolCalls', () {
      expect(
        mapOpenAiCompatibleFinishReason('function_call').unified,
        FinishReasonType.toolCalls,
      );
      expect(
        mapOpenAiCompatibleFinishReason('tool_calls').unified,
        FinishReasonType.toolCalls,
      );
    });

    test('未知值与 null 都映射为 other,raw 原样保留', () {
      final unknown = mapOpenAiCompatibleFinishReason('something_else');
      expect(unknown.unified, FinishReasonType.other);
      expect(unknown.raw, 'something_else');

      final nullCase = mapOpenAiCompatibleFinishReason(null);
      expect(nullCase.unified, FinishReasonType.other);
      expect(nullCase.raw, isNull);
    });
  });
}
