import 'dart:convert';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('validates, redacts token/header/path, and recomputes NDJSON', () {
    final recorder = McpRecorder(maxEntries: 2);
    final frame = recorder.record(
      role: McpMessageRole.clientRequest,
      source: jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'inspect',
          'arguments': <String, Object?>{
            'apiToken': 'secret-token',
            'targetPath': '/private/workspace/file.txt',
            'headers': <String, Object?>{
              'Authorization': 'Bearer secret-token',
              'X-Trace': 'private-trace',
            },
          },
        },
      }),
    );

    expect(frame.ndjsonLine.endsWith('\n'), isTrue);
    expect(frame.ndjsonLine, isNot(contains('secret-token')));
    expect(frame.ndjsonLine, isNot(contains('/private/workspace')));
    expect(frame.ndjsonLine, isNot(contains('private-trace')));
    final params = frame.envelope['params']! as Map<String, Object?>;
    final arguments = params['arguments']! as Map<String, Object?>;
    expect(arguments['apiToken'], '[REDACTED]');
    expect(arguments['targetPath'], '/redacted');
    expect(
      arguments['headers'],
      <String, Object?>{
        'Authorization': '[REDACTED]',
        'X-Trace': '[REDACTED]',
      },
    );
    expect(utf8.decode(recorder.fixtureBytes()), frame.ndjsonLine);
  });

  test('rejects invalid input before retaining anything', () {
    final recorder = McpRecorder();

    expect(
      () => recorder.record(
        role: McpMessageRole.clientRequest,
        source: '{"jsonrpc":"2.0","id":1,"method":"tools/call"}',
      ),
      throwsA(isA<McpCodecException>()),
    );
    expect(recorder.frames, isEmpty);
  });

  test('replay is observational and cannot execute side effects', () async {
    final recorder = McpRecorder()
      ..record(
        role: McpMessageRole.clientRequest,
        source: jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': <String, Object?>{
            'name': 'delete',
            'arguments': <String, Object?>{},
          },
        }),
      )
      ..record(
        role: McpMessageRole.clientRequest,
        source: jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'resources/read',
          'params': <String, Object?>{
            'uri': 'file:///private/file.txt',
          },
        }),
      );
    var toolCalls = 0;
    var resourceReads = 0;
    final replayed = <String>[];

    await recorder.replay((frame) {
      replayed.add(frame.envelope['method']! as String);
    });

    expect(replayed, <String>['tools/call', 'resources/read']);
    expect(toolCalls, 0);
    expect(resourceReads, 0);
  });
}
