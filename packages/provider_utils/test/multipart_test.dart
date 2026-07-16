import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/fake_http_client.dart';

void main() {
  group('fileDataToBytes', () {
    test('returns raw bytes', () {
      expect(
        fileDataToBytes(
          FileDataBytes(Uint8List.fromList([1, 2, 3])),
          argument: 'data',
        ),
        [1, 2, 3],
      );
    });

    test('decodes base64 data', () {
      expect(
        fileDataToBytes(const FileDataBase64('AQID'), argument: 'data'),
        [1, 2, 3],
      );
    });

    test('encodes text as UTF-8', () {
      expect(
        fileDataToBytes(const FileDataText('hello'), argument: 'data'),
        utf8.encode('hello'),
      );
    });

    test('rejects URL data', () {
      expect(
        () => fileDataToBytes(
          FileDataUrl(Uri.parse('https://example.test/file')),
          argument: 'data',
        ),
        throwsA(
          isA<InvalidArgumentError>().having(
            (error) => error.argument,
            'argument',
            'data',
          ),
        ),
      );
    });

    test('rejects provider-reference data', () {
      expect(
        () => fileDataToBytes(
          const FileDataReference({'anthropic': 'file_1'}),
          argument: 'data',
        ),
        throwsA(
          isA<InvalidArgumentError>().having(
            (error) => error.argument,
            'argument',
            'data',
          ),
        ),
      );
    });
  });

  group('postMultipartToApi', () {
    final url = Uri.parse('https://api.example.test/v1/files');

    Future<String> decodeBody(ResponseContext context) async {
      final bytes = await context.response.stream.toBytes();
      return utf8.decode(bytes);
    }

    test('sends multipart fields and files and handles a 2xx response',
        () async {
      final fakeClient = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: 'ok',
        ),
      );

      final result = await postMultipartToApi<String>(
        url: url,
        client: fakeClient,
        build: (request) {
          request.headers['Authorization'] = 'Bearer token';
          request.fields['purpose'] = 'test';
          request.files.add(
            http.MultipartFile.fromString('file', 'hello'),
          );
        },
        successHandler: decodeBody,
        failureHandler: (context) async => throw UnimplementedError(),
      );

      expect(result, 'ok');
      expect(fakeClient.recordedRequests, hasLength(1));
      final sent = fakeClient.recordedRequests.single;
      expect(sent.method, 'POST');
      expect(sent.url, url);
      expect(sent.headers['Authorization'], 'Bearer token');
      expect(sent, isA<http.MultipartRequest>());
      final multipart = sent as http.MultipartRequest;
      expect(multipart.fields, {'purpose': 'test'});
      expect(multipart.files, hasLength(1));
      expect(multipart.files.single.field, 'file');
      expect(fakeClient.closed, isFalse);
    });

    test('throws the failure handler result for a non-2xx response', () async {
      final fakeClient = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 400,
          body: 'bad request',
        ),
      );
      final expectedError = ApiCallError(
        message: 'bad request',
        url: url.toString(),
        requestBody: null,
        statusCode: 400,
      );

      await expectLater(
        postMultipartToApi<String>(
          url: url,
          client: fakeClient,
          build: (request) {},
          successHandler: (context) async => throw UnimplementedError(),
          failureHandler: (context) async => expectedError,
        ),
        throwsA(same(expectedError)),
      );
    });

    test('maps transport exceptions to retryable API call errors', () async {
      final fakeClient = FakeHttpClient(
        exceptionToThrow: http.ClientException('offline', url),
      );

      await expectLater(
        postMultipartToApi<String>(
          url: url,
          client: fakeClient,
          build: (request) {},
          successHandler: decodeBody,
          failureHandler: (context) async => throw UnimplementedError(),
        ),
        throwsA(
          isA<ApiCallError>()
              .having((error) => error.isRetryable, 'isRetryable', isTrue)
              .having((error) => error.statusCode, 'statusCode', isNull),
        ),
      );
    });

    test('maps client exceptions while reading a 2xx response body', () async {
      final sourceError = http.ClientException('body interrupted', url);
      final fakeClient = FakeHttpClient(
        responseBuilder: (request) async => http.StreamedResponse(
          Stream<List<int>>.error(sourceError),
          200,
        ),
      );

      await expectLater(
        postMultipartToApi<String>(
          url: url,
          client: fakeClient,
          build: (request) {},
          successHandler: decodeBody,
          failureHandler: (context) async => throw UnimplementedError(),
        ),
        throwsA(
          isA<ApiCallError>()
              .having((error) => error.isRetryable, 'isRetryable', isTrue)
              .having((error) => error.statusCode, 'statusCode', isNull)
              .having((error) => error.cause, 'cause', same(sourceError)),
        ),
      );
    });

    test('maps timeouts while reading a 2xx response body', () async {
      final sourceError = TimeoutException('body timed out');
      final fakeClient = FakeHttpClient(
        responseBuilder: (request) async => http.StreamedResponse(
          Stream<List<int>>.error(sourceError),
          200,
        ),
      );

      await expectLater(
        postMultipartToApi<String>(
          url: url,
          client: fakeClient,
          build: (request) {},
          successHandler: decodeBody,
          failureHandler: (context) async => throw UnimplementedError(),
        ),
        throwsA(
          isA<ApiCallError>()
              .having((error) => error.isRetryable, 'isRetryable', isTrue)
              .having((error) => error.statusCode, 'statusCode', isNull)
              .having((error) => error.cause, 'cause', same(sourceError)),
        ),
      );
    });

    test('propagates cancellation while reading a 2xx response body', () async {
      final sourceError = http.RequestAbortedException(url);
      final fakeClient = FakeHttpClient(
        responseBuilder: (request) async => http.StreamedResponse(
          Stream<List<int>>.error(sourceError),
          200,
        ),
      );

      await expectLater(
        postMultipartToApi<String>(
          url: url,
          client: fakeClient,
          build: (request) {},
          successHandler: decodeBody,
          failureHandler: (context) async => throw UnimplementedError(),
        ),
        throwsA(same(sourceError)),
      );
    });

    test('propagates request cancellation without wrapping it', () async {
      final fakeClient = FakeHttpClient(awaitAbort: true);
      final controller = CancellationController();

      final future = postMultipartToApi<String>(
        url: url,
        client: fakeClient,
        cancellation: controller.signal,
        build: (request) {},
        successHandler: decodeBody,
        failureHandler: (context) async => throw UnimplementedError(),
      );

      controller.cancel();

      await expectLater(
        future,
        throwsA(isA<http.RequestAbortedException>()),
      );
      expect(fakeClient.abortObserved, isTrue);
    });

    test('closes an internally created client after the handler completes',
        () async {
      final ownedClient = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: 'ok',
        ),
      );

      final result = await http.runWithClient(
        () => postMultipartToApi<String>(
          url: url,
          build: (request) {},
          successHandler: decodeBody,
          failureHandler: (context) async => throw UnimplementedError(),
        ),
        () => ownedClient,
      );

      expect(result, 'ok');
      expect(ownedClient.closed, isTrue);
    });
  });
}
