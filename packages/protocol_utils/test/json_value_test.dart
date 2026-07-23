import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

void main() {
  group('freezeJsonValue', () {
    test('deep-copies supported JSON values into immutable collections', () {
      final sourceList = <Object?>[true, 3, 1.5, null];
      final source = <String, Object?>{
        'text': 'value',
        'nested': <String, Object?>{'items': sourceList},
      };

      final frozen = freezeJsonObject(source);
      sourceList[0] = false;
      (source['nested']! as Map<String, Object?>)['added'] = true;

      expect(frozen, <String, Object?>{
        'text': 'value',
        'nested': <String, Object?>{
          'items': <Object?>[true, 3, 1.5, null],
        },
      });
      expect(
        () => frozen['new'] = 'value',
        throwsUnsupportedError,
      );
      expect(
        () => (frozen['nested']! as Map<String, Object?>)['new'] = 'value',
        throwsUnsupportedError,
      );
      expect(
        () => ((frozen['nested']! as Map<String, Object?>)['items']!
                as List<Object?>)
            .add('value'),
        throwsUnsupportedError,
      );
    });

    test('rejects reference cycles', () {
      final map = <String, Object?>{};
      map['self'] = map;

      expect(
        () => freezeJsonValue(map),
        throwsA(
          isA<JsonValueException>().having(
            (error) => error.code,
            'code',
            'json_cycle',
          ),
        ),
      );
    });

    test('rejects non-finite numbers', () {
      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => freezeJsonValue(value),
          throwsA(
            isA<JsonValueException>().having(
              (error) => error.code,
              'code',
              'json_non_finite_number',
            ),
          ),
        );
      }
    });

    test('rejects unsupported objects and non-string map keys', () {
      expect(
        () => freezeJsonValue(DateTime.utc(2026)),
        throwsA(
          isA<JsonValueException>().having(
            (error) => error.code,
            'code',
            'json_unsupported_type',
          ),
        ),
      );
      expect(
        () => freezeJsonValue(<Object?, Object?>{1: 'value'}),
        throwsA(
          isA<JsonValueException>().having(
            (error) => error.code,
            'code',
            'json_non_string_key',
          ),
        ),
      );
    });
  });
}
