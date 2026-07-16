import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

/// 把一组字节块喂给 [sseTransformer],收集全部产出的事件。
Future<List<ServerSentEvent>> collectEvents(List<List<int>> chunks) {
  final controller = StreamController<List<int>>();
  final events = Stream<List<int>>.fromIterable(chunks)
      .transform(sseTransformer())
      .toList();
  controller.close();
  return events;
}

/// 按字符串块喂给 [sseTransformer](UTF-8 编码后逐块下发)。
Future<List<ServerSentEvent>> collectEventsFromStrings(
  List<String> chunks,
) {
  return collectEvents(
    chunks.map((chunk) => utf8.encode(chunk)).toList(growable: false),
  );
}

void main() {
  group('ServerSentEvent value equality', () {
    test('two events with identical fields are equal', () {
      const a = ServerSentEvent(event: 'message', data: 'hi', id: '1');
      const b = ServerSentEvent(event: 'message', data: 'hi', id: '1');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('events differing in data are not equal', () {
      const a = ServerSentEvent(data: 'hi');
      const b = ServerSentEvent(data: 'bye');
      expect(a, isNot(equals(b)));
    });

    test('event and id default to null', () {
      const event = ServerSentEvent(data: 'hi');
      expect(event.event, isNull);
      expect(event.id, isNull);
    });
  });

  group('sseTransformer basic frame parsing', () {
    test('parses a single data-only frame terminated by a blank line',
        () async {
      final events = await collectEventsFromStrings(<String>[
        'data: hello\n\n',
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(data: 'hello'),
          ]));
    });

    test('parses event/id/data fields on one frame', () async {
      final events = await collectEventsFromStrings(<String>[
        'event: update\nid: 42\ndata: payload\n\n',
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(event: 'update', data: 'payload', id: '42'),
          ]));
    });

    test('strips a single leading space after the field colon', () async {
      final events = await collectEventsFromStrings(<String>[
        'data:  two leading spaces collapse to one stripped\n\n',
      ]);

      expect(
        events.single.data,
        equals(' two leading spaces collapse to one stripped'),
      );
    });

    test('field value with no leading space is kept as-is', () async {
      final events = await collectEventsFromStrings(<String>[
        'data:no-space\n\n',
      ]);

      expect(events.single.data, equals('no-space'));
    });

    test('multiple frames in one chunk are all emitted in order', () async {
      final events = await collectEventsFromStrings(<String>[
        'data: first\n\ndata: second\n\n',
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(data: 'first'),
            const ServerSentEvent(data: 'second'),
          ]));
    });
  });

  group('sseTransformer multi-line data', () {
    test('joins multiple data lines with \\n', () async {
      final events = await collectEventsFromStrings(<String>[
        'data: line1\ndata: line2\ndata: line3\n\n',
      ]);

      expect(events.single.data, equals('line1\nline2\nline3'));
    });
  });

  group('sseTransformer comment lines', () {
    test('lines starting with colon are ignored', () async {
      final events = await collectEventsFromStrings(<String>[
        ': this is a comment\ndata: real payload\n\n',
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(data: 'real payload'),
          ]));
    });

    test('a comment-only frame does not dispatch any event', () async {
      final events = await collectEventsFromStrings(<String>[
        ': just a comment\n\n',
      ]);

      expect(events, isEmpty);
    });
  });

  group('sseTransformer line-ending normalization', () {
    test('CRLF-terminated lines parse identically to LF', () async {
      final events = await collectEventsFromStrings(<String>[
        'data: hello\r\n\r\n',
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(data: 'hello'),
          ]));
    });

    test('bare CR-terminated lines parse identically to LF', () async {
      final events = await collectEventsFromStrings(<String>[
        'data: hello\r\r',
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(data: 'hello'),
          ]));
    });

    test('mixed CRLF/LF frames both parse correctly', () async {
      final events = await collectEventsFromStrings(<String>[
        'data: a\r\ndata: b\n\r\n',
      ]);

      expect(events.single.data, equals('a\nb'));
    });
  });

  group('sseTransformer chunk-boundary splitting', () {
    test('a frame split across two chunks mid-field is reassembled', () async {
      final events = await collectEventsFromStrings(<String>[
        'data: hel',
        'lo\n\n',
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(data: 'hello'),
          ]));
    });

    test('a frame split exactly at the blank-line boundary still dispatches',
        () async {
      final events = await collectEventsFromStrings(<String>[
        'data: hello\n',
        '\n',
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(data: 'hello'),
          ]));
    });

    test(
        'a multi-byte UTF-8 character split across chunk boundary decodes correctly',
        () async {
      // "你好" 中的每个字符在 UTF-8 下是 3 字节；在第一个字符中间切断字节流，
      // 验证跨块的流式 UTF-8 解码不会产生乱码或异常。
      final fullBytes = utf8.encode('data: 你好\n\n');
      final splitPoint = fullBytes.length - 5;
      final events = await collectEvents(<List<int>>[
        fullBytes.sublist(0, splitPoint),
        fullBytes.sublist(splitPoint),
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(data: '你好'),
          ]));
    });
  });

  group('sseTransformer CRLF split across chunk boundaries', () {
    test(
        'a CRLF whose \\r ends one chunk and \\n starts the next is treated '
        'as one line break, not two', () async {
      // 回归测试：`\r` 落在块尾、配对的 `\n` 落在下一块块首时，二者属于
      // 同一个 CRLF 换行，不能被当成两次独立换行处理（否则会把本应合并
      // 的多行 data 提前分发拆成两个事件）。
      final events = await collectEventsFromStrings(<String>[
        'data: a\r',
        '\ndata: b\r\n\r\n',
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(data: 'a\nb'),
          ]));
    });

    test(
        'a bare \\r at chunk end followed by a chunk not starting with \\n '
        'still dispatches on the blank line as two separate frames', () async {
      // 块尾的 `\r` 若不是与下一块块首的 `\n` 配对（下一块以 `\r` 开头），
      // 则两者都各自独立地按换行处理：第一段被空行终止分发为一个事件，
      // 紧接着的 `data: y` 帧由随后的空行分发为第二个事件。
      final events = await collectEventsFromStrings(<String>[
        'data: x\r',
        '\r\ndata: y\r\n\r\n',
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(data: 'x'),
            const ServerSentEvent(data: 'y'),
          ]));
    });
  });

  group('sseTransformer misc fields', () {
    test('retry field is ignored and does not affect data/event/id', () async {
      final events = await collectEventsFromStrings(<String>[
        'retry: 5000\ndata: payload\n\n',
      ]);

      expect(
          events,
          equals(<ServerSentEvent>[
            const ServerSentEvent(data: 'payload'),
          ]));
    });

    test('a frame with no data field does not dispatch an event', () async {
      final events = await collectEventsFromStrings(<String>[
        'event: ping\nid: 7\n\n',
      ]);

      expect(events, isEmpty);
    });

    test('an unterminated trailing frame at stream end is not dispatched',
        () async {
      // 无终止空行的末尾帧（流提前结束）不应被分发。
      final events = await collectEventsFromStrings(<String>[
        'data: incomplete',
      ]);

      expect(events, isEmpty);
    });
  });

  group('parseJsonEventStream', () {
    Stream<List<int>> streamOf(List<String> chunks) {
      return Stream<List<int>>.fromIterable(
        chunks.map((chunk) => utf8.encode(chunk)),
      );
    }

    test('parses a sequence of normal JSON frames', () async {
      final results = await parseJsonEventStream(streamOf(<String>[
        'data: {"a": 1}\n\n',
        'data: {"a": 2}\n\n',
      ])).toList();

      expect(results, hasLength(2));
      expect(
        results[0],
        equals(const ParseSuccess<JsonValue>(
          <String, Object?>{'a': 1},
          rawValue: <String, Object?>{'a': 1},
        )),
      );
      expect(
        results[1],
        equals(const ParseSuccess<JsonValue>(
          <String, Object?>{'a': 2},
          rawValue: <String, Object?>{'a': 2},
        )),
      );
    });

    test('skips the [DONE] sentinel without closing the stream early',
        () async {
      final results = await parseJsonEventStream(streamOf(<String>[
        'data: {"a": 1}\n\n',
        'data: [DONE]\n\n',
        'data: {"a": 2}\n\n',
      ])).toList();

      expect(results, hasLength(2));
      expect(
        results[0],
        equals(const ParseSuccess<JsonValue>(
          <String, Object?>{'a': 1},
          rawValue: <String, Object?>{'a': 1},
        )),
      );
      expect(
        results[1],
        equals(const ParseSuccess<JsonValue>(
          <String, Object?>{'a': 2},
          rawValue: <String, Object?>{'a': 2},
        )),
      );
    });

    test('stream ends naturally after a trailing [DONE] with nothing else',
        () async {
      final results = await parseJsonEventStream(streamOf(<String>[
        'data: {"a": 1}\n\n',
        'data: [DONE]\n\n',
      ])).toList();

      expect(results, hasLength(1));
      expect(
        results.single,
        equals(const ParseSuccess<JsonValue>(
          <String, Object?>{'a': 1},
          rawValue: <String, Object?>{'a': 1},
        )),
      );
    });

    test(
        'a malformed JSON frame yields ParseFailure and later frames still arrive',
        () async {
      final results = await parseJsonEventStream(streamOf(<String>[
        'data: {"a": 1}\n\n',
        'data: not-json\n\n',
        'data: {"a": 3}\n\n',
      ])).toList();

      expect(results, hasLength(3));
      expect(results[0], isA<ParseSuccess<JsonValue>>());
      expect(results[1], isA<ParseFailure<JsonValue>>());
      expect(
        (results[1] as ParseFailure<JsonValue>).error,
        isA<JsonParseError>(),
      );
      expect(results[2], isA<ParseSuccess<JsonValue>>());
    });

    test('an error on the source stream propagates as a stream error',
        () async {
      final controller = StreamController<List<int>>();
      final resultsFuture = parseJsonEventStream(controller.stream).toList();

      controller.add(utf8.encode('data: {"a": 1}\n\n'));
      controller.addError(StateError('connection dropped'));
      await controller.close();

      await expectLater(resultsFuture, throwsA(isA<StateError>()));
    });
  });
}
