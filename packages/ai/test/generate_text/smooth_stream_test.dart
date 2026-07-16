import 'package:pigcode_ai/src/generate_text/smooth_stream.dart';
import 'package:pigcode_ai/src/generate_text/text_stream_part.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

Future<List<TextStreamPart>> _smooth(
  List<TextStreamPart> parts, {
  SmoothStreamChunking chunking = SmoothStreamChunking.word,
}) {
  return Stream<TextStreamPart>.fromIterable(parts)
      .transform(smoothStream(
        delay: null,
        chunking: chunking,
      ))
      .toList();
}

void main() {
  group('smoothStream', () {
    test('word chunking combines partial words and emits complete chunks',
        () async {
      final parts = await _smooth(const [
        TextStartPart('1'),
        TextDeltaPart('1', 'Hello'),
        TextDeltaPart('1', ', '),
        TextDeltaPart('1', 'world!'),
        TextEndPart('1'),
      ]);

      expect(parts, const [
        TextStartPart('1'),
        TextDeltaPart('1', 'Hello, '),
        TextDeltaPart('1', 'world!'),
        TextEndPart('1'),
      ]);
    });

    test('word chunking splits a large text delta', () async {
      final parts = await _smooth(const [
        TextStartPart('1'),
        TextDeltaPart('1', 'Hello, World! This is text.'),
        TextEndPart('1'),
      ]);

      expect(parts, const [
        TextStartPart('1'),
        TextDeltaPart('1', 'Hello, '),
        TextDeltaPart('1', 'World! '),
        TextDeltaPart('1', 'This '),
        TextDeltaPart('1', 'is '),
        TextDeltaPart('1', 'text.'),
        TextEndPart('1'),
      ]);
    });

    test('line chunking emits through newlines', () async {
      final parts = await _smooth(
        const [
          TextStartPart('1'),
          TextDeltaPart('1', 'first'),
          TextDeltaPart('1', '\nsecond\nthird'),
          TextEndPart('1'),
        ],
        chunking: SmoothStreamChunking.line,
      );

      expect(parts, const [
        TextStartPart('1'),
        TextDeltaPart('1', 'first\n'),
        TextDeltaPart('1', 'second\n'),
        TextDeltaPart('1', 'third'),
        TextEndPart('1'),
      ]);
    });

    test('regexp chunking includes text before the first match', () async {
      final parts = await _smooth(
        const [
          TextStartPart('1'),
          TextDeltaPart('1', 'Hello_, world!'),
          TextEndPart('1'),
        ],
        chunking: SmoothStreamChunking.regExp(RegExp('_')),
      );

      expect(parts, const [
        TextStartPart('1'),
        TextDeltaPart('1', 'Hello_'),
        TextDeltaPart('1', ', world!'),
        TextEndPart('1'),
      ]);
    });

    test('custom callback chunking emits callback matches', () async {
      final parts = await _smooth(
        const [
          TextStartPart('1'),
          TextDeltaPart('1', 'He_llo, '),
          TextDeltaPart('1', 'w_orld!'),
          TextEndPart('1'),
        ],
        chunking: SmoothStreamChunking.custom(
          (buffer) => RegExp(r'[^_]*_').firstMatch(buffer)?.group(0),
        ),
      );

      expect(parts, const [
        TextStartPart('1'),
        TextDeltaPart('1', 'He_'),
        TextDeltaPart('1', 'llo, w_'),
        TextDeltaPart('1', 'orld!'),
        TextEndPart('1'),
      ]);
    });

    test('flushes buffered text before non-text parts', () async {
      const toolCall = provider.ToolCall(
        toolCallId: 'call-1',
        toolName: 'search',
        input: '{}',
      );
      final parts = await _smooth(const [
        TextStartPart('1'),
        TextDeltaPart('1', 'checking the'),
        ToolCallStreamPart(toolCall),
      ]);

      expect(parts, const [
        TextStartPart('1'),
        TextDeltaPart('1', 'checking '),
        TextDeltaPart('1', 'the'),
        ToolCallStreamPart(toolCall),
      ]);
    });

    test('smooths reasoning deltas and preserves flushed metadata', () async {
      const metadata = {
        'anthropic': {'signature': 'sig-1'},
      };
      final parts = await _smooth(
        const [
          ReasoningStartPart('r1'),
          ReasoningDeltaPart('r1', 'checking'),
          ReasoningDeltaPart('r1', ' the', providerMetadata: metadata),
          ReasoningEndPart('r1'),
        ],
        chunking: SmoothStreamChunking.custom((_) => null),
      );

      expect(parts, const [
        ReasoningStartPart('r1'),
        ReasoningDeltaPart(
          'r1',
          'checking the',
          providerMetadata: metadata,
        ),
        ReasoningEndPart('r1'),
      ]);
    });

    test('preserves metadata on emitted text and reasoning chunks', () async {
      const metadata = {
        'openai': {'itemId': 'item-1'},
      };
      final parts = await _smooth(const [
        TextDeltaPart('t1', 'Hello, world! ', providerMetadata: metadata),
        ReasoningDeltaPart('r1', 'checking the path ',
            providerMetadata: metadata),
      ]);

      expect(parts, const [
        TextDeltaPart('t1', 'Hello, ', providerMetadata: metadata),
        TextDeltaPart('t1', 'world! ', providerMetadata: metadata),
        ReasoningDeltaPart('r1', 'checking ', providerMetadata: metadata),
        ReasoningDeltaPart('r1', 'the ', providerMetadata: metadata),
        ReasoningDeltaPart('r1', 'path ', providerMetadata: metadata),
      ]);
    });

    test('custom chunk detector must return a non-empty prefix', () async {
      final stream = Stream<TextStreamPart>.fromIterable(const [
        TextDeltaPart('1', 'abc'),
      ]).transform(smoothStream(
        delay: null,
        chunking: SmoothStreamChunking.custom((_) => 'bc'),
      ));

      expect(stream.toList(), throwsArgumentError);
    });
  });
}
