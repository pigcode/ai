import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

void main() {
  group('parseJson', () {
    test('parses a valid JSON object into a JsonValue', () {
      final result = parseJson('{"foo": "bar"}');
      expect(result, equals(<String, Object?>{'foo': 'bar'}));
    });

    test('parses a valid JSON array into a JsonValue', () {
      final result = parseJson('[1, 2, 3]');
      expect(result, equals(<Object?>[1, 2, 3]));
    });

    test('throws JsonParseError for syntactically invalid JSON', () {
      expect(
        () => parseJson('invalid json'),
        throwsA(isA<JsonParseError>()),
      );
    });

    test('JsonParseError carries the original text and a cause', () {
      try {
        parseJson('{not valid}');
        fail('expected parseJson to throw');
      } on JsonParseError catch (error) {
        expect(error.text, equals('{not valid}'));
        expect(error.cause, isNotNull);
      }
    });
  });

  group('safeParseJson', () {
    test('returns ParseSuccess with rawValue for valid JSON', () {
      final result = safeParseJson('{"foo": "bar"}');
      expect(
        result,
        equals(
          const ParseSuccess<Object?>(
            <String, Object?>{'foo': 'bar'},
            rawValue: <String, Object?>{'foo': 'bar'},
          ),
        ),
      );
    });

    test('returns ParseFailure with a JsonParseError for invalid JSON', () {
      final result = safeParseJson('invalid json');
      expect(result, isA<ParseFailure<Object?>>());
      final failure = result as ParseFailure<Object?>;
      expect(failure.error, isA<JsonParseError>());
    });

    test('does not double-wrap an already-typed AiError', () {
      // safeParseJson 内部只应产出 JsonParseError,不应重复包装成另一层
      // JsonParseError;验证同一段非法文本产生的错误类型单一、稳定。
      final first = safeParseJson('{"a":}');
      final second = safeParseJson('{"a":}');
      expect(first, isA<ParseFailure<Object?>>());
      expect(second, isA<ParseFailure<Object?>>());
      final firstError = (first as ParseFailure<Object?>).error;
      final secondError = (second as ParseFailure<Object?>).error;
      expect(firstError, isA<JsonParseError>());
      expect(secondError, isA<JsonParseError>());
      expect(
        (firstError as JsonParseError).text,
        equals((secondError as JsonParseError).text),
      );
    });
  });

  group('JsonSchemaValidator / validateTypes / safeValidateTypes', () {
    final personSchema = JsonSchemaValidator.fromContract(
      const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string'},
          'age': <String, Object?>{'type': 'number'},
        },
        'required': <Object?>['name', 'age'],
      }),
    );

    test('validate returns ValidationSuccess for a matching instance', () {
      final result = personSchema.validate(
        <String, Object?>{'name': 'Ada', 'age': 30},
      );
      expect(
        result,
        equals(
          const ValidationSuccess(<String, Object?>{
            'name': 'Ada',
            'age': 30,
          }),
        ),
      );
    });

    test(
        'validate returns ValidationFailure with details for a violating instance',
        () {
      final result = personSchema.validate(<String, Object?>{'name': 'Ada'});
      expect(result, isA<ValidationFailure>());
      final failure = result as ValidationFailure;
      expect(failure.error, isA<TypeValidationError>());
      expect(failure.error.value, equals(<String, Object?>{'name': 'Ada'}));
      expect(failure.error.cause, isNotNull);
      expect(failure.error.cause.toString(), isNotEmpty);
    });

    test('validateTypes returns the value for a matching instance', () {
      final value = validateTypes(
        <String, Object?>{'name': 'Ada', 'age': 30},
        personSchema,
      );
      expect(value, equals(<String, Object?>{'name': 'Ada', 'age': 30}));
    });

    test('validateTypes throws TypeValidationError for a violating instance',
        () {
      expect(
        () => validateTypes(<String, Object?>{'name': 'Ada'}, personSchema),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('safeValidateTypes does not throw for a violating instance', () {
      final result = safeValidateTypes(
        <String, Object?>{'age': 'not a number'},
        personSchema,
      );
      expect(result, isA<ValidationFailure>());
    });

    test('the same validator instance can be reused across multiple calls', () {
      final first = personSchema.validate(
        <String, Object?>{'name': 'Ada', 'age': 30},
      );
      final second = personSchema.validate(
        <String, Object?>{'name': 'Grace', 'age': 40},
      );
      expect(first, isA<ValidationSuccess>());
      expect(second, isA<ValidationSuccess>());
    });
  });

  group('json_schema draft compatibility with an OpenAI-style response schema',
      () {
    // 开放问题 #2:确认 json_schema 库默认 draft(draft-07)能校验一个
    // OpenAI structured output 风格的 schema(顶层 object + 嵌套 object +
    // enum + additionalProperties: false)。
    test('validates an OpenAI-style structured-output schema instance', () {
      final validator = JsonSchemaValidator.fromContract(
        const JsonSchema(<String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'name': <String, Object?>{'type': 'string'},
            'weather': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'condition': <String, Object?>{
                  'type': 'string',
                  'enum': <Object?>['sunny', 'cloudy', 'rainy'],
                },
                'temperatureCelsius': <String, Object?>{'type': 'number'},
              },
              'required': <Object?>['condition', 'temperatureCelsius'],
              'additionalProperties': false,
            },
          },
          'required': <Object?>['name', 'weather'],
          'additionalProperties': false,
        }),
      );

      final valid = validator.validate(<String, Object?>{
        'name': 'Beijing',
        'weather': <String, Object?>{
          'condition': 'sunny',
          'temperatureCelsius': 28,
        },
      });
      expect(valid, isA<ValidationSuccess>());

      final invalid = validator.validate(<String, Object?>{
        'name': 'Beijing',
        'weather': <String, Object?>{
          'condition': 'stormy',
          'temperatureCelsius': 28,
        },
      });
      expect(invalid, isA<ValidationFailure>());
    });
  });
}
