import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

void main() {
  test('decodes arbitrary UTF-8 byte splits and sticky frames', () {
    final first = _frame('{"text":"🐷"}');
    final second = _frame('{"next":true}');
    final bytes = <int>[...first, ...second];
    final framer = ContentLengthFramer();
    final frames = <List<int>>[];

    for (final byte in bytes) {
      frames.addAll(framer.add(<int>[byte]));
    }
    framer.close();

    expect(frames.map(utf8.decode), ['{"text":"🐷"}', '{"next":true}']);
  });

  test('fails closed on truncation, oversize, and add-after-close', () {
    final truncated = ContentLengthFramer()
      ..add(ascii.encode('Content-Length: 4\r\n\r\n{}'));
    expect(() => truncated.close(), throwsA(isA<FramingException>()));

    final oversize = ContentLengthFramer(
      limits: ProtocolLimits(maxMessageBytes: 3),
    );
    expect(
      () => oversize.add(ascii.encode('Content-Length: 4\r\n\r\n')),
      throwsA(isA<FramingException>()),
    );

    final closed = ContentLengthFramer()..close();
    expect(() => closed.add(const <int>[]), throwsA(isA<FramingException>()));
  });
}

List<int> _frame(String body) {
  final bodyBytes = utf8.encode(body);
  return <int>[
    ...ascii.encode('Content-Length: ${bodyBytes.length}\r\n\r\n'),
    ...bodyBytes,
  ];
}
