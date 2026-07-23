import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

void main() {
  // Compatibility fixture (scripted-peer): P1-UTIL-01
  // Compatibility fixture (scripted-peer): P1-UTIL-02
  // Compatibility fixture (scripted-peer): P1-UTIL-03
  // Compatibility fixture (scripted-peer): P1-UTIL-04
  // Compatibility fixture (scripted-peer): P1-UTIL-05
  // Compatibility fixture (scripted-peer): P1-UTIL-06
  // Compatibility fixture (scripted-peer): P1-UTIL-07
  // Compatibility fixture (scripted-peer): P1-UTIL-08
  test('public provider utilities exchange all fixtures with a scripted peer',
      () async {
    final peer = _ScriptedProviderUtilsPeer();

    final echoed = await postJsonToApi<JsonObject>(
      url: Uri.parse('https://api.example.test/json'),
      headers: const <String, String>{'User-Agent': 'scripted/1'},
      body: const <String, Object?>{'value': 1},
      client: peer,
      successHandler: (context) async {
        final text = utf8.decode(await context.response.stream.toBytes());
        return parseJson(text) as JsonObject;
      },
      failureHandler: (_) async => throw StateError('unexpected failure'),
    );
    expect(echoed, <String, Object?>{'value': 1});
    final validator = JsonSchemaValidator.fromContract(
      const JsonSchema(<String, Object?>{
        'type': 'object',
        'required': <Object?>['value'],
      }),
    );
    expect(validator.validate(echoed), isA<ValidationSuccess>());
    expect(safeParseJson('{"value":'), isA<ParseFailure<JsonValue>>());

    final streamResponse = await fetchWithValidatedRedirects(
      url: 'https://api.example.test/redirect',
      headers: const <String, String>{
        'Authorization': 'Bearer scripted-secret',
        'Cookie': 'session=scripted',
        'User-Agent': 'scripted/1',
      },
      client: peer,
      credentialedOrigin: 'https://api.example.test',
      trustedOrigin: 'https://api.example.test',
    );
    final parsedEvents = await parseJsonEventStream(streamResponse.stream)
        .where((event) => event is ParseSuccess<JsonValue>)
        .cast<ParseSuccess<JsonValue>>()
        .toList();
    expect(
      parsedEvents.map((event) => event.value),
      <JsonValue>[
        <String, Object?>{'delta': 'hello\nworld'},
      ],
    );
    expect(peer.requests, hasLength(3));
    expect(peer.requests[1].headers['authorization'], 'Bearer scripted-secret');
    expect(peer.requests[1].headers['cookie'], isNull);
    expect(peer.requests[2].headers['authorization'], isNull);
    expect(peer.requests[2].headers['user-agent'], 'scripted/1');

    expect(validateBaseUrl(null), isNull);
    expect(
      () => validateBaseUrl(' '),
      throwsA(isA<InvalidArgumentError>()),
    );
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
      () => validateDownloadUrl('https://example.com/result'),
      returnsNormally,
    );
    expect(
      () => validateDownloadUrl('http://169.254.169.254/metadata'),
      throwsA(isA<DownloadError>()),
    );
    expect(isRedirectStatusCode(302), isTrue);
    expect(isRedirectStatusCode(304), isFalse);

    final timeout = TimeoutException('scripted timeout');
    peer.nextError = timeout;
    await expectLater(
      postJsonToApi<void>(
        url: Uri.parse('https://api.example.test/json'),
        body: null,
        client: peer,
        successHandler: (_) async {},
        failureHandler: (_) async => throw StateError('unexpected failure'),
      ),
      throwsA(
        isA<ApiCallError>().having(
          (error) => error.cause,
          'cause',
          same(timeout),
        ),
      ),
    );

    final cancellation = CancellationController();
    final cancelledRequest = fetchWithValidatedRedirects(
      url: 'https://api.example.test/wait',
      client: peer,
      cancellation: cancellation.signal,
      trustedOrigin: 'https://api.example.test',
    );
    cancellation.cancel(StateError('scripted cancellation'));
    await expectLater(
      cancelledRequest,
      throwsA(isA<http.RequestAbortedException>()),
    );

    final id3ThenMp3 = Uint8List.fromList(
      <int>[0x49, 0x44, 0x33, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xfb],
    );
    expect(
      detectMediaType(data: id3ThenMp3, topLevelType: 'audio'),
      'audio/mpeg',
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

    final multipartResult = await postMultipartToApi<String>(
      url: Uri.parse('https://api.example.test/multipart'),
      client: peer,
      build: (request) {
        request.files.add(
          http.MultipartFile.fromString(
            'file',
            'fixture body',
            filename: 'fixture.txt',
          ),
        );
      },
      successHandler: (context) async =>
          utf8.decode(await context.response.stream.toBytes()),
      failureHandler: (_) async => throw StateError('unexpected failure'),
    );
    expect(multipartResult, 'multipart-ok');
    expect(peer.multipartFilename, 'fixture.txt');
    expect(peer.multipartContentType, startsWith('multipart/form-data;'));

    final tracker = StreamingToolCallTracker();
    final first = tracker.addDelta(
      index: 0,
      id: 'call-1',
      name: 'lookup',
      argumentsDelta: '{"query":',
    );
    final terminal = tracker.addDelta(
      index: 0,
      argumentsDelta: '"dart"}',
    );
    expect(first.whereType<ToolInputStart>(), hasLength(1));
    expect(terminal.whereType<ToolInputEnd>(), hasLength(1));
    expect(terminal.whereType<ToolCall>().single.input, '{"query":"dart"}');
    expect(tracker.finishAll(), isEmpty);
  });
}

final class _ScriptedProviderUtilsPeer extends http.BaseClient {
  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  Object? nextError;
  String? multipartFilename;
  String? multipartContentType;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (nextError case final Object error) {
      nextError = null;
      throw error;
    }

    switch (request.url.path) {
      case '/json':
        final body = request is http.Request ? request.body : '';
        return _response(200, body);
      case '/redirect':
        return _response(
          302,
          '',
          headers: const <String, String>{
            'location': 'https://cdn.example.test/sse',
          },
        );
      case '/sse':
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable(<List<int>>[
            utf8.encode(': comment\r\n'),
            utf8.encode('data: {"delta":"hello'),
            utf8.encode(r'\nworld"}' '\r\nunknown: ignored\r\n\r\n'),
            utf8.encode('data: {"truncated":true}'),
          ]),
          200,
          headers: const <String, String>{
            'content-type': 'text/event-stream',
          },
        );
      case '/wait':
        final abortTrigger = (request as http.Abortable).abortTrigger;
        if (abortTrigger == null) {
          throw StateError('wait request did not carry an abort trigger');
        }
        await abortTrigger;
        throw http.RequestAbortedException(request.url);
      case '/multipart':
        final multipart = request as http.MultipartRequest;
        multipartFilename = multipart.files.single.filename;
        await multipart.finalize().drain<void>();
        multipartContentType = multipart.headers['content-type'];
        return _response(200, 'multipart-ok');
      default:
        return _response(404, 'not-found');
    }
  }

  http.StreamedResponse _response(
    int statusCode,
    String body, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      headers: headers,
    );
  }
}
