// Compatibility fixture (unit): P1-CROSS-01
// Compatibility fixture (unit): P1-CROSS-02
import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('cross-package provider metadata stays typed', () {
    const ProviderMetadata metadata = <String, JsonObject>{
      'portable': <String, Object?>{'traceId': 'provider-utils'},
    };
    const Headers headers = <String, String>{'x-trace-id': 'provider-utils'};
    expect(metadata['portable']?['traceId'], 'provider-utils');
    expect(headers['x-trace-id'], 'provider-utils');
  });

  test('provider reference helpers are exported', () {
    expect(
      resolveProviderReference(
        reference: const {'openai': 'file-1'},
        provider: 'openai',
      ),
      'file-1',
    );
  });

  test('json.dart symbols are exported', () {
    final success = safeParseJson('{"a":1}');
    expect(success, isA<ParseSuccess<JsonValue>>());

    final validator = JsonSchemaValidator.fromContract(
      const JsonSchema(<String, Object?>{'type': 'object'}),
    );
    expect(validator.validate(<String, Object?>{}), isA<ValidationSuccess>());

    expect(parseJson('{}'), isA<JsonObject>());
    expect(
      validateTypes(<String, Object?>{}, validator),
      isA<JsonObject>(),
    );
    expect(
      safeValidateTypes(<String, Object?>{}, validator),
      isA<ValidationSuccess>(),
    );
  });

  test('sse.dart symbols are exported', () async {
    const event = ServerSentEvent(data: 'hello');
    expect(event.data, 'hello');

    final transformer = sseTransformer();
    expect(transformer, isA<StreamTransformer<List<int>, ServerSentEvent>>());

    final stream = parseJsonEventStream(
      Stream.value(utf8.encode('data: {"a":1}\n\n')),
    );
    final results = await stream.toList();
    expect(results, hasLength(1));
  });

  test('http.dart symbols are exported', () async {
    final headers = combineHeaders(<Map<String, String?>?>[
      <String, String?>{'a': '1'},
      <String, String?>{'b': '2'},
    ]);
    expect(headers, <String, String>{'a': '1', 'b': '2'});

    final ctx = ResponseContext(
      url: Uri.parse('https://example.com'),
      requestBody: null,
      response: http.StreamedResponse(const Stream<List<int>>.empty(), 200),
    );
    expect(ctx.url, Uri.parse('https://example.com'));

    final mapped = mapTransportError(
      Exception('boom'),
      url: Uri.parse('https://example.com'),
    );
    expect(mapped, isA<ApiCallError>());
    expect(mapped.isRetryable, isTrue);
  });

  test('multipart.dart symbols are exported', () {
    expect(
      fileDataToBytes(const FileDataText('x'), argument: 'data'),
      [120],
    );
  });

  test('response_handler.dart symbols are exported', () {
    final successHandler = jsonResponseHandler<JsonValue>(decode: (j) => j);
    expect(successHandler, isA<ResponseHandler<JsonValue>>());

    final failureHandler = jsonErrorResponseHandler(
      errorToMessage: (json) => 'error',
    );
    expect(failureHandler, isA<FailedResponseHandler>());

    final sseHandler = eventSourceResponseHandler<JsonValue>(decode: (j) => j);
    expect(
      sseHandler,
      isA<ResponseHandler<Stream<ParseResult<JsonValue>>>>(),
    );
  });

  test('streaming_tool_call.dart symbols are exported', () {
    final tracker = StreamingToolCallTracker();
    final started = tracker.addDelta(index: 0, id: 'call_1', name: 'search');
    expect(started, contains(isA<ToolInputStart>()));

    final completed =
        tracker.addDelta(index: 0, argumentsDelta: '{"q":"dart"}');
    expect(completed, contains(isA<ToolInputEnd>()));
    expect(completed, contains(isA<ToolCall>()));

    expect(tracker.finishAll(), isEmpty);
  });

  test('ids.dart symbols are exported', () {
    expect(generateId(), hasLength(16));
    final generator = createIdGenerator(prefix: 'msg');
    expect(generator(), startsWith('msg-'));
  });

  test('settings.dart symbols are exported', () {
    expect(withoutTrailingSlash('https://a.com/'), 'https://a.com');
    expect(loadApiKey(apiKey: 'k', settingName: 'K'), 'k');
    expect(loadSetting(settingValue: 'v', settingName: 'V'), 'v');
    expect(loadOptionalSetting(), isNull);
  });

  test('async.dart symbols are exported', () async {
    await delayCancellable(const Duration(milliseconds: 1));
  });
}
