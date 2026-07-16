import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

const _alphabetPattern = r'^[0-9A-Za-z]+$';

void main() {
  group('generateId', () {
    test('defaults to 16 characters from the alphanumeric alphabet', () {
      final id = generateId();

      expect(id, hasLength(16));
      expect(RegExp(_alphabetPattern).hasMatch(id), isTrue);
    });

    test('honors an explicit size', () {
      final id = generateId(8);

      expect(id, hasLength(8));
    });

    test('produces different ids on repeated calls', () {
      final first = generateId();
      final second = generateId();

      expect(first, isNot(equals(second)));
    });
  });

  group('createIdGenerator', () {
    test('prefixes generated ids with a separator', () {
      final generator = createIdGenerator(prefix: 'msg', size: 8);

      final id = generator();

      expect(id, startsWith('msg-'));
      expect(id.substring('msg-'.length), hasLength(8));
    });

    test('without a prefix behaves like generateId', () {
      final generator = createIdGenerator(size: 10);

      final id = generator();

      expect(id, hasLength(10));
      expect(RegExp(_alphabetPattern).hasMatch(id), isTrue);
    });
  });
}
