import 'dart:convert';

import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('anthropicErrorValidator', () {
    test('accepts a standard Anthropic error body', () {
      final result = anthropicErrorValidator.validate(<String, Object?>{
        'type': 'error',
        'error': <String, Object?>{
          'type': 'overloaded_error',
          'message': 'Overloaded',
        },
      });
      expect(result, isA<ValidationSuccess>());
    });

    test('accepts extra keys inside the error object (details: null)', () {
      // 上游 zod v4 默认 strip 未知键(校验通过、value 中剥除);pigcode 的
      // JsonSchemaValidator 不删键、原值透传——差异仅在 data 保留形态,
      // 校验通过性一致(报告 06 §1.1)。
      final result = anthropicErrorValidator.validate(<String, Object?>{
        'type': 'error',
        'error': <String, Object?>{
          'type': 'overloaded_error',
          'message': 'Overloaded',
          'details': null,
        },
      });
      expect(result, isA<ValidationSuccess>());
    });

    test('rejects a body missing error.message', () {
      final result = anthropicErrorValidator.validate(<String, Object?>{
        'type': 'error',
        'error': <String, Object?>{'type': 'overloaded_error'},
      });
      expect(result, isA<ValidationFailure>());
    });

    test("rejects a body whose top-level type is not the literal 'error'", () {
      final result = anthropicErrorValidator.validate(<String, Object?>{
        'type': 'not_error',
        'error': <String, Object?>{
          'type': 'overloaded_error',
          'message': 'Overloaded',
        },
      });
      expect(result, isA<ValidationFailure>());
    });

    test('rejects a body missing the error envelope entirely', () {
      final result = anthropicErrorValidator.validate(<String, Object?>{
        'message': 'no envelope',
      });
      expect(result, isA<ValidationFailure>());
    });
  });

  group('anthropicErrorToMessage', () {
    test('extracts error.message only (does not append error.type)', () {
      final message = anthropicErrorToMessage(<String, Object?>{
        'type': 'error',
        'error': <String, Object?>{
          'type': 'overloaded_error',
          'message': 'Overloaded',
        },
      });
      expect(message, 'Overloaded');
    });
  });

  group('anthropicFailedResponseHandler', () {
    test('parses a well-formed 429 error body into a retryable ApiCallError',
        () async {
      final handler = anthropicFailedResponseHandler();
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'type': 'error',
              'error': <String, Object?>{
                'type': 'rate_limit_error',
                'message': 'rate limited',
              },
            }),
          ),
        ),
        429,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://api.anthropic.com/v1/messages'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error, isA<ApiCallError>());
      expect(error.message, 'rate limited');
      expect(error.statusCode, 429);
      // 契约默认可重试状态码:408/409/429/≥500。
      expect(error.isRetryable, isTrue);
    });

    test('a malformed (non-JSON) error body falls back to reasonPhrase',
        () async {
      final handler = anthropicFailedResponseHandler();
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('not json at all')),
        500,
        reasonPhrase: 'Internal Server Error',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://api.anthropic.com/v1/messages'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'Internal Server Error');
      expect(error.statusCode, 500);
      expect(error.data, isNull);
      expect(error.isRetryable, isTrue); // 5xx 默认可重试。
    });

    test('a 401 response with a valid error body is not retryable', () async {
      final handler = anthropicFailedResponseHandler();
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'type': 'error',
              'error': <String, Object?>{
                'type': 'authentication_error',
                'message': 'invalid x-api-key',
              },
            }),
          ),
        ),
        401,
        reasonPhrase: 'Unauthorized',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://api.anthropic.com/v1/messages'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'invalid x-api-key');
      expect(error.statusCode, 401);
      expect(error.isRetryable, isFalse);
    });

    test(
        'a body that is valid JSON but fails schema validation falls back '
        'to reasonPhrase', () async {
      final handler = anthropicFailedResponseHandler();
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(jsonEncode(<String, Object?>{'unexpected': true})),
        ),
        400,
        reasonPhrase: 'Bad Request',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://api.anthropic.com/v1/messages'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'Bad Request');
      expect(error.statusCode, 400);
      expect(error.data, isNull);
      expect(error.isRetryable, isFalse); // 400 默认不可重试。
    });

    test('a 529 overloaded response is retryable (status-code based only)',
        () async {
      // 重试判定只看状态码(≥500),不看 error.type(报告 06 §1.4 末句)。
      final handler = anthropicFailedResponseHandler();
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'type': 'error',
              'error': <String, Object?>{
                'type': 'overloaded_error',
                'message': 'Overloaded',
              },
            }),
          ),
        ),
        529,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://api.anthropic.com/v1/messages'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'Overloaded');
      expect(error.statusCode, 529);
      expect(error.isRetryable, isTrue);
    });
  });
}
