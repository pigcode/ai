import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

void main() {
  group('ProtocolLimits', () {
    test('rejects non-positive values and values above hard ceilings', () {
      expect(
        () => ProtocolLimits(maxMessageBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => ProtocolLimits(
          maxMessageBytes: ProtocolLimits.hardMaxMessageBytes + 1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('NdjsonFramer', () {
    test('handles byte-by-byte UTF-8, CRLF, blank lines, and sticky frames',
        () {
      final framer = NdjsonFramer();
      final output = <String>[];
      final bytes = utf8.encode('{"text":"猪"}\r\n\n[1]\n{"ok":true}\r');

      for (final byte in bytes) {
        output.addAll(framer.add(<int>[byte]));
      }

      expect(output, <String>[
        '{"text":"猪"}',
        '[1]',
        '{"ok":true}',
      ]);
      expect(framer.close(), isEmpty);
      expect(framer.bufferedByteCount, 0);
    });

    test('releases buffered data after truncated EOF', () {
      final framer = NdjsonFramer()..add(utf8.encode('{"partial":'));

      _expectFramingError(
        framer.close,
        'ndjson_truncated_frame',
      );
      expect(framer.bufferedByteCount, 0);
    });

    test('can reject empty records with an explicit policy', () {
      final framer = NdjsonFramer(
        emptyLinePolicy: NdjsonEmptyLinePolicy.reject,
      );

      _expectFramingError(
        () => framer.add(utf8.encode('\n')),
        'ndjson_empty_frame',
      );
      expect(framer.bufferedByteCount, 0);
    });

    test('fails closed on oversized and invalid UTF-8 frames', () {
      final oversized = NdjsonFramer(
        limits: ProtocolLimits(maxMessageBytes: 4),
      );
      _expectFramingError(
        () => oversized.add(utf8.encode('12345')),
        'ndjson_frame_too_large',
      );
      expect(oversized.bufferedByteCount, 0);

      final invalidUtf8 = NdjsonFramer();
      _expectFramingError(
        () => invalidUtf8.add(<int>[0xc3, 0x28, 0x0a]),
        'ndjson_invalid_utf8',
      );
      expect(invalidUtf8.bufferedByteCount, 0);
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
