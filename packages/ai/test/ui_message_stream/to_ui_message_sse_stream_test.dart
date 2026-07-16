import 'dart:async';

import 'package:pigcode_ai/src/ui_message_stream/to_ui_message_sse_stream.dart';
import 'package:pigcode_ai/src/ui_message_stream/ui_message_chunk.dart';
import 'package:test/test.dart';

void main() {
  group('toUiMessageSseStream', () {
    test('encodes chunks as SSE data frames and appends done', () async {
      final frames = await toUiMessageSseStream(
        Stream<UiMessageChunk>.fromIterable([
          TextStartUiMessageChunk('txt_1'),
          TextDeltaUiMessageChunk('txt_1', 'hi'),
        ]),
      ).toList();

      expect(frames, [
        'data: {"type":"text-start","id":"txt_1"}\n\n',
        'data: {"type":"text-delta","id":"txt_1","delta":"hi"}\n\n',
        'data: [DONE]\n\n',
      ]);
    });

    test('can omit the done frame', () async {
      final frames = await toUiMessageSseStream(
        Stream<UiMessageChunk>.fromIterable([
          TextEndUiMessageChunk('txt_1'),
        ]),
        sendDone: false,
      ).toList();

      expect(frames, [
        'data: {"type":"text-end","id":"txt_1"}\n\n',
      ]);
    });

    test('keeps JSON with newline text in a single data line', () async {
      final frames = await toUiMessageSseStream(
        Stream<UiMessageChunk>.fromIterable([
          TextDeltaUiMessageChunk('txt_1', 'a\nb'),
        ]),
        sendDone: false,
      ).toList();

      expect(frames.single, contains(r'"delta":"a\nb"'));
      expect(frames.single.split('\n'), [
        r'data: {"type":"text-delta","id":"txt_1","delta":"a\nb"}',
        '',
        '',
      ]);
    });

    test('propagates source stream errors and does not append done', () async {
      final controller = StreamController<UiMessageChunk>();
      final error = StateError('boom');
      final expectation = expectLater(
        toUiMessageSseStream(controller.stream).toList(),
        throwsA(same(error)),
      );

      controller
        ..add(TextStartUiMessageChunk('txt_1'))
        ..addError(error)
        ..add(TextEndUiMessageChunk('txt_1'));
      await controller.close();
      await expectation;
    });
  });
}
