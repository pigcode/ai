import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/fake_http_client.dart';

http.StreamedResponse _streamedResponse(String body, {int statusCode = 200}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
  );
}

void main() {
  group('jsonResponseHandler', () {
    test('decodes a well-formed JSON body', () async {
      final handler = jsonResponseHandler<String>(
        decode: (json) => (json as JsonObject)['name']! as String,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: <String, Object?>{},
        response: _streamedResponse('{"name":"ada"}'),
      );

      final result = await handler(ctx);

      expect(result, 'ada');
    });

    test('throws EmptyResponseBodyError on empty body', () async {
      final handler = jsonResponseHandler<String>(
        decode: (json) => (json as JsonObject)['name']! as String,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: _streamedResponse('   '),
      );

      await expectLater(
        () => handler(ctx),
        throwsA(isA<EmptyResponseBodyError>()),
      );
    });

    test('throws JsonParseError on malformed JSON body', () async {
      final handler = jsonResponseHandler<String>(
        decode: (json) => (json as JsonObject)['name']! as String,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: _streamedResponse('{not-json'),
      );

      await expectLater(
        () => handler(ctx),
        throwsA(isA<JsonParseError>()),
      );
    });

    test('throws TypeValidationError when schema validation fails', () async {
      final validator = JsonSchemaValidator.fromContract(
        const JsonSchema(<String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'name': <String, Object?>{'type': 'string'},
          },
          'required': <Object?>['name'],
        }),
      );
      final handler = jsonResponseHandler<String>(
        validator: validator,
        decode: (json) => (json as JsonObject)['name']! as String,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: _streamedResponse('{"age":30}'),
      );

      await expectLater(
        () => handler(ctx),
        throwsA(isA<TypeValidationError>()),
      );
    });
  });

  group('jsonErrorResponseHandler', () {
    test('empty body falls back to reasonPhrase, default isRetryable',
        () async {
      final handler = jsonErrorResponseHandler(
        errorToMessage: (json) => (json as JsonObject)['message']! as String,
      );
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('   ')),
        429,
        reasonPhrase: 'Too Many Requests',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'Too Many Requests');
      expect(error.statusCode, 429);
      expect(error.data, isNull);
      expect(error.isRetryable, isTrue); // 契约默认对 429 推断为 true
    });

    test('malformed error body falls back to reasonPhrase', () async {
      final handler = jsonErrorResponseHandler(
        errorToMessage: (json) => (json as JsonObject)['message']! as String,
      );
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('{not-json')),
        400,
        reasonPhrase: 'Bad Request',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'Bad Request');
      expect(error.statusCode, 400);
      expect(error.data, isNull);
      expect(error.isRetryable, isFalse); // 契约默认对 400 推断为 false
    });

    test('null reasonPhrase falls back to HTTP <statusCode> message', () async {
      final handler = jsonErrorResponseHandler(
        errorToMessage: (json) => (json as JsonObject)['message']! as String,
      );
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('')),
        500,
        // 不设 reasonPhrase(HTTP/2 下常见):message 兜底为 'HTTP 500'。
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'HTTP 500');
      expect(error.statusCode, 500);
      expect(error.isRetryable, isTrue); // 契约默认对 5xx 推断为 true
    });

    test(
        'errorToMessage throwing on an unexpected error envelope falls back '
        'to the ApiCallError with full HTTP context (no raw exception)',
        () async {
      final handler = jsonErrorResponseHandler(
        // 预期 {"message": "..."} 信封;实际错误体形状不同 → cast/null 抛出。
        errorToMessage: (json) => (json as JsonObject)['message']! as String,
      );
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('{"unexpected":{"shape":true}}')),
        502,
        reasonPhrase: 'Bad Gateway',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      // 提取失败与其他畸形错误体同等对待:保留原始 HTTP 上下文的兜底
      // ApiCallError,而非让 cast/null 异常裸传播。
      expect(error.message, 'Bad Gateway');
      expect(error.statusCode, 502);
      expect(error.data, isNull);
      expect(error.isRetryable, isTrue); // 契约默认对 502 推断为 true
    });

    test('parses error body and calls errorToMessage on success', () async {
      final handler = jsonErrorResponseHandler(
        errorToMessage: (json) => (json as JsonObject)['message']! as String,
      );
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('{"message":"invalid api key"}')),
        401,
        reasonPhrase: 'Unauthorized',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'invalid api key');
      expect(error.statusCode, 401);
      expect(error.data, <String, Object?>{'message': 'invalid api key'});
    });

    test(
        'a body stream error while reading the error body falls back to the '
        'ApiCallError with known HTTP context (no raw exception)', () async {
      final handler = jsonErrorResponseHandler(
        errorToMessage: (json) => (json as JsonObject)['message']! as String,
      );
      final response = http.StreamedResponse(
        // 对端发出 429 状态头后中途重置连接:body 读取抛错、不可得。
        Stream<List<int>>.error(StateError('connection reset mid-body')),
        429,
        reasonPhrase: 'Too Many Requests',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      // 已知的 HTTP 上下文(status/message/可重试性)完整保留,读取异常
      // 不裸传播。
      expect(error.message, 'Too Many Requests');
      expect(error.statusCode, 429);
      expect(error.responseBody, '');
      expect(error.isRetryable, isTrue); // 契约默认对 429 推断为 true
    });

    test(
        'a RequestAbortedException while reading the error body propagates '
        'unwrapped (cancellation is not converted to ApiCallError)', () async {
      final handler = jsonErrorResponseHandler(
        errorToMessage: (json) => (json as JsonObject)['message']! as String,
      );
      final response = http.StreamedResponse(
        // headers 到达后取消:取消异常出现在 body 流的消费过程中。
        Stream<List<int>>.error(
          http.RequestAbortedException(Uri.parse('https://example.com')),
        ),
        429,
        reasonPhrase: 'Too Many Requests',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: response,
      );

      await expectLater(
        () => handler(ctx),
        throwsA(isA<http.RequestAbortedException>()),
      );
    });

    test('isRetryable callback overrides default inference (true)', () async {
      final handler = jsonErrorResponseHandler(
        errorToMessage: (json) => (json as JsonObject)['message']! as String,
        isRetryable: (response, parsedError) => true,
      );
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('{"message":"bad request but retry"}')),
        400,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.isRetryable, isTrue);
    });

    test('isRetryable callback overrides default inference (false)', () async {
      final handler = jsonErrorResponseHandler(
        errorToMessage: (json) => (json as JsonObject)['message']! as String,
        isRetryable: (response, parsedError) => false,
      );
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('{"message":"server error but no retry"}')),
        500,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.isRetryable, isFalse);
    });

    test(
        'non-UTF-8 error body (invalid continuation byte) falls back '
        'without throwing FormatException', () async {
      // 回归测试：错误体可能是二进制/传统编码的代理错误页，不能因为严格
      // UTF-8 解码抛出 FormatException 而丢失原始 HTTP 失败上下文。
      final handler = jsonErrorResponseHandler(
        errorToMessage: (json) => (json as JsonObject)['message']! as String,
      );
      final response = http.StreamedResponse(
        Stream.value(<int>[0xC3, 0x28]),
        502,
        reasonPhrase: 'Bad Gateway',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.statusCode, 502);
      expect(error.message, 'Bad Gateway');
      expect(error.isRetryable, isTrue); // 契约默认对 502 推断为 true
    });

    test(
        'non-UTF-8 error body (BOM-like invalid bytes) falls back without '
        'throwing FormatException', () async {
      final handler = jsonErrorResponseHandler(
        errorToMessage: (json) => (json as JsonObject)['message']! as String,
      );
      final response = http.StreamedResponse(
        Stream.value(<int>[0xFF, 0xFE]),
        502,
        // 无 reasonPhrase：message 兜底为 'HTTP 502'。
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.statusCode, 502);
      expect(error.message, 'HTTP 502');
      expect(error.isRetryable, isTrue);
    });
  });

  group('eventSourceResponseHandler', () {
    test(
        'an empty source stream yields a stream that errors with '
        'EmptyResponseBodyError when consumed', () async {
      final handler = eventSourceResponseHandler<String>(
        decode: (json) => (json as JsonObject)['text']! as String,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: http.StreamedResponse(const Stream<List<int>>.empty(), 200),
      );

      final stream = await handler(ctx);

      await expectLater(
        stream.toList(),
        throwsA(isA<EmptyResponseBodyError>()),
      );
    });

    test('decodes well-formed frames into ParseSuccess', () async {
      final handler = eventSourceResponseHandler<String>(
        decode: (json) => (json as JsonObject)['text']! as String,
      );
      final sseBody = 'data: {"text":"hello"}\n\n'
          'data: {"text":"world"}\n\n';
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: http.StreamedResponse(
          Stream.value(utf8.encode(sseBody)),
          200,
        ),
      );

      final stream = await handler(ctx);
      final results = await stream.toList();

      expect(results, hasLength(2));
      expect((results[0] as ParseSuccess<String>).value, 'hello');
      expect((results[1] as ParseSuccess<String>).value, 'world');
    });

    test('a malformed frame becomes ParseFailure and stream continues',
        () async {
      final handler = eventSourceResponseHandler<String>(
        decode: (json) => (json as JsonObject)['text']! as String,
      );
      final sseBody = 'data: {not-json}\n\n'
          'data: {"text":"world"}\n\n';
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: http.StreamedResponse(
          Stream.value(utf8.encode(sseBody)),
          200,
        ),
      );

      final stream = await handler(ctx);
      final results = await stream.toList();

      expect(results, hasLength(2));
      expect(results[0], isA<ParseFailure<String>>());
      expect((results[1] as ParseSuccess<String>).value, 'world');
    });

    test('decode throwing turns the frame into ParseFailure and continues',
        () async {
      final handler = eventSourceResponseHandler<String>(
        decode: (json) {
          final map = json as JsonObject;
          if (!map.containsKey('text')) {
            throw TypeValidationError(value: json);
          }
          return map['text']! as String;
        },
      );
      final sseBody = 'data: {"missing":"field"}\n\n'
          'data: {"text":"world"}\n\n';
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: http.StreamedResponse(
          Stream.value(utf8.encode(sseBody)),
          200,
        ),
      );

      final stream = await handler(ctx);
      final results = await stream.toList();

      expect(results, hasLength(2));
      expect(results[0], isA<ParseFailure<String>>());
      expect(
        (results[0] as ParseFailure<String>).error,
        isA<TypeValidationError>(),
      );
      expect((results[1] as ParseSuccess<String>).value, 'world');
    });

    test(
        'a source stream error before any bytes surfaces as the original '
        'error on the returned stream, not EmptyResponseBodyError', () async {
      final handler = eventSourceResponseHandler<String>(
        decode: (json) => (json as JsonObject)['text']! as String,
      );
      final sourceError = StateError('connection reset');
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: http.StreamedResponse(
          Stream<List<int>>.error(sourceError),
          200,
        ),
      );

      final stream = await handler(ctx);

      await expectLater(
        stream.toList(),
        throwsA(same(sourceError)),
      );
    });

    test(
        'a source error before any bytes yields exactly one stream error '
        '(no trailing EmptyResponseBodyError for non-cancelling consumers)',
        () async {
      final handler = eventSourceResponseHandler<String>(
        decode: (json) => (json as JsonObject)['text']! as String,
      );
      final sourceError = StateError('connection reset');
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: http.StreamedResponse(
          // Stream.error 的标准形态:先 error 后 close。
          Stream<List<int>>.error(sourceError),
          200,
        ),
      );

      final stream = await handler(ctx);

      // 不随首个 error 取消的消费者(如把流错误转终端 ErrorPart 的 provider
      // 层)必须只看到一个错误:onDone 不得再补发 EmptyResponseBodyError。
      final errors = <Object>[];
      final done = Completer<void>();
      stream.listen(
        (_) {},
        onError: errors.add,
        onDone: done.complete,
        cancelOnError: false,
      );
      await done.future;

      expect(errors, hasLength(1));
      expect(errors.single, same(sourceError));
    });

    test(
        'empty List<int> chunks do not count as body bytes: a zero-byte '
        'response still surfaces EmptyResponseBodyError', () async {
      final handler = eventSourceResponseHandler<String>(
        decode: (json) => (json as JsonObject)['text']! as String,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: http.StreamedResponse(
          // 部分 client/代理会发空块;body 实际零字节,仍应判空。
          Stream.fromIterable(<List<int>>[<int>[], <int>[]]),
          200,
        ),
      );

      final stream = await handler(ctx);

      await expectLater(
        stream.toList(),
        throwsA(isA<EmptyResponseBodyError>()),
      );
    });

    test(
        'the handler future resolves immediately without waiting for the '
        'source stream to emit data, and the returned stream remains '
        'cancellable', () async {
      // 回归测试：round-5 修复移除了首块探测 completer——handler 不应再
      // 阻塞在“首字节是否到达”上。构造一个订阅后不 add 任何数据、也不
      // close 的源流（模拟迟迟不发数据的长连接），验证 handler(ctx) 在
      // 短 timeout 内 resolve；再验证拿到流后取消订阅会传导到上游 cancel。
      late final StreamController<List<int>> sourceController;
      var sourceCancelled = false;
      sourceController = StreamController<List<int>>(
        onCancel: () {
          sourceCancelled = true;
        },
      );
      addTearDown(() {
        if (!sourceController.isClosed) {
          unawaited(sourceController.close());
        }
      });

      final handler = eventSourceResponseHandler<String>(
        decode: (json) => (json as JsonObject)['text']! as String,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: http.StreamedResponse(sourceController.stream, 200),
      );

      final stream = await handler(ctx).timeout(const Duration(seconds: 2));
      final subscription = stream.listen((_) {});
      await subscription.cancel();
      // 给 onCancel 回调一次事件循环的机会完成。
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(sourceCancelled, isTrue);
    });

    test(
        'cancelling the returned stream propagates cancellation to the '
        'upstream byte stream', () async {
      final handler = eventSourceResponseHandler<String>(
        decode: (json) => (json as JsonObject)['text']! as String,
      );
      final upstream = ObservableByteStream([
        utf8.encode('data: {"text":"a"}\n\n'),
        utf8.encode('data: {"text":"b"}\n\n'),
        utf8.encode('data: {"text":"c"}\n\n'),
      ]);
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: http.StreamedResponse(upstream.stream, 200),
      );

      final stream = await handler(ctx);
      final received = <ParseResult<String>>[];
      final subscription = stream.listen(received.add);
      // 消费到至少一帧后再取消,验证取消经由 controller.onCancel 传导到
      // 上游订阅(而不仅仅是脱离下游 controller.stream)。
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await subscription.cancel();
      // 给 onCancel 回调一次事件循环的机会完成。
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(upstream.wasCancelled, isTrue);
    });

    test(
        'a synchronously-dispatching source stream (chunk emitted and '
        'closed inside onListen) is fully consumed without dropping the '
        'first chunk', () async {
      // 回归测试：round-1 修复后 probe 订阅曾是 `listen(null)` 后再用级联
      // `..onData(...)..onError(...)..onDone(...)` 事后装 handler；若源流
      // 在订阅 setup 期间（`onListen` 回调内）就同步 `add` 首块甚至随即
      // `close`，级联赋值完成之前发出的块/done 会被空 handler 吞掉，导致
      // 首块丢失、probe 挂起或误报空 body。这里构造一个 `sync: true` 的
      // `StreamController`，在 `onListen` 里同步吐出完整 SSE 帧后立即
      // `close`，验证修复后事件不丢、流可完整消费。
      late final StreamController<List<int>> sourceController;
      sourceController = StreamController<List<int>>(
        sync: true,
        onListen: () {
          final sseBody = 'data: {"text":"hello"}\n\n'
              'data: {"text":"world"}\n\n';
          sourceController.add(utf8.encode(sseBody));
          sourceController.close();
        },
      );

      final handler = eventSourceResponseHandler<String>(
        decode: (json) => (json as JsonObject)['text']! as String,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat'),
        requestBody: null,
        response: http.StreamedResponse(sourceController.stream, 200),
      );

      final stream = await handler(ctx).timeout(const Duration(seconds: 2));
      final results = await stream.toList().timeout(const Duration(seconds: 2));

      expect(results, hasLength(2));
      expect((results[0] as ParseSuccess<String>).value, 'hello');
      expect((results[1] as ParseSuccess<String>).value, 'world');
    });
  });
}
