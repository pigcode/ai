import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

void main() {
  group('SseDecoder', () {
    test('decodes byte-by-byte multiline events, IDs, retry, and comments', () {
      final decoder = SseDecoder();
      final events = <SseEvent>[];
      final bytes = utf8.encode(
        ': keepalive\r\n'
        'id: evt-1\r\n'
        'event: message\r\n'
        'retry: 1500\r\n'
        'data: first 猪\r\n'
        'data: second\r\n'
        '\r\n',
      );

      for (final byte in bytes) {
        events.addAll(decoder.add(<int>[byte]));
      }

      expect(events, hasLength(1));
      expect(events.single.data, 'first 猪\nsecond');
      expect(events.single.id, 'evt-1');
      expect(events.single.event, 'message');
      expect(events.single.retry, const Duration(milliseconds: 1500));
      expect(decoder.close(), isEmpty);
      expect(decoder.bufferedByteCount, 0);
    });

    test('handles all-in-one LF input and ignores unknown or invalid fields',
        () {
      final decoder = SseDecoder();

      final events = decoder.add(
        utf8.encode(
          'unknown: ignored\n'
          'retry: invalid\n'
          'id: ignored\u0000id\n'
          'data: one\n\n'
          'data: two\n\n',
        ),
      );

      expect(
        events,
        <SseEvent>[
          const SseEvent(data: 'one'),
          const SseEvent(data: 'two'),
        ],
      );
      expect(decoder.close(), isEmpty);
    });

    test('ignores retry delays above the configured bound', () {
      final decoder = SseDecoder(
        limits: ProtocolLimits(maxSseRetryMilliseconds: 1000),
      );

      final events = decoder.add(
        utf8.encode(
          'retry: 1000\n'
          'data: accepted\n\n'
          'retry: 1001\n'
          'data: bounded\n\n',
        ),
      );

      expect(events[0].retry, const Duration(milliseconds: 1000));
      expect(events[1].retry, isNull);
      expect(
        decoder.reconnectionDelay,
        const Duration(milliseconds: 1000),
      );
      expect(decoder.close(), isEmpty);
    });

    test('releases buffers after line, event, UTF-8, and EOF failures', () {
      final lineTooLarge = SseDecoder(
        limits: ProtocolLimits(maxLineBytes: 4),
      );
      _expectFramingError(
        () => lineTooLarge.add(utf8.encode('data:')),
        'sse_line_too_large',
      );
      expect(lineTooLarge.bufferedByteCount, 0);

      final eventTooLarge = SseDecoder(
        limits: ProtocolLimits(
          maxLineBytes: 16,
          maxSseEventBytes: 8,
        ),
      );
      _expectFramingError(
        () => eventTooLarge.add(utf8.encode('data: 123\n')),
        'sse_event_too_large',
      );
      expect(eventTooLarge.bufferedByteCount, 0);

      final invalidUtf8 = SseDecoder();
      _expectFramingError(
        () => invalidUtf8.add(<int>[0x64, 0x61, 0x74, 0x61, 0x3a, 0xc3, 0x0a]),
        'sse_invalid_utf8',
      );
      expect(invalidUtf8.bufferedByteCount, 0);

      final truncated = SseDecoder()..add(utf8.encode('data: partial'));
      _expectFramingError(truncated.close, 'sse_truncated_event');
      expect(truncated.bufferedByteCount, 0);
    });
  });
}

void _expectFramingError(void Function() body, String code) {
  expect(
    body,
    throwsA(
      isA<FramingException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    ),
  );
}
