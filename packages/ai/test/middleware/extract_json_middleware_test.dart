import 'dart:async';

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

ScriptedTurn _textTurn(List<lm.LanguageModelContent> content) {
  return ScriptedTurn(
    content: content,
    finishReason: _finishReason,
    usage: _usage,
  );
}

String _textFrom(List<lm.LanguageModelStreamPart> chunks) {
  return chunks.whereType<lm.TextDelta>().map((part) => part.delta).join();
}

void main() {
  group('extractJsonMiddleware', () {
    test('strips markdown json fences from generated text content', () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'weather',
        input: '{"city":"Paris"}',
      );
      final model = ScriptedModel(
        turns: [
          _textTurn(const [
            lm.TextContent('```json\n{"ok":true}\n```'),
            toolCall,
          ]),
        ],
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doGenerate(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(result.content, const [
        lm.TextContent('{"ok":true}'),
        toolCall,
      ]);
    });

    test('strips generated fences after leading whitespace', () async {
      final model = ScriptedModel(
        turns: [
          _textTurn(const [lm.TextContent(' \n```json\n{"ok":true}\n```')]),
        ],
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doGenerate(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(result.content.single, const lm.TextContent('{"ok":true}'));
    });

    test('strips generated fences with spaced json info strings', () async {
      final model = ScriptedModel(
        turns: [
          _textTurn(const [lm.TextContent('``` json\n{"ok":true}\n```')]),
        ],
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doGenerate(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(result.content.single, const lm.TextContent('{"ok":true}'));
    });

    test('strips generated fences with uppercase json info strings', () async {
      final model = ScriptedModel(
        turns: [
          _textTurn(const [lm.TextContent('```JSON\n{"ok":true}\n```')]),
        ],
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doGenerate(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(result.content.single, const lm.TextContent('{"ok":true}'));
    });

    test('strips generated fences with CRLF line endings', () async {
      final model = ScriptedModel(
        turns: [
          _textTurn(const [lm.TextContent('```json\r\n{"ok":true}\r\n```')]),
        ],
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doGenerate(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(result.content.single, const lm.TextContent('{"ok":true}'));
    });

    test('keeps generated fences with non-json info strings', () async {
      final model = ScriptedModel(
        turns: [
          _textTurn(const [lm.TextContent('```js\nconst ok = true;\n```')]),
        ],
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doGenerate(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(
        result.content.single,
        const lm.TextContent('```js\nconst ok = true;\n```'),
      );
    });

    test('uses custom transform for generated text content', () async {
      final model = ScriptedModel(
        turns: [
          _textTurn(const [lm.TextContent('prefix {"ok":true} suffix')]),
        ],
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(
          transform: (text) =>
              text.replaceFirst('prefix ', '').replaceFirst(' suffix', ''),
        ),
      );

      final result = await wrapped.doGenerate(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(result.content.single, const lm.TextContent('{"ok":true}'));
    });

    test('strips split markdown json fences from streamed text', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '`'),
        lm.TextDelta('text-1', '``json\n{"'),
        lm.TextDelta('text-1', 'ok":true}'),
        lm.TextDelta('text-1', '\n```'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );
      final chunks = await result.stream.toList();

      expect(chunks.whereType<lm.TextStart>(), [
        const lm.TextStart('text-1'),
      ]);
      expect(_textFrom(chunks), '{"ok":true}');
      expect(chunks.whereType<lm.TextEnd>(), [
        const lm.TextEnd('text-1'),
      ]);
    });

    test('strips streamed fences with spaced json info strings', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '``` json\n'),
        lm.TextDelta('text-1', '{"ok":true}\n```'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(_textFrom(await result.stream.toList()), '{"ok":true}');
    });

    test('strips streamed fences with uppercase json info strings', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '```JSON\n'),
        lm.TextDelta('text-1', '{"ok":true}\n```'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(_textFrom(await result.stream.toList()), '{"ok":true}');
    });

    test('strips streamed fences with CRLF line endings', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '```json\r\n'),
        lm.TextDelta('text-1', '{"ok":true}\r\n```'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(_textFrom(await result.stream.toList()), '{"ok":true}');
    });

    test('keeps streamed fences with non-json info strings', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '```js\n'),
        lm.TextDelta('text-1', 'const ok = true;\n```'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(
        _textFrom(await result.stream.toList()),
        '```js\nconst ok = true;\n```',
      );
    });

    test('does not let raw chunks flush split markdown fences', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '`'),
        lm.RawPart({'frame': 1}),
        lm.TextDelta('text-1', '``json\n{"ok":true}\n```'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );
      final chunks = await result.stream.toList();

      expect(chunks.whereType<lm.RawPart>(), [
        const lm.RawPart({'frame': 1}),
      ]);
      expect(_textFrom(chunks), '{"ok":true}');
    });

    test('flushes streaming buffered text before raw chunks', () async {
      const raw = lm.RawPart({'frame': 1});
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'hello'),
        raw,
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );
      final chunks = await result.stream.toList();

      expect(chunks.whereType<lm.TextDelta>(), [
        const lm.TextDelta('text-1', 'hello'),
      ]);
      expect(
        chunks.indexWhere((chunk) => chunk is lm.TextDelta),
        lessThan(chunks.indexOf(raw)),
      );
    });

    test('preserves closing fence buffers across raw chunks', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '```json\n{"ok":true}\n``'),
        lm.RawPart({'frame': 1}),
        lm.TextDelta('text-1', '`'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(_textFrom(await result.stream.toList()), '{"ok":true}');
    });

    test('does not let non-text chunks flush undecided markdown fences',
        () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'weather',
        input: '{"city":"Paris"}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '`'),
        toolCall,
        lm.TextDelta('text-1', '``json\n{"ok":true}\n```'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );
      final chunks = await result.stream.toList();

      expect(chunks, contains(toolCall));
      expect(_textFrom(chunks), '{"ok":true}');
    });

    test('strips streamed fences after leading whitespace', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', ' \n'),
        lm.TextDelta('text-1', '```json\n{"ok":true}\n```'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(_textFrom(await result.stream.toList()), '{"ok":true}');
    });

    test('waits for a complete fence line after leading whitespace', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', ' \n```json'),
        lm.TextDelta('text-1', '\n{"ok":true}\n```'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(_textFrom(await result.stream.toList()), '{"ok":true}');
    });

    test('strips streamed fences followed by long trailing whitespace',
        () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '```json\n'),
        lm.TextDelta('text-1', '{"ok":true}\n```                    '),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(_textFrom(await result.stream.toList()), '{"ok":true}');
    });

    test('does not trim ordinary streamed text that has no fence', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'there'),
        lm.TextDelta('text-1', ' altogether?'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(_textFrom(await result.stream.toList()), 'there altogether?');
    });

    test('preserves trailing spaces in streamed text that has no fence',
        () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'hello '),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(_textFrom(await result.stream.toList()), 'hello ');
    });

    test('uses custom transform for streamed text at text end', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'prefix '),
        lm.TextDelta('text-1', '{"ok":true}'),
        lm.TextDelta('text-1', ' suffix'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(
          transform: (text) =>
              text.replaceFirst('prefix ', '').replaceFirst(' suffix', ''),
        ),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      expect(_textFrom(await result.stream.toList()), '{"ok":true}');
    });

    test('preserves text delta metadata for streamText aggregation', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta(
          'text-1',
          '{"ok"',
          providerMetadata: {
            'openai': {'itemId': 'msg_1'},
          },
        ),
        lm.TextDelta(
          'text-1',
          ':true}',
          providerMetadata: {
            'openai': {'itemId': 'msg_1', 'refined': true},
          },
        ),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = ai.streamText(model: wrapped, prompt: 'hi');
      await result.consumeStream();

      final textContent = (await result.steps)
          .single
          .content
          .whereType<lm.TextContent>()
          .single;
      expect(textContent.text, '{"ok":true}');
      expect(textContent.providerMetadata, {
        'openai': {'itemId': 'msg_1', 'refined': true},
      });
    });

    test('flushes default buffered text before terminal errors', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'there'),
        lm.ErrorPart('boom'),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      final chunks = await result.stream.toList();
      expect(chunks.whereType<lm.TextStart>(), [
        const lm.TextStart('text-1'),
      ]);
      expect(chunks.whereType<lm.TextDelta>(), [
        const lm.TextDelta('text-1', 'there'),
      ]);
      expect(chunks.last, const lm.ErrorPart('boom'));
    });

    test('flushes custom transformed text before terminal errors', () async {
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'prefix there'),
        lm.ErrorPart('boom'),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(
          transform: (text) => text.replaceFirst('prefix ', ''),
        ),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );

      final chunks = await result.stream.toList();
      expect(chunks.whereType<lm.TextStart>(), [
        const lm.TextStart('text-1'),
      ]);
      expect(chunks.whereType<lm.TextDelta>(), [
        const lm.TextDelta('text-1', 'there'),
      ]);
      expect(chunks.last, const lm.ErrorPart('boom'));
    });

    test('flushes default buffered text before non-text chunks', () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'weather',
        input: '{"city":"Paris"}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'there'),
        toolCall,
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );
      final chunks = await result.stream.toList();

      expect(chunks.whereType<lm.TextDelta>(), [
        const lm.TextDelta('text-1', 'there'),
      ]);
      expect(
        chunks.indexWhere((chunk) => chunk is lm.TextDelta),
        lessThan(chunks.indexOf(toolCall)),
      );
    });

    test('streams known non-fence backtick prefixes before non-text chunks',
        () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'weather',
        input: '{"city":"Paris"}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '`a'),
        toolCall,
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );
      final chunks = await result.stream.toList();

      expect(_textFrom(chunks), '`a');
      expect(
        chunks.indexWhere((chunk) => chunk is lm.TextDelta),
        lessThan(chunks.indexOf(toolCall)),
      );
    });

    test('preserves fenced state after flushing before non-text chunks',
        () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'weather',
        input: '{"city":"Paris"}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '```json\n{"ok"'),
        toolCall,
        lm.TextDelta('text-1', ':true}\n```'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );
      final chunks = await result.stream.toList();

      expect(chunks, contains(toolCall));
      expect(_textFrom(chunks), '{"ok":true}');
    });

    test('preserves closing fence buffers across non-raw chunks', () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'weather',
        input: '{"city":"Paris"}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', '```json\n{"ok":true}\n``'),
        toolCall,
        lm.TextDelta('text-1', '`'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );
      final chunks = await result.stream.toList();

      expect(chunks, contains(toolCall));
      expect(_textFrom(chunks), '{"ok":true}');
    });

    test('keeps custom transform buffered across non-text chunks', () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'weather',
        input: '{"city":"Paris"}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-1'),
        lm.TextDelta('text-1', 'a'),
        toolCall,
        lm.TextDelta('text-1', 'b'),
        lm.TextEnd('text-1'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(
          transform: (text) => text.toUpperCase(),
        ),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );
      final chunks = await result.stream.toList();

      expect(chunks.whereType<lm.TextDelta>(), [
        const lm.TextDelta('text-1', 'AB'),
      ]);
      expect(chunks, contains(toolCall));
      expect(
        chunks.indexWhere((chunk) => chunk is lm.TextDelta),
        lessThan(chunks.indexOf(toolCall)),
      );
    });

    test('queues custom transform chunks on the latest text block', () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'weather',
        input: '{"city":"Paris"}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextStart('text-a'),
        lm.TextDelta('text-a', 'a'),
        lm.TextStart('text-b'),
        lm.TextDelta('text-b', 'b'),
        toolCall,
        lm.TextEnd('text-b'),
        lm.TextEnd('text-a'),
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(
          transform: (text) => text.toUpperCase(),
        ),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );
      final chunks = await result.stream.toList();

      expect(chunks.whereType<lm.TextDelta>(), [
        const lm.TextDelta('text-b', 'B'),
        const lm.TextDelta('text-a', 'A'),
      ]);
      expect(
        chunks.indexOf(toolCall),
        lessThan(chunks.indexOf(const lm.TextEnd('text-b'))),
      );
    });

    test('leaves non-text chunks and untracked text deltas unchanged',
        () async {
      const toolCall = lm.ToolCall(
        toolCallId: 'call-1',
        toolName: 'weather',
        input: '{"city":"Paris"}',
      );
      final model = _FixedStreamModel(const [
        lm.StreamStart([]),
        lm.TextDelta('missing-start', 'loose text'),
        toolCall,
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.extractJsonMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: _prompt),
      );
      final chunks = await result.stream.toList();

      expect(chunks[1], const lm.TextDelta('missing-start', 'loose text'));
      expect(chunks[2], toolCall);
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
