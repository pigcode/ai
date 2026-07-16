import 'package:pigcode_ai_provider/src/json_value/json.dart';
import 'package:test/test.dart';

void main() {
  group('JsonSchema', () {
    test('two schemas wrapping equal nested maps are ==', () {
      const a = JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string'},
          'age': <String, Object?>{'type': 'integer'},
        },
        'required': <Object?>['name'],
      });
      const b = JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string'},
          'age': <String, Object?>{'type': 'integer'},
        },
        'required': <Object?>['name'],
      });

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two schemas wrapping different nested maps are !=', () {
      const a = JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string'},
        },
      });
      const b = JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'number'},
        },
      });

      expect(a, isNot(equals(b)));
    });

    test('exposes the wrapped JsonObject unchanged', () {
      const schema = JsonSchema(<String, Object?>{'type': 'string'});
      expect(schema.value, equals(<String, Object?>{'type': 'string'}));
    });

    test('props contains the wrapped value for equatable diffing', () {
      const schema = JsonSchema(<String, Object?>{'type': 'boolean'});
      expect(
          schema.props,
          equals(<Object?>[
            <String, Object?>{'type': 'boolean'},
          ]));
    });
  });

  group('JSON typedefs', () {
    test('JsonObject / JsonArray / JsonValue accept canonical JSON shapes', () {
      const JsonObject object = <String, Object?>{
        'a': 1,
        'b': <Object?>[true, null, 'x'],
        'c': <String, Object?>{'nested': 2.5},
      };
      const JsonArray array = <Object?>[1, 'two', false, null];
      // ignore: unnecessary_nullable_for_final_variable_declarations
      const JsonValue value = object;

      expect(object['a'], equals(1));
      expect(array.length, equals(4));
      expect(value, isA<JsonObject>());
    });
  });
}
