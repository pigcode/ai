import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('mapOpenAiChatFinishReason', () {
    test('stop', () {
      final result = mapOpenAiChatFinishReason('stop');
      expect(result.unified, FinishReasonType.stop);
      expect(result.raw, 'stop');
    });

    test('length', () {
      expect(
          mapOpenAiChatFinishReason('length').unified, FinishReasonType.length);
    });

    test('content_filter', () {
      expect(
        mapOpenAiChatFinishReason('content_filter').unified,
        FinishReasonType.contentFilter,
      );
    });

    test('function_call 与 tool_calls 都映射为 toolCalls', () {
      expect(
        mapOpenAiChatFinishReason('function_call').unified,
        FinishReasonType.toolCalls,
      );
      expect(
        mapOpenAiChatFinishReason('tool_calls').unified,
        FinishReasonType.toolCalls,
      );
    });

    test('未知值与 null 都映射为 other,raw 原样保留', () {
      final unknown = mapOpenAiChatFinishReason('something_else');
      expect(unknown.unified, FinishReasonType.other);
      expect(unknown.raw, 'something_else');

      final nullCase = mapOpenAiChatFinishReason(null);
      expect(nullCase.unified, FinishReasonType.other);
      expect(nullCase.raw, isNull);
    });
  });
}
