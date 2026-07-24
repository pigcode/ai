import 'dart:convert';

import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('validates, redacts, reframes, and replays without proposals', () async {
    final recorder = DapRecorder(maxEntries: 2);
    final frame = recorder.record(
      source: jsonEncode(<String, Object?>{
        'seq': 1,
        'type': 'request',
        'command': 'runInTerminal',
        'arguments': <String, Object?>{
          'cwd': '/workspace',
          'args': <Object?>['dart', 'run'],
          'env': <String, Object?>{'SECRET': 'do-not-record'},
        },
      }),
    );
    final encoded = utf8.decode(frame.contentLengthBytes);
    expect(encoded, isNot(contains('do-not-record')));
    expect(frame.envelope['command'], 'runInTerminal');

    var replayed = 0;
    await recorder.replay((_) => replayed += 1);
    expect(replayed, 1);
  });

  test('rejects invalid frames before retaining them', () {
    final recorder = DapRecorder();
    expect(
      () => recorder.record(
        source: '{"seq":0,"type":"event","event":"initialized"}',
      ),
      throwsA(isA<DapCodecException>()),
    );
    expect(recorder.frames, isEmpty);
  });
}
