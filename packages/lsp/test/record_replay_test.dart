import 'dart:convert';

import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('validates, redacts, reframes, and replays without proposals', () async {
    final recorder = LspRecorder(maxEntries: 2);
    final frame = recorder.record(
      sender: LspMessageSender.server,
      source: jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'window/showMessageRequest',
        'params': <String, Object?>{
          'type': 3,
          'message': 'token=not-a-secret',
          'secret': 'should-not-survive',
        },
      }),
    );

    final encoded = utf8.decode(frame.contentLengthBytes);
    expect(encoded, contains('Content-Length:'));
    expect(encoded, isNot(contains('should-not-survive')));
    expect(frame.envelope['method'], 'window/showMessageRequest');

    var replayed = 0;
    await recorder.replay((recorded) {
      replayed += 1;
      expect(recorded.envelope['method'], 'window/showMessageRequest');
    });
    expect(replayed, 1);
  });

  test('rejects invalid input before recording it', () {
    final recorder = LspRecorder();
    expect(
      () => recorder.record(
        sender: LspMessageSender.client,
        source: '{"jsonrpc":"2.0","method":"unknown"}',
      ),
      throwsA(isA<LspCodecException>()),
    );
    expect(recorder.frames, isEmpty);
  });
}
