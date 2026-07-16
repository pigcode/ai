import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:test/test.dart';

void main() {
  group('cosineSimilarity', () {
    test('同向向量返回 1', () {
      expect(cosineSimilarity([1, 2, 3], [2, 4, 6]), closeTo(1.0, 1e-9));
    });

    test('正交向量返回 0', () {
      expect(cosineSimilarity([1, 0], [0, 1]), closeTo(0.0, 1e-9));
    });

    test('反向向量返回 -1', () {
      expect(cosineSimilarity([1, 2, 3], [-1, -2, -3]), closeTo(-1.0, 1e-9));
    });

    test('长度不等抛 ArgumentError', () {
      expect(
        () => cosineSimilarity([1, 2], [1, 2, 3]),
        throwsArgumentError,
      );
    });

    test('空向量返回 0(不抛错)', () {
      expect(cosineSimilarity(<double>[], <double>[]), equals(0.0));
    });

    test('零向量返回 0(避免除零)', () {
      expect(cosineSimilarity([0, 0, 0], [1, 2, 3]), equals(0.0));
      expect(cosineSimilarity([1, 2, 3], [0, 0, 0]), equals(0.0));
      expect(cosineSimilarity([0, 0], [0, 0]), equals(0.0));
    });
  });
}
