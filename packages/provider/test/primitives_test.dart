import 'package:pigcode_ai_provider/src/language_model/finish_reason.dart';
import 'package:pigcode_ai_provider/src/json_value/json.dart';
import 'package:pigcode_ai_provider/src/language_model/reasoning.dart';
import 'package:pigcode_ai_provider/src/language_model/response_format.dart';
import 'package:pigcode_ai_provider/src/language_model/usage.dart';
import 'package:test/test.dart';

void main() {
  group('ReasoningEffort.wireValue', () {
    test('providerDefault maps to provider-default', () {
      expect(ReasoningEffort.providerDefault.wireValue, 'provider-default');
    });

    test('xhigh maps to its name', () {
      expect(ReasoningEffort.xhigh.wireValue, 'xhigh');
    });

    test('remaining variants map to their names', () {
      expect(ReasoningEffort.none.wireValue, 'none');
      expect(ReasoningEffort.minimal.wireValue, 'minimal');
      expect(ReasoningEffort.low.wireValue, 'low');
      expect(ReasoningEffort.medium.wireValue, 'medium');
      expect(ReasoningEffort.high.wireValue, 'high');
    });

    test('covers every enum value', () {
      expect(ReasoningEffort.values.length, 7);
    });
  });

  group('ResponseFormat equality', () {
    test('text variants are equal', () {
      expect(const ResponseFormatText(), const ResponseFormatText());
    });

    test('json variants with equal fields are equal', () {
      const a = ResponseFormatJson(
        schema: JsonSchema(<String, Object?>{'type': 'object'}),
        name: 'result',
        description: 'a result',
      );
      const b = ResponseFormatJson(
        schema: JsonSchema(<String, Object?>{'type': 'object'}),
        name: 'result',
        description: 'a result',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('json variants differing by schema are not equal', () {
      const a = ResponseFormatJson(
        schema: JsonSchema(<String, Object?>{'type': 'object'}),
      );
      const b = ResponseFormatJson(
        schema: JsonSchema(<String, Object?>{'type': 'string'}),
      );
      expect(a, isNot(b));
    });

    test('empty json defaults all optional fields to null', () {
      const a = ResponseFormatJson();
      expect(a.schema, isNull);
      expect(a.name, isNull);
      expect(a.description, isNull);
      expect(a, const ResponseFormatJson());
    });
  });

  group('LanguageModelUsage equality', () {
    test('nested usage with equal fields is equal', () {
      const a = LanguageModelUsage(
        inputTokens: InputTokens(total: 10, cacheRead: 4),
        outputTokens: OutputTokens(total: 5, reasoning: 2),
        raw: <String, Object?>{'foo': 1},
      );
      const b = LanguageModelUsage(
        inputTokens: InputTokens(total: 10, cacheRead: 4),
        outputTokens: OutputTokens(total: 5, reasoning: 2),
        raw: <String, Object?>{'foo': 1},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('usage differing in a nested input field is not equal', () {
      const a = LanguageModelUsage(
        inputTokens: InputTokens(total: 10),
        outputTokens: OutputTokens(total: 5),
      );
      const b = LanguageModelUsage(
        inputTokens: InputTokens(total: 11),
        outputTokens: OutputTokens(total: 5),
      );
      expect(a, isNot(b));
    });

    test('usage differing only in raw is not equal', () {
      const a = LanguageModelUsage(
        inputTokens: InputTokens(),
        outputTokens: OutputTokens(),
        raw: <String, Object?>{'a': 1},
      );
      const b = LanguageModelUsage(
        inputTokens: InputTokens(),
        outputTokens: OutputTokens(),
      );
      expect(a, isNot(b));
    });

    test('input tokens carries all four fields', () {
      const t = InputTokens(total: 1, noCache: 2, cacheRead: 3, cacheWrite: 4);
      expect(t.total, 1);
      expect(t.noCache, 2);
      expect(t.cacheRead, 3);
      expect(t.cacheWrite, 4);
    });
  });

  group('LanguageModelFinishReason equality', () {
    test('reasons with equal unified and raw are equal', () {
      const a =
          LanguageModelFinishReason(FinishReasonType.stop, raw: 'end_turn');
      const b =
          LanguageModelFinishReason(FinishReasonType.stop, raw: 'end_turn');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('reasons differing by unified are not equal', () {
      const a = LanguageModelFinishReason(FinishReasonType.stop);
      const b = LanguageModelFinishReason(FinishReasonType.length);
      expect(a, isNot(b));
    });

    test('reasons differing by raw are not equal', () {
      const a = LanguageModelFinishReason(FinishReasonType.toolCalls,
          raw: 'tool_use');
      const b = LanguageModelFinishReason(FinishReasonType.toolCalls);
      expect(a, isNot(b));
    });

    test('finish reason type covers six variants', () {
      expect(FinishReasonType.values.length, 6);
    });
  });
}
