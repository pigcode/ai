import 'dart:convert';

import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:test/test.dart';

void main() {
  test('validates, redacts, and recomputes NDJSON before recording', () {
    final recorder = AcpRecorder(maxEntries: 2);

    final frame = recorder.record(
      root: AcpMessageRoot.client,
      source: jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'session/new',
        'params': <String, Object?>{
          'cwd': '/private/workspace',
          'mcpServers': <Object?>[],
          '_meta': <String, Object?>{'apiToken': 'secret-token'},
        },
      }),
    );

    expect(frame.ndjsonLine.endsWith('\n'), isTrue);
    expect(frame.ndjsonLine, isNot(contains('/private/workspace')));
    expect(frame.ndjsonLine, isNot(contains('secret-token')));
    expect(
      (frame.envelope['params']! as Map<String, Object?>)['cwd'],
      '/redacted',
    );
    expect(
      utf8.decode(recorder.fixtureBytes()),
      frame.ndjsonLine,
    );
  });

  test('rejects invalid input before retaining anything', () {
    final recorder = AcpRecorder();

    expect(
      () => recorder.record(
        root: AcpMessageRoot.client,
        source: '{"jsonrpc":"2.0","id":1,"method":"fs/read_text_file"}',
      ),
      throwsA(isA<AcpCodecException>()),
    );
    expect(recorder.frames, isEmpty);
  });

  test('replay is observational and never executes reverse side effects',
      () async {
    final recorder = AcpRecorder()
      ..record(
        root: AcpMessageRoot.agent,
        source: jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'fs/read_text_file',
          'params': <String, Object?>{
            'sessionId': 'session-1',
            'path': '/private/file.txt',
          },
        }),
      )
      ..record(
        root: AcpMessageRoot.agent,
        source: jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'terminal/create',
          'params': <String, Object?>{
            'sessionId': 'session-1',
            'command': 'echo',
          },
        }),
      );
    var filesystemCalls = 0;
    var terminalCalls = 0;
    final replayed = <String>[];

    await recorder.replay((frame) {
      replayed.add(
        (frame.envelope['method']! as String),
      );
    });

    expect(replayed, <String>['fs/read_text_file', 'terminal/create']);
    expect(filesystemCalls, 0);
    expect(terminalCalls, 0);
  });
}
