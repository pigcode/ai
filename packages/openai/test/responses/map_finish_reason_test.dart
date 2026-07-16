import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('mapOpenAiResponsesFinishReason', () {
    test('null reason + no function call => stop', () {
      final reason = mapOpenAiResponsesFinishReason(
        incompleteReason: null,
        hasFunctionCall: false,
      );
      expect(reason.unified, FinishReasonType.stop);
      expect(reason.raw, isNull);
    });

    test('null reason + function call => tool-calls', () {
      final reason = mapOpenAiResponsesFinishReason(
        incompleteReason: null,
        hasFunctionCall: true,
      );
      expect(reason.unified, FinishReasonType.toolCalls);
      expect(reason.raw, isNull);
    });

    test('max_output_tokens => length (regardless of hasFunctionCall)', () {
      final reason = mapOpenAiResponsesFinishReason(
        incompleteReason: 'max_output_tokens',
        hasFunctionCall: true,
      );
      expect(reason.unified, FinishReasonType.length);
      expect(reason.raw, 'max_output_tokens');
    });

    test('content_filter => contentFilter', () {
      final reason = mapOpenAiResponsesFinishReason(
        incompleteReason: 'content_filter',
        hasFunctionCall: false,
      );
      expect(reason.unified, FinishReasonType.contentFilter);
      expect(reason.raw, 'content_filter');
    });

    test('unknown reason + no function call => other', () {
      final reason = mapOpenAiResponsesFinishReason(
        incompleteReason: 'something_else',
        hasFunctionCall: false,
      );
      expect(reason.unified, FinishReasonType.other);
      expect(reason.raw, 'something_else');
    });

    test('unknown reason + function call => tool-calls', () {
      final reason = mapOpenAiResponsesFinishReason(
        incompleteReason: 'something_else',
        hasFunctionCall: true,
      );
      expect(reason.unified, FinishReasonType.toolCalls);
      expect(reason.raw, 'something_else');
    });
  });
}
