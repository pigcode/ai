import 'dart:convert';

import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('defaultOpenAiCompatibleErrorStructure.validator', () {
    test('accepts a valid error body with only message', () {
      final result = defaultOpenAiCompatibleErrorStructure.validator.validate(
        <String, Object?>{
          'error': <String, Object?>{'message': 'invalid api key'},
        },
      );
      expect(result, isA<ValidationSuccess>());
    });

    test('accepts a valid error body with all optional fields', () {
      final result = defaultOpenAiCompatibleErrorStructure.validator.validate(
        <String, Object?>{
          'error': <String, Object?>{
            'message': 'rate limited',
            'type': 'rate_limit_error',
            'param': null,
            'code': 'rate_limit_exceeded',
          },
        },
      );
      expect(result, isA<ValidationSuccess>());
    });

    test('accepts numeric code (code is string | number in raw schema)', () {
      final result = defaultOpenAiCompatibleErrorStructure.validator.validate(
        <String, Object?>{
          'error': <String, Object?>{'message': 'oops', 'code': 500},
        },
      );
      expect(result, isA<ValidationSuccess>());
    });

    test('rejects a body missing error.message', () {
      final result = defaultOpenAiCompatibleErrorStructure.validator.validate(
        <String, Object?>{
          'error': <String, Object?>{'type': 'server_error'},
        },
      );
      expect(result, isA<ValidationFailure>());
    });

    test('rejects a body missing the error envelope entirely', () {
      final result = defaultOpenAiCompatibleErrorStructure.validator.validate(
        <String, Object?>{'message': 'no envelope'},
      );
      expect(result, isA<ValidationFailure>());
    });
  });

  group('defaultOpenAiCompatibleErrorStructure.errorToMessage', () {
    test('extracts error.message and ignores other fields', () {
      final message = defaultOpenAiCompatibleErrorStructure.errorToMessage(
        <String, Object?>{
          'error': <String, Object?>{
            'message': 'invalid api key',
            'type': 'invalid_request_error',
            'code': 'invalid_api_key',
          },
        },
      );
      expect(message, 'invalid api key');
    });
  });

  group('openAiCompatibleFailedResponseHandler (default structure)', () {
    test('parses a well-formed error body into ApiCallError', () async {
      final handler = openAiCompatibleFailedResponseHandler(
        defaultOpenAiCompatibleErrorStructure,
      );
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
        url: Uri.parse('https://example.com/v1/chat/completions'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error, isA<ApiCallError>());
      expect(error.message, 'invalid api key');
      expect(error.statusCode, 401);
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
      final handler = openAiCompatibleFailedResponseHandler(
        defaultOpenAiCompatibleErrorStructure,
      );
      final response = http.StreamedResponse(
        Stream.value(utf8.encode('not json at all')),
        500,
        reasonPhrase: 'Internal Server Error',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat/completions'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'Internal Server Error');
      expect(error.statusCode, 500);
      expect(error.data, isNull);
      expect(error.isRetryable, isTrue); // 5xx 默认可重试。
    });

    test('a body that fails schema validation falls back to reasonPhrase',
        () async {
      final handler = openAiCompatibleFailedResponseHandler(
        defaultOpenAiCompatibleErrorStructure,
      );
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(jsonEncode(<String, Object?>{'unexpected': true})),
        ),
        400,
        reasonPhrase: 'Bad Request',
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat/completions'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'Bad Request');
      expect(error.statusCode, 400);
      expect(error.data, isNull);
      expect(error.isRetryable, isFalse); // 400 默认不可重试。
    });
  });

  group('openAiCompatibleFailedResponseHandler (custom structure)', () {
    test('custom validator/errorToMessage/isRetryable all take effect',
        () async {
      // 模拟一个私有错误体形状 {message, retry} 的第三方服务。
      final customStructure = ProviderErrorStructure(
        validator: JsonSchemaValidator.fromContract(
          const JsonSchema(<String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'message': <String, Object?>{'type': 'string'},
              'retry': <String, Object?>{'type': 'boolean'},
            },
            'required': <Object?>['message'],
          }),
        ),
        errorToMessage: (JsonValue error) {
          final root = error! as JsonObject;
          return root['message']! as String;
        },
        isRetryable: (http.StreamedResponse response, JsonValue? error) {
          final root = error as JsonObject?;
          return root?['retry'] as bool? ?? false;
        },
      );
      final handler = openAiCompatibleFailedResponseHandler(customStructure);
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'message': 'custom overloaded',
              'retry': true,
            }),
          ),
        ),
        503,
      );
      final ctx = ResponseContext(
        url: Uri.parse('https://example.com/v1/chat/completions'),
        requestBody: null,
        response: response,
      );

      final error = await handler(ctx);

      expect(error.message, 'custom overloaded');
      // isRetryable 回调显式返回 true,覆盖契约默认的按状态码推断。
      expect(error.isRetryable, isTrue);
    });
  });
}
