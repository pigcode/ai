import 'dart:convert';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('openAiErrorValidator', () {
    test('accepts a valid error body with only message', () {
      final result = openAiErrorValidator.validate(<String, Object?>{
        'error': <String, Object?>{'message': 'invalid api key'},
      });
      expect(result, isA<ValidationSuccess>());
    });

    test('accepts a valid error body with all optional fields', () {
      final result = openAiErrorValidator.validate(<String, Object?>{
        'error': <String, Object?>{
          'message': 'rate limited',
          'type': 'rate_limit_error',
          'param': null,
          'code': 'rate_limit_exceeded',
        },
      });
      expect(result, isA<ValidationSuccess>());
    });

    test('accepts numeric code (code is string | number in raw schema)', () {
      final result = openAiErrorValidator.validate(<String, Object?>{
        'error': <String, Object?>{'message': 'oops', 'code': 500},
      });
      expect(result, isA<ValidationSuccess>());
    });

    test('rejects a body missing error.message', () {
      final result = openAiErrorValidator.validate(<String, Object?>{
        'error': <String, Object?>{'type': 'server_error'},
      });
      expect(result, isA<ValidationFailure>());
    });

    test('rejects a body missing the error envelope entirely', () {
      final result = openAiErrorValidator.validate(<String, Object?>{
        'message': 'no envelope',
      });
      expect(result, isA<ValidationFailure>());
    });
  });

  group('openAiErrorToMessage', () {
    test('extracts error.message and ignores other fields', () {
      final message = openAiErrorToMessage(<String, Object?>{
        'error': <String, Object?>{
          'message': 'invalid api key',
          'type': 'invalid_request_error',
          'code': 'invalid_api_key',
        },
      });
      expect(message, 'invalid api key');
    });
  });

  group('openAiFailedResponseHandler', () {
    test('parses a well-formed OpenAI error body into ApiCallError', () async {
      final handler = openAiFailedResponseHandler();
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'message': 'invalid api key',
                'type': 'invalid_request_error',
                'code': 'invalid_api_key',
              },
            }),
          ),
        ),
        401,
        reasonPhrase: 'Unauthorized',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error, isA<ApiCallError>());
      expect(error.message, 'invalid api key');
      expect(error.statusCode, 401);
      // 401 不在契约默认可重试状态码集合(408/409/429/5xx)内。
      expect(error.isRetryable, isFalse);
      expect(
        error.data,
        <String, Object?>{
          'error': <String, Object?>{
            'message': 'invalid api key',
            'type': 'invalid_request_error',
            'code': 'invalid_api_key',
          },
        },
      );
    });

    test('a malformed (non-JSON) error body falls back to reasonPhrase',
        () async {
      final handler = openAiFailedResponseHandler();
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('not json at all')),
        500,
        reasonPhrase: 'Internal Server Error',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'Internal Server Error');
      expect(error.statusCode, 500);
      expect(error.data, isNull);
      expect(error.isRetryable, isTrue); // 5xx 默认可重试。
    });

    test(
        'a body that is valid JSON but fails schema validation falls back '
        'to reasonPhrase', () async {
      final handler = openAiFailedResponseHandler();
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(jsonEncode(<String, Object?>{'unexpected': true})),
        ),
        400,
        reasonPhrase: 'Bad Request',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'Bad Request');
      expect(error.statusCode, 400);
      expect(error.data, isNull);
      expect(error.isRetryable, isFalse); // 400 默认不可重试。
    });

    test('a 429 response defaults isRetryable to true (no custom override)',
        () async {
      final handler = openAiFailedResponseHandler();
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{'message': 'rate limited'},
            }),
          ),
        ),
        429,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.isRetryable, isTrue);
    });
  });
}
