import 'package:pigcode_ai/src/util/split_array.dart';
import 'package:test/test.dart';

void main() {
  group('splitArray', () {
    test('chunkSize <= 0 抛 ArgumentError', () {
      expect(() => splitArray([1, 2, 3], 0), throwsArgumentError);
      expect(() => splitArray([1, 2, 3], -1), throwsArgumentError);
    });

    test('空数组返回空列表', () {
      expect(splitArray(<int>[], 3), isEmpty);
    });

    test('恰好整除:无空尾批', () {
      expect(
        splitArray([1, 2, 3, 4], 2),
        [
          [1, 2],
          [3, 4],
        ],
      );
    });

    test('有余数:末批短于 chunkSize', () {
      expect(
        splitArray([1, 2, 3, 4, 5], 2),
        [
          [1, 2],
          [3, 4],
          [5],
        ],
      );
    });

    test('单元素数组、chunkSize 大于数组长度:单一分片', () {
      expect(splitArray([1], 5), [
        [1],
      ]);
    });

    test('chunkSize 恰好等于数组长度:单一分片', () {
      expect(splitArray([1, 2, 3], 3), [
        [1, 2, 3],
      ]);
    });
  });
}
