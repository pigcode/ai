import 'package:pigcode_ai/src/generate_text/fix_json.dart';
import 'package:pigcode_ai/src/generate_text/parse_partial_json.dart';
import 'package:test/test.dart';

void main() {
  group('parsePartialJson', () {
    test('complete JSON returns successfulParse and value', () {
      final result = parsePartialJson('{"a":1}');

      expect(result.state, PartialJsonState.successfulParse);
      expect(result.value, <String, Object?>{'a': 1});
    });

    test('incomplete string value returns repairedParse and value', () {
      final result = parsePartialJson('{"value":"hel');

      expect(result.state, PartialJsonState.repairedParse);
      expect(result.value, <String, Object?>{'value': 'hel'});
    });

    test('incomplete numeric object returns repairedParse and value', () {
      final result = parsePartialJson('{"a":1');

      expect(result.state, PartialJsonState.repairedParse);
      expect(result.value, <String, Object?>{'a': 1});
    });

    test('incomplete array wrapper returns repairedParse and value', () {
      final result = parsePartialJson('{"elements":[1,2');

      expect(result.state, PartialJsonState.repairedParse);
      expect(result.value, <String, Object?>{
        'elements': <Object?>[1, 2],
      });
    });

    test('unrecoverable text returns failedParse', () {
      final result = parsePartialJson('not json');

      expect(result.state, PartialJsonState.failedParse);
      expect(result.value, isNull);
    });

    test('null returns undefinedInput', () {
      final result = parsePartialJson(null);

      expect(result.state, PartialJsonState.undefinedInput);
      expect(result.value, isNull);
    });
  });

  group('fixJson', () {
    test('repairs incomplete object', () {
      expect(fixJson('{"a":1'), '{"a":1}');
    });

    test('repairs incomplete array inside object', () {
      expect(fixJson('{"a":[1,2'), '{"a":[1,2]}');
    });

    test('repairs incomplete string inside object', () {
      expect(fixJson('{"a":"b'), '{"a":"b"}');
    });

    test('repairs incomplete literal inside object', () {
      expect(fixJson('{"a":tru'), '{"a":true}');
    });

    test('repairs incomplete top-level literal', () {
      expect(fixJson('fal'), 'false');
    });

    test('keeps complete top-level number unchanged', () {
      expect(fixJson('123'), '123');
    });

    test('trims trailing junk after the last valid prefix', () {
      expect(fixJson('{"a":1} trailing'), '{"a":1}');
    });
  });
}
