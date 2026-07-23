import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

void main() {
  group('ContentLengthFramer', () {
    test('handles byte-by-byte input, zero bodies, and sticky frames', () {
      final framer = ContentLengthFramer();
      final frames = <List<int>>[];
      final bytes = ascii.encode(
        'Content-Length: 2\r\nX-Test: yes\r\n\r\n{}'
        'content-length: 0\r\n\r\n'
        'Content-Length: 3\r\n\r\nabc',
      );

      for (final byte in bytes) {
        frames.addAll(framer.add(<int>[byte]));
      }

      expect(
        frames.map(utf8.decode).toList(),
        <String>['{}', '', 'abc'],
      );
      expect(framer.close(), isEmpty);
      expect(framer.bufferedByteCount, 0);
    });

    test('distinguishes duplicate and conflicting content lengths', () {
      final duplicate = ContentLengthFramer();
      _expectFramingError(
        () => duplicate.add(
          ascii.encode(
            'Content-Length: 2\r\nContent-Length: 2\r\n\r\n{}',
          ),
        ),
        'content_length_duplicate',
      );
      expect(duplicate.bufferedByteCount, 0);

      final conflict = ContentLengthFramer();
      _expectFramingError(
        () => conflict.add(
          ascii.encode(
            'Content-Length: 2\r\nContent-Length: 3\r\n\r\n{}',
          ),
        ),
        'content_length_conflict',
      );
      expect(conflict.bufferedByteCount, 0);
    });

    test('rejects malformed, oversized, and truncated frames', () {
      final malformed = ContentLengthFramer();
      _expectFramingError(
        () => malformed.add(ascii.encode('Content-Length: -1\r\n\r\n')),
        'content_length_invalid',
      );

      final oversizedHeader = ContentLengthFramer(
        limits: ProtocolLimits(maxHeaderBytes: 16),
      );
      _expectFramingError(
        () => oversizedHeader.add(ascii.encode('X-Long: 1234567890')),
        'content_length_header_too_large',
      );
      expect(oversizedHeader.bufferedByteCount, 0);

      final oversizedBody = ContentLengthFramer(
        limits: ProtocolLimits(maxMessageBytes: 2),
      );
      _expectFramingError(
        () => oversizedBody.add(ascii.encode('Content-Length: 3\r\n\r\n')),
        'content_length_body_too_large',
      );
      expect(oversizedBody.bufferedByteCount, 0);

      final truncatedHeader = ContentLengthFramer()
        ..add(ascii.encode('Content-Length: 2\r\n'));
      _expectFramingError(
        truncatedHeader.close,
        'content_length_truncated_header',
      );
      expect(truncatedHeader.bufferedByteCount, 0);

      final truncatedBody = ContentLengthFramer()
        ..add(ascii.encode('Content-Length: 2\r\n\r\n{'));
      _expectFramingError(
        truncatedBody.close,
        'content_length_truncated_body',
      );
      expect(truncatedBody.bufferedByteCount, 0);
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
