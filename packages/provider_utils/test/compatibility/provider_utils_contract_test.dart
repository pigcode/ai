import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

import '../support/fake_http_client.dart';

void main() {
  // Compatibility fixture (unit): P1-UTIL-01
  test('P1-UTIL-01 classifies JSON, schema, malformed, and trailing input', () {
    final parsed = safeParseJson('{"value":1}');
    expect(parsed, isA<ParseSuccess<JsonValue>>());
    expect(
      (parsed as ParseSuccess<JsonValue>).value,
      <String, Object?>{'value': 1},
    );

    final validator = JsonSchemaValidator.fromContract(
      const JsonSchema(<String, Object?>{
        'type': 'object',
        'required': <Object?>['value'],
        'properties': <String, Object?>{
          'value': <String, Object?>{'type': 'integer'},
        },
      }),
    );
    expect(
      validator.validate(<String, Object?>{'value': 1}),
      isA<ValidationSuccess>(),
    );
    expect(
      validator.validate(<String, Object?>{'value': 'wrong'}),
      isA<ValidationFailure>(),
    );
    expect(safeParseJson('{"value":'), isA<ParseFailure<JsonValue>>());
    expect(
      safeParseJson('{"value":1} trailing'),
      isA<ParseFailure<JsonValue>>(),
    );
  });

  // Compatibility fixture (unit): P1-UTIL-02
  test('P1-UTIL-02 parses CR/LF SSE and drops a truncated terminal event',
      () async {
    final bytes = Stream<List<int>>.fromIterable(<List<int>>[
      utf8.encode(': comment\r'),
      utf8.encode('\ndata: first\rdata: second\runknown: ignored\r\r'),
      utf8.encode('data: truncated'),
    ]);

    final events = await bytes.transform(sseTransformer()).toList();
    expect(
      events,
      const <ServerSentEvent>[
        ServerSentEvent(data: 'first\nsecond'),
      ],
    );
  });

  // Compatibility fixture (unit): P1-UTIL-03
  test('P1-UTIL-03 preserves request metadata and maps status/transport errors',
      () async {
    final url = Uri.parse('https://api.example.test/v1/generate');
    final successClient = FakeHttpClient(
      responseBuilder: (_) async => fakeStreamedResponse(
        statusCode: 200,
        body: 'ok',
      ),
    );
    final result = await postJsonToApi<String>(
      url: url,
      headers: const <String, String>{
        'User-Agent': 'fixture/1',
        'x-fixture': 'unit',
      },
      body: const <String, Object?>{'prompt': 'hello'},
      client: successClient,
      successHandler: (context) async =>
          utf8.decode(await context.response.stream.toBytes()),
      failureHandler: (_) async => throw StateError('unexpected failure'),
    );
    expect(result, 'ok');
    expect(successClient.recordedBodies.single, '{"prompt":"hello"}');
    expect(successClient.recordedRequests.single.headers['user-agent'],
        'fixture/1');

    for (final statusCode in <int>[400, 503]) {
      final client = FakeHttpClient(
        responseBuilder: (_) async =>
            fakeStreamedResponse(statusCode: statusCode),
      );
      await expectLater(
        postJsonToApi<void>(
          url: url,
          body: null,
          client: client,
          successHandler: (_) async {},
          failureHandler: (_) async => ApiCallError(
            message: 'status $statusCode',
            url: url.toString(),
            requestBody: null,
            statusCode: statusCode,
          ),
        ),
        throwsA(
          isA<ApiCallError>().having(
            (error) => error.isRetryable,
            'isRetryable',
            statusCode >= 500,
          ),
        ),
      );
    }

    final timeout = TimeoutException('fixture timeout');
    final timeoutClient = FakeHttpClient(exceptionToThrow: timeout);
    await expectLater(
      postJsonToApi<void>(
        url: url,
        body: null,
        client: timeoutClient,
        successHandler: (_) async {},
        failureHandler: (_) async => throw StateError('unexpected failure'),
      ),
      throwsA(
        isA<ApiCallError>()
            .having((error) => error.statusCode, 'statusCode', isNull)
            .having((error) => error.isRetryable, 'isRetryable', isTrue)
            .having((error) => error.cause, 'cause', same(timeout)),
      ),
    );
  });

  // Compatibility fixture (unit): P1-UTIL-04
  test('P1-UTIL-04 rejects empty base URLs and protects credential headers',
      () async {
    expect(validateBaseUrl(null), isNull);
    expect(validateBaseUrl('https://api.example.test/'),
        'https://api.example.test/');
    for (final invalid in <String>[
      '',
      '   ',
      'not-a-url',
      'ftp://example.test',
      'https:///missing-host',
    ]) {
      expect(
        () => validateBaseUrl(invalid),
        throwsA(
          isA<InvalidArgumentError>().having(
            (error) => error.argument,
            'argument',
            'baseURL',
          ),
        ),
      );
    }
    expect(
      isSameOrigin(
        'https://api.example.test/result',
        'https://api.example.test/v1',
      ),
      isTrue,
    );
    expect(
      isSameOrigin(
        'https://cdn.example.test/result',
        'https://api.example.test/v1',
      ),
      isFalse,
    );
    expect(
      isSameOrigin(
        'https://api.example.test:443/result',
        'https://api.example.test/v1',
      ),
      isTrue,
    );
    expect(isSameOrigin('not-a-url', 'https://api.example.test'), isFalse);
    expect(
      sanitizeRequestHeaders(const <String, String>{
        'Host': 'metadata.internal',
        'Cookie': 'session=secret',
        'x-forwarded-for': '127.0.0.1',
        'Authorization': 'Bearer fixture-secret',
      }),
      const <String, String>{
        'Authorization': 'Bearer fixture-secret',
      },
    );

    final client = FakeHttpClient(
      responseBuilder: (request) async {
        if (request.url.host == 'api.example.test') {
          return fakeStreamedResponse(
            statusCode: 302,
            headers: const <String, String>{
              'location': 'https://cdn.example.test/result',
            },
          );
        }
        return fakeStreamedResponse(statusCode: 200, body: 'ok');
      },
    );
    final response = await fetchWithValidatedRedirects(
      url: 'https://api.example.test/start',
      headers: const <String, String>{
        'Authorization': 'Bearer fixture-secret',
        'x-api-key': 'fixture-secret',
        'User-Agent': 'fixture/1',
      },
      client: client,
      credentialedOrigin: 'https://api.example.test',
      trustedOrigin: 'https://api.example.test',
    );
    expect(response.statusCode, 200);
    expect(client.recordedRequests, hasLength(2));
    expect(client.recordedRequests.first.headers['authorization'],
        'Bearer fixture-secret');
    expect(client.recordedRequests.last.headers['authorization'], isNull);
    expect(client.recordedRequests.last.headers['x-api-key'], isNull);
    expect(client.recordedRequests.last.headers['user-agent'], 'fixture/1');
  });

  // Compatibility fixture (unit): P1-UTIL-05
  test('P1-UTIL-05 validates network targets and redirect status allowlist',
      () {
    for (final safe in <String>[
      'https://example.com/file',
      'https://8.8.8.8/file',
      'data:text/plain;base64,aGVsbG8=',
      'http://100.63.255.255/file',
      'http://172.15.255.255/file',
      'http://172.32.0.1/file',
      'http://192.0.3.1/file',
      'http://[2606:4700::1]/file',
      'http://[3fff:1000::1]/file',
      'http://[::ffff:8.8.8.8]/file',
    ]) {
      expect(() => validateDownloadUrl(safe), returnsNormally);
    }
    for (final unsafe in <String>[
      'not-a-url',
      'file:///etc/passwd',
      'http://localhost/file',
      'http://10.0.0.1/file',
      'http://100.64.0.1/file',
      'http://169.254.169.254/file',
      'http://192.0.0.1/file',
      'http://192.0.2.1/file',
      'http://198.18.0.1/file',
      'http://198.51.100.1/file',
      'http://203.0.113.1/file',
      'http://224.0.0.1/file',
      'http://240.0.0.1/file',
      'http://2130706433/file',
      'http://0x7f000001/file',
      'http://0177.0.0.1/file',
      'http://[::1]/file',
      'http://[::ffff:127.0.0.1]/file',
      'http://[64:ff9b::169.254.169.254]/file',
      'http://[fe80::1]/file',
      'http://[fec0::1]/file',
      'http://[2001:db8::1]/file',
      'http://[3fff::1]/file',
      'http://[ff02::1]/file',
    ]) {
      expect(
        () => validateDownloadUrl(unsafe),
        throwsA(isA<DownloadError>()),
        reason: unsafe,
      );
    }
    expect(
      <int>[300, 301, 302, 303, 304, 307, 308].where(isRedirectStatusCode),
      <int>[301, 302, 303, 307, 308],
    );
  });

  // Compatibility fixture (unit): P1-UTIL-06
  test('P1-UTIL-06 bounds ID3 scanning and detects MP4 audio ftyp', () {
    final id3AtLimit = Uint8List(maxId3TagBytes + 12)
      ..setAll(0, <int>[0x49, 0x44, 0x33, 0, 0, 0, 0, 0x07, 0x7f, 0x76])
      ..setAll(maxId3TagBytes, <int>[0xff, 0xfb]);
    expect(
      detectMediaType(data: id3AtLimit, topLevelType: 'audio'),
      'audio/mpeg',
    );

    final oversizedId3 = Uint8List(maxId3TagBytes + 13)
      ..setAll(0, <int>[0x49, 0x44, 0x33, 0, 0, 0, 0, 0x08, 0x00, 0x00])
      ..setAll(maxId3TagBytes + 1, <int>[0xff, 0xfb]);
    expect(
      detectMediaType(data: oversizedId3, topLevelType: 'audio'),
      isNull,
    );
    expect(
      detectMediaType(
        data: Uint8List.fromList(
          <int>[0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70],
        ),
        topLevelType: 'audio',
      ),
      'audio/mp4',
    );
  });

  // Compatibility fixture (unit): P1-UTIL-07
  test('P1-UTIL-07 preserves multipart filename/type and maps body failures',
      () async {
    final url = Uri.parse('https://api.example.test/v1/files');
    final bodyFailure = http.ClientException('body interrupted', url);
    late http.MultipartRequest recorded;
    final client = FakeHttpClient(
      responseBuilder: (request) async {
        recorded = request as http.MultipartRequest;
        return http.StreamedResponse(
          Stream<List<int>>.error(bodyFailure),
          200,
        );
      },
    );

    await expectLater(
      postMultipartToApi<void>(
        url: url,
        client: client,
        build: (request) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'file',
              <int>[1, 2, 3],
              filename: 'fixture.bin',
            ),
          );
        },
        successHandler: (context) async {
          await context.response.stream.drain<void>();
        },
        failureHandler: (_) async => throw StateError('unexpected failure'),
      ),
      throwsA(
        isA<ApiCallError>().having(
          (error) => error.cause,
          'cause',
          same(bodyFailure),
        ),
      ),
    );
    await recorded.finalize().drain<void>();
    expect(
        recorded.headers['content-type'], startsWith('multipart/form-data;'));
    expect(recorded.files.single.filename, 'fixture.bin');
    expect(recorded.files.single.contentType.toString(),
        'application/octet-stream');
  });

  // Compatibility fixture (unit): P1-UTIL-08
  test('P1-UTIL-08 tracks deltas, malformed input, and terminal exactly once',
      () {
    final tracker = StreamingToolCallTracker();
    expect(
      () => tracker.addDelta(index: 0, name: 'lookup'),
      throwsA(isA<InvalidResponseDataError>()),
    );

    final start = tracker.addDelta(
      index: 0,
      id: 'call-1',
      name: 'lookup',
      argumentsDelta: '{"query":',
    );
    expect(start.whereType<ToolInputStart>(), hasLength(1));
    expect(start.whereType<ToolInputEnd>(), isEmpty);

    final malformedTerminal = tracker.finishAll();
    expect(malformedTerminal.whereType<ToolInputEnd>(), hasLength(1));
    expect(malformedTerminal.whereType<ToolCall>(), hasLength(1));
    expect((malformedTerminal.last as ToolCall).input, '{"query":');
    expect(tracker.finishAll(), isEmpty);
  });
}
