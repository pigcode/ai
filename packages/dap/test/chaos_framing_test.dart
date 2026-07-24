import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

void main() {
  test('decodes arbitrary chunks and interleaved event/response frames', () {
    final response = _frame(
      '{"seq":2,"type":"response","request_seq":1,'
      '"success":true,"command":"threads"}',
    );
    final event = _frame(
      '{"seq":3,"type":"event","event":"stopped",'
      '"body":{"reason":"breakpoint","threadId":1}}',
    );
    final framer = ContentLengthFramer();
    final frames = <List<int>>[];
    for (final byte in <int>[...response, ...event]) {
      frames.addAll(framer.add(<int>[byte]));
    }
    framer.close();
    expect(frames.map(utf8.decode), hasLength(2));
  });

  test('rejects duplicate headers, truncation, and oversize', () {
    expect(
      () => ContentLengthFramer().add(
        ascii.encode(
          'Content-Length: 1\r\nContent-Length: 1\r\n\r\nx',
        ),
      ),
      throwsA(isA<FramingException>()),
    );
    final truncated = ContentLengthFramer()
      ..add(ascii.encode('Content-Length: 2\r\n\r\nx'));
    expect(() => truncated.close(), throwsA(isA<FramingException>()));
    expect(
      () => ContentLengthFramer(
        limits: ProtocolLimits(maxMessageBytes: 1),
      ).add(ascii.encode('Content-Length: 2\r\n\r\n')),
      throwsA(isA<FramingException>()),
    );
  });
}

List<int> _frame(String body) {
  final bytes = utf8.encode(body);
  return <int>[
    ...ascii.encode('Content-Length: ${bytes.length}\r\n\r\n'),
    ...bytes,
  ];
}
