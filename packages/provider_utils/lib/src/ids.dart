import 'dart:math';

const _defaultAlphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const _defaultSeparator = '-';

final _random = Random();

/// 生成一个长度为 [size] 的非加密随机字符串,取自字母数字表
/// `0-9A-Za-z`。等价于 `createIdGenerator(size: size)()` 的一次性调用,
/// 每次调用都产出新值。
String generateId([int size = 16]) {
  return _randomAlphanumeric(size);
}

/// 构造一个可重复调用的 id 生成函数。
///
/// 每次调用返回的字符串由 [size] 个字母数字字符组成;若提供 [prefix],
/// 生成结果为 `'$prefix-$随机部分'`(分隔符固定为 `-`)。非加密随机,
/// 使用 `dart:math` 的 [Random]。
String Function() createIdGenerator({String? prefix, int size = 16}) {
  if (prefix == null) {
    return () => _randomAlphanumeric(size);
  }
  return () => '$prefix$_defaultSeparator${_randomAlphanumeric(size)}';
}

String _randomAlphanumeric(int size) {
  final buffer = StringBuffer();
  for (var i = 0; i < size; i++) {
    buffer.write(_defaultAlphabet[_random.nextInt(_defaultAlphabet.length)]);
  }
  return buffer.toString();
}
