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

  test('redacts credential maps nested through arbitrary list depth', () async {
    const secret = 'dap-deep-secret';
    final recorder = DapRecorder();
    final frame = recorder.record(
      source: jsonEncode(<String, Object?>{
        'seq': 1,
        'type': 'request',
        'command': 'launch',
        'arguments': <String, Object?>{
          'custom': <Object?>[
            <Object?>[
              <String, Object?>{'token': secret},
            ],
          ],
        },
      }),
    );

    expect(jsonEncode(frame.envelope), isNot(contains(secret)));
    expect(utf8.decode(frame.contentLengthBytes), isNot(contains(secret)));
    await recorder.replay((recorded) {
      expect(jsonEncode(recorded.envelope), isNot(contains(secret)));
      expect(
        utf8.decode(recorded.contentLengthBytes),
        isNot(contains(secret)),
      );
    });
  });

  test('redacts compound credential keys in launch and attach', () async {
    for (final command in <String>['launch', 'attach']) {
      final secrets = <String>[
        '$command-client-secret',
        '$command-access-token',
        '$command-api-key',
      ];
      final recorder = DapRecorder();
      final frame = recorder.record(
        source: jsonEncode(<String, Object?>{
          'seq': 1,
          'type': 'request',
          'command': command,
          'arguments': <String, Object?>{
            'clientSecret': secrets[0],
            'nested': <String, Object?>{'accessToken': secrets[1]},
            'custom': <Object?>[
              <Object?>[
                <String, Object?>{'apiKey': secrets[2]},
              ],
            ],
          },
        }),
      );

      for (final secret in secrets) {
        expect(jsonEncode(frame.envelope), isNot(contains(secret)));
        expect(
          utf8.decode(frame.contentLengthBytes),
          isNot(contains(secret)),
        );
      }
      await recorder.replay((recorded) {
        for (final secret in secrets) {
          expect(jsonEncode(recorded.envelope), isNot(contains(secret)));
          expect(
            utf8.decode(recorded.contentLengthBytes),
            isNot(contains(secret)),
          );
        }
      });
    }
  });
}
