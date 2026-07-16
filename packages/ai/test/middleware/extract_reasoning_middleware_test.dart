import 'package:pigcode_ai/pigcode_ai.dart' as ai;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

const _prompt = <lm.LanguageModelMessage>[
  lm.UserMessage([lm.TextPart('hi')]),
];
const _finishReason = lm.LanguageModelFinishReason(
  lm.FinishReasonType.stop,
);
const _usage = lm.LanguageModelUsage(
  inputTokens: lm.InputTokens(),
  outputTokens: lm.OutputTokens(),
);
const _extractedReasoning0 = 'extracted-reasoning-0';
const _extractedReasoning1 = 'extracted-reasoning-1';

ScriptedTurn _textTurn(List<lm.LanguageModelContent> content) {
  return ScriptedTurn(
    content: content,
    finishReason: _finishReason,
    usage: _usage,
  );
}

void main() {
  group('extractReasoningMiddleware', () {
    test('extracts reasoning tags from generated text content', () async {
      const metadata = {
        'openai': {'itemId': 'item-1'},
      };
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'weather',
        input: '{"city":"Paris"}',
      );
      final model = ScriptedModel(
        turns: [
          _textTurn(const [
            lm.TextContent(
              '<think>analyzing</think>Here'
              '<think>checking again</think>more',
              providerMetadata: metadata,
            ),
            toolCall,
          ]),
        ],
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doGenerate(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(result.content, const [
        lm.ReasoningContent(
          'analyzing\nchecking again',
          providerMetadata: metadata,
        ),
        lm.TextContent('Here\nmore', providerMetadata: metadata),
        toolCall,
      ]);
    });

    test('startWithReasoning treats leading text as reasoning', () async {
      final model = ScriptedModel(
        turns: [
          _textTurn(const [
            lm.TextContent('analyzing</think>Here is the response'),
          ]),
        ],
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(
          tagName: 'think',
          startWithReasoning: true,
        ),
      );

      final result = await wrapped.doGenerate(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(result.content, const [
        lm.ReasoningContent('analyzing'),
        lm.TextContent('Here is the response'),
      ]);
    });

    test('extracts unterminated generated reasoning', () async {
      final model = ScriptedModel(
        turns: [
          _textTurn(const [
            lm.TextContent('<think>thinking'),
          ]),
        ],
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doGenerate(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(result.content, const [
        lm.ReasoningContent('thinking'),
        lm.TextContent(''),
      ]);
    });

    test('startWithReasoning extracts unterminated generated text', () async {
      final model = ScriptedModel(
        turns: [
          _textTurn(const [
            lm.TextContent('thinking'),
          ]),
        ],
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(
          tagName: 'think',
          startWithReasoning: true,
        ),
      );

      final result = await wrapped.doGenerate(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(result.content, const [
        lm.ReasoningContent('thinking'),
        lm.TextContent(''),
      ]);
    });

    test('extracts split reasoning tags from streamed text', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<thi'),
        lm.TextDelta('text-1', 'nk>ana'),
        lm.TextDelta('text-1', 'lyzing</thi'),
        lm.TextDelta('text-1', 'nk>Here'),
        lm.TextDelta('text-1', ' is the response'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'ana'),
        lm.ReasoningDelta(_extractedReasoning0, 'lyzing'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'Here'),
        lm.TextDelta('text-1', ' is the response'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('uses globally unique streamed reasoning ids', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('a'),
        lm.TextStart('b'),
        lm.TextDelta('a', '<think>one</think>'),
        lm.TextDelta('b', '<think>two</think>'),
        lm.TextEnd('a'),
        lm.TextEnd('b'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'one'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.ReasoningStart(_extractedReasoning1),
        lm.ReasoningDelta(_extractedReasoning1, 'two'),
        lm.ReasoningEnd(_extractedReasoning1),
        lm.TextStart('a'),
        lm.TextEnd('a'),
        lm.TextStart('b'),
        lm.TextEnd('b'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('avoids native streamed reasoning id collisions', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.ReasoningStart('reasoning-0'),
        lm.ReasoningDelta('reasoning-0', 'native'),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<think>synthetic</think>'),
        lm.TextEnd('text-1'),
        lm.ReasoningEnd('reasoning-0'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart('reasoning-0'),
        lm.ReasoningDelta('reasoning-0', 'native'),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'synthetic'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextStart('text-1'),
        lm.TextEnd('text-1'),
        lm.ReasoningEnd('reasoning-0'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('does not collide with later native streamed reasoning ids', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<think>synthetic</think>'),
        lm.TextEnd('text-1'),
        lm.ReasoningStart('reasoning-0'),
        lm.ReasoningDelta('reasoning-0', 'native'),
        lm.ReasoningEnd('reasoning-0'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'synthetic'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextStart('text-1'),
        lm.TextEnd('text-1'),
        lm.ReasoningStart('reasoning-0'),
        lm.ReasoningDelta('reasoning-0', 'native'),
        lm.ReasoningEnd('reasoning-0'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('rewrites later native ids that collide with extracted reasoning ids',
        () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<think>synthetic</think>'),
        lm.TextEnd('text-1'),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'native'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'synthetic'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextStart('text-1'),
        lm.TextEnd('text-1'),
        lm.ReasoningStart(_extractedReasoning1),
        lm.ReasoningDelta(_extractedReasoning1, 'native'),
        lm.ReasoningEnd(_extractedReasoning1),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('rewrites queued native reasoning ids only once', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<think>synthetic'),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'native'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextDelta('text-1', '</think>answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'synthetic'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextStart('text-1'),
        lm.ReasoningStart(_extractedReasoning1),
        lm.ReasoningDelta(_extractedReasoning1, 'native'),
        lm.ReasoningEnd(_extractedReasoning1),
        lm.TextDelta('text-1', 'answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('emits reasoning boundaries for empty streamed reasoning blocks',
        () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<think></think>'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextStart('text-1'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('emits reasoning starts for later empty streamed reasoning blocks',
        () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<think>a</think><think></think>answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'a'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.ReasoningStart(_extractedReasoning1),
        lm.ReasoningEnd(_extractedReasoning1),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('closes unterminated streamed reasoning at text end', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<think>partial'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'partial'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextStart('text-1'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('startWithReasoning extracts leading streamed text as reasoning',
        () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'ana'),
        lm.TextDelta('text-1', 'lyzing\n'),
        lm.TextDelta('text-1', '</think>'),
        lm.TextDelta('text-1', 'Here is the response'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(
          tagName: 'think',
          startWithReasoning: true,
        ),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'ana'),
        lm.ReasoningDelta(_extractedReasoning0, 'lyzing\n'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'Here is the response'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('preserves text start metadata on extracted reasoning', () async {
      const metadata = {
        'openai': {'itemId': 'item-1'},
      };
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1', providerMetadata: metadata),
        lm.TextDelta('text-1', '<think>reason</think>answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0, providerMetadata: metadata),
        lm.ReasoningDelta(
          _extractedReasoning0,
          'reason',
          providerMetadata: metadata,
        ),
        lm.ReasoningEnd(_extractedReasoning0, providerMetadata: metadata),
        lm.TextStart('text-1', providerMetadata: metadata),
        lm.TextDelta('text-1', 'answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('preserves text end metadata on unterminated extracted reasoning',
        () async {
      const metadata = {
        'openai': {'encryptedContent': 'encrypted-1'},
      };
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<think>reason'),
        lm.TextEnd('text-1', providerMetadata: metadata),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'reason'),
        lm.ReasoningEnd(_extractedReasoning0, providerMetadata: metadata),
        lm.TextStart('text-1'),
        lm.TextEnd('text-1', providerMetadata: metadata),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('preserves metadata from tag-only opening deltas on reasoning',
        () async {
      const metadata = {
        'openai': {'itemId': 'item-1'},
      };
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<think>', providerMetadata: metadata),
        lm.TextDelta('text-1', 'reason</think>answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0, providerMetadata: metadata),
        lm.ReasoningDelta(
          _extractedReasoning0,
          'reason',
          providerMetadata: metadata,
        ),
        lm.ReasoningEnd(_extractedReasoning0, providerMetadata: metadata),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'answer', providerMetadata: metadata),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('preserves streamed text delta metadata when tags are absent',
        () async {
      const metadata = {
        'openai': {'itemId': 'item-1'},
      };
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta(
          'text-1',
          'Here is the response',
          providerMetadata: metadata,
        ),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta(
          'text-1',
          'Here is the response',
          providerMetadata: metadata,
        ),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('flushes buffered possible tag prefixes before terminal errors',
        () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<thi'),
        lm.ErrorPart('boom'),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<thi'),
        lm.ErrorPart('boom'),
      ]);
    });

    test('tracks delayed text starts per text id', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('a'),
        lm.TextStart('b'),
        lm.TextDelta('a', 'first'),
        lm.TextEnd('a'),
        lm.TextDelta('b', 'second'),
        lm.TextEnd('b'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.TextStart('a'),
        lm.TextDelta('a', 'first'),
        lm.TextEnd('a'),
        lm.TextStart('b'),
        lm.TextDelta('b', 'second'),
        lm.TextEnd('b'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('preserves text starts before interleaved non-text chunks', () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'search',
        input: '{}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        toolCall,
        lm.TextDelta('text-1', 'answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        toolCall,
        lm.TextDelta('text-1', 'answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('preserves order when nonterminal chunks split reasoning tags',
        () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'search',
        input: '{}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<thi'),
        toolCall,
        lm.TextDelta('text-1', 'nk>reason</think>answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'reason'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextStart('text-1'),
        toolCall,
        lm.TextDelta('text-1', 'answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('delays non-text chunks while reasoning remains open', () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'search',
        input: '{}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<think>reason'),
        toolCall,
        lm.TextDelta('text-1', '</think>answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'reason'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextStart('text-1'),
        toolCall,
        lm.TextDelta('text-1', 'answer'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('delays other text deltas while a tag prefix is buffered', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('a'),
        lm.TextStart('b'),
        lm.TextDelta('a', '<thi'),
        lm.TextDelta('b', 'second'),
        lm.TextDelta('a', 'nk>one</think>'),
        lm.TextEnd('a'),
        lm.TextEnd('b'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.ReasoningStart(_extractedReasoning0),
        lm.ReasoningDelta(_extractedReasoning0, 'one'),
        lm.ReasoningEnd(_extractedReasoning0),
        lm.TextStart('b'),
        lm.TextDelta('b', 'second'),
        lm.TextStart('a'),
        lm.TextEnd('a'),
        lm.TextEnd('b'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('queues other text ends while a tag prefix is buffered', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('a'),
        lm.TextStart('b'),
        lm.TextDelta('a', '<thi'),
        lm.TextDelta('b', 'second'),
        lm.TextEnd('b'),
        lm.TextDelta('a', 's plain'),
        lm.TextEnd('a'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.TextStart('a'),
        lm.TextDelta('a', '<this plain'),
        lm.TextStart('b'),
        lm.TextDelta('b', 'second'),
        lm.TextEnd('b'),
        lm.TextEnd('a'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('does not rotate pending text ends when a prefix ends as text',
        () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('a'),
        lm.TextStart('b'),
        lm.TextDelta('a', '<thi'),
        lm.TextDelta('b', 'second'),
        lm.TextEnd('b'),
        lm.TextEnd('a'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.TextStart('a'),
        lm.TextDelta('a', '<thi'),
        lm.TextStart('b'),
        lm.TextDelta('b', 'second'),
        lm.TextEnd('b'),
        lm.TextEnd('a'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('drains pending non-text chunks before text end', () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'search',
        input: '{}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<thi'),
        toolCall,
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '<thi'),
        toolCall,
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });

    test('keeps streamed text unchanged when reasoning tags are absent',
        () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'Here is the response'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractReasoningMiddleware(tagName: 'think'),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(await result.stream.toList(), const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'Here is the response'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
    });
  });
}

final class _FixedStreamModel implements lm.LanguageModel {
  const _FixedStreamModel(this.chunks);

  final List<lm.LanguageModelStreamPart> chunks;

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'fixed-stream';

  @override
  String get modelId => 'fixed-stream-model';

  @override
  Map<String, List<RegExp>> get supportedUrls => const {};

  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async {
    return lm.LanguageModelStreamResult(
      stream: Stream.fromIterable(chunks),
    );
  }
}
