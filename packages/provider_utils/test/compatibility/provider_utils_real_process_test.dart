import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

const _peerVersion = 'phase1-ai-core-peer-v1';
const _deadline = Duration(seconds: 5);

void main() {
  // Compatibility fixture (real-process): P1-UTIL-01
  // Compatibility fixture (real-process): P1-UTIL-02
  // Compatibility fixture (real-process): P1-UTIL-03
  // Compatibility fixture (real-process): P1-UTIL-04
  // Compatibility fixture (real-process): P1-UTIL-05
  // Compatibility fixture (real-process): P1-UTIL-06
  // Compatibility fixture (real-process): P1-UTIL-07
  // Compatibility fixture (real-process): P1-UTIL-08
  test('public provider utilities exchange all fixtures with the fixed peer',
      () async {
    final peer = await _PeerProcess.start();
    final client = http.Client();
    try {
      final baseUrl = 'http://${peer.host}:${peer.port}';

      final jsonEcho = await peer.request(<String, Object?>{
        'id': 'json',
        'op': 'echo',
        'value': '{"value":1}',
      });
      final parsed = safeParseJson(jsonEcho['value']! as String);
      expect(parsed, isA<ParseSuccess<JsonValue>>());
      final validator = JsonSchemaValidator.fromContract(
        const JsonSchema(<String, Object?>{
          'type': 'object',
          'required': <Object?>['value'],
        }),
      );
      expect(
        validator.validate((parsed as ParseSuccess<JsonValue>).value),
        isA<ValidationSuccess>(),
      );
      expect(safeParseJson('{"value":1} trailing'),
          isA<ParseFailure<JsonValue>>());

      final echo = await postJsonToApi<JsonObject>(
        url: Uri.parse('$baseUrl/echo?fixture=provider-utils'),
        headers: const <String, String>{
          'User-Agent': 'real-process/1',
          'x-fixture': 'provider-utils',
        },
        body: const <String, Object?>{'prompt': 'hello process'},
        client: client,
        successHandler: jsonResponseHandler<JsonObject>(
          decode: (json) => json as JsonObject,
        ),
        failureHandler: (_) async => throw StateError('unexpected failure'),
      );
      expect(echo['method'], 'POST');
      expect(echo['query'], <String, Object?>{
        'fixture': 'provider-utils',
      });
      expect(echo['body'], <String, Object?>{'prompt': 'hello process'});
      expect(
        (echo['headerNames'] as List<Object?>).cast<String>(),
        containsAll(<String>['content-type', 'user-agent', 'x-fixture']),
      );

      await expectLater(
        postJsonToApi<void>(
          url: Uri.parse('$baseUrl/status?code=503'),
          body: null,
          client: client,
          successHandler: (_) async {},
          failureHandler: jsonErrorResponseHandler(
            errorToMessage: (json) => 'status '
                '${(json as Map<String, Object?>)['status'] as int}',
          ),
        ),
        throwsA(
          isA<ApiCallError>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having((error) => error.isRetryable, 'isRetryable', isTrue),
        ),
      );

      final sse = await postJsonStreamToApi<JsonValue>(
        url: Uri.parse('$baseUrl/sse'),
        body: const <String, Object?>{
          'events': <Object?>[
            <String, Object?>{'delta': 'hello'},
            <String, Object?>{'delta': ' world'},
          ],
        },
        client: client,
        successHandler: eventSourceResponseHandler<JsonValue>(
          decode: (json) => json,
        ),
        failureHandler: (_) async => throw StateError('unexpected failure'),
      );
      final sseEvents = await sse.toList();
      expect(sseEvents, hasLength(2));
      expect(
        sseEvents.whereType<ParseSuccess<JsonValue>>().map(
              (event) => (event.value as Map<String, Object?>)['delta'],
            ),
        <Object?>['hello', ' world'],
      );

      expect(validateBaseUrl(baseUrl), baseUrl);
      expect(
        () => validateBaseUrl(''),
        throwsA(isA<InvalidArgumentError>()),
      );
      expect(isSameOrigin('$baseUrl/result', '$baseUrl/v1'), isTrue);

      final redirected = await fetchWithValidatedRedirects(
        url: '$baseUrl/redirect?status=302&target=%2Fecho',
        headers: const <String, String>{
          'Authorization': 'Bearer process-secret',
          'User-Agent': 'real-process/1',
        },
        client: client,
        credentialedOrigin: baseUrl,
        trustedOrigin: baseUrl,
      );
      final redirectedBody =
          jsonDecode(utf8.decode(await redirected.stream.toBytes()))
              as Map<String, Object?>;
      expect(redirected.statusCode, 200);
      expect(
        (redirectedBody['headerNames'] as List<Object?>).cast<String>(),
        containsAll(<String>['authorization', 'user-agent']),
      );

      final notRedirected = await fetchWithValidatedRedirects(
        url: '$baseUrl/redirect?status=304&target=%2Fmissing',
        client: client,
        trustedOrigin: baseUrl,
      );
      expect(notRedirected.statusCode, 304);
      await notRedirected.stream.drain<void>();
      expect(
        () => validateDownloadUrl('http://127.0.0.1/private'),
        throwsA(isA<DownloadError>()),
      );
      expect(
        () => validateDownloadUrl('https://example.com/public'),
        returnsNormally,
      );

      final mediaEcho = await peer.request(<String, Object?>{
        'id': 'media',
        'op': 'echo',
        'value': base64Encode(
          <int>[0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70],
        ),
      });
      expect(
        detectMediaType(
          data: mediaEcho['value']! as String,
          topLevelType: 'audio',
        ),
        'audio/mp4',
      );
      final id3ThenMp3 = Uint8List.fromList(
        <int>[0x49, 0x44, 0x33, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xfb],
      );
      expect(
        detectMediaType(data: id3ThenMp3, topLevelType: 'audio'),
        'audio/mpeg',
      );

      final multipart = await postMultipartToApi<JsonObject>(
        url: Uri.parse('$baseUrl/multipart'),
        client: client,
        build: (request) {
          request.files.add(
            http.MultipartFile.fromString(
              'file',
              'fixture body',
              filename: 'fixture.txt',
            ),
          );
        },
        successHandler: jsonResponseHandler<JsonObject>(
          decode: (json) => json as JsonObject,
        ),
        failureHandler: (_) async => throw StateError('unexpected failure'),
      );
      expect(multipart['method'], 'POST');
      expect(multipart['contentType'], startsWith('multipart/form-data;'));
      expect(multipart['containsFixtureFilename'], isTrue);
      expect(multipart['containsFixtureBody'], isTrue);

      final toolEcho = await peer.request(<String, Object?>{
        'id': 'tool',
        'op': 'echo',
        'value': <Object?>[
          <String, Object?>{
            'index': 0,
            'id': 'call-1',
            'name': 'lookup',
            'argumentsDelta': '{"query":',
          },
          <String, Object?>{
            'index': 0,
            'argumentsDelta': '"dart"}',
          },
        ],
      });
      final tracker = StreamingToolCallTracker();
      final terminalEvents = <LanguageModelStreamPart>[];
      for (final item in toolEcho['value']! as List<Object?>) {
        final delta = item as Map<String, Object?>;
        terminalEvents.addAll(
          tracker.addDelta(
            index: delta['index'] as int?,
            id: delta['id'] as String?,
            name: delta['name'] as String?,
            argumentsDelta: delta['argumentsDelta'] as String?,
          ),
        );
      }
      expect(terminalEvents.whereType<ToolInputStart>(), hasLength(1));
      expect(terminalEvents.whereType<ToolInputEnd>(), hasLength(1));
      expect(terminalEvents.whereType<ToolCall>().single.input,
          '{"query":"dart"}');
      expect(tracker.finishAll(), isEmpty);

      await peer.shutdown();
      expect(await peer.process.exitCode.timeout(_deadline), 0);
      expect((await peer.stderrOutput).trim(), isEmpty);
    } finally {
      client.close();
      await peer.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}

final class _PeerProcess {
  _PeerProcess._(
    this.process,
    this._lines,
    this.stderrOutput, {
    required this.host,
    required this.port,
  });

  final Process process;
  final StreamIterator<String> _lines;
  final Future<String> stderrOutput;
  final String host;
  final int port;
  var _shutdown = false;

  static Future<_PeerProcess> start() async {
    final repositoryRoot = Directory.current.parent.parent;
    final peerFile = File.fromUri(
      repositoryRoot.uri.resolve('tool/fixtures/ai_core_peer.dart'),
    );
    final expectedHashResult = Process.runSync(
      'git',
      <String>['hash-object', '--', peerFile.path],
      workingDirectory: repositoryRoot.path,
    );
    expect(expectedHashResult.exitCode, 0);
    final expectedHash = (expectedHashResult.stdout as String).trim();
    final environment = <String, String>{
      for (final key in const <String>[
        'PATH',
        'SystemRoot',
        'TEMP',
        'TMP',
        'TMPDIR',
      ])
        if (Platform.environment[key] case final String value) key: value,
    };
    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>[peerFile.path],
      workingDirectory: repositoryRoot.path,
      environment: environment,
      includeParentEnvironment: false,
    );
    final lines = StreamIterator<String>(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final stderrOutput = process.stderr.transform(utf8.decoder).join();
    expect(await lines.moveNext().timeout(_deadline), isTrue);
    final ready = jsonDecode(lines.current) as Map<String, Object?>;
    expect(ready['type'], 'ready');
    expect(ready['version'], _peerVersion);
    expect(ready['sourceBlobHash'], expectedHash);
    expect(ready['host'], InternetAddress.loopbackIPv4.address);
    return _PeerProcess._(
      process,
      lines,
      stderrOutput,
      host: ready['host']! as String,
      port: ready['port']! as int,
    );
  }

  Future<Map<String, Object?>> request(Map<String, Object?> request) async {
    process.stdin.writeln(jsonEncode(request));
    await process.stdin.flush();
    expect(await _lines.moveNext().timeout(_deadline), isTrue);
    return jsonDecode(_lines.current) as Map<String, Object?>;
  }

  Future<void> shutdown() async {
    if (_shutdown) {
      return;
    }
    final response = await request(<String, Object?>{
      'id': 'shutdown',
      'op': 'shutdown',
    });
    expect(response['ok'], isTrue);
    _shutdown = true;
  }

  Future<void> dispose() async {
    if (!_shutdown) {
      try {
        await shutdown();
      } on Object {
        process.kill();
      }
    }
    await _lines.cancel();
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 10));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
    }
  }
}
