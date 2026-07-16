/// 把 [array] 切成若干长度不超过 [chunkSize] 的连续子列表。
///
/// 对齐 v7 `splitArray`:[chunkSize] 必须为正,否则抛
/// [ArgumentError]("chunkSize must be greater than 0",英文文案对齐
/// raw 的 `Error('chunkSize must be greater than 0')`)。空 [array]
/// 返回空列表(循环体不执行,非错误)。最后一个分片可能短于
/// [chunkSize](恰好整除时无空尾片)。
///
/// pigcode_ai 内部私有工具,不进 `pigcode_ai.dart` barrel
/// ——仅 `embed/embed_many.dart` 使用。
List<List<T>> splitArray<T>(List<T> array, int chunkSize) {
  if (chunkSize <= 0) {
    throw ArgumentError('chunkSize must be greater than 0');
  }

  final result = <List<T>>[];
  for (var i = 0; i < array.length; i += chunkSize) {
    final end = i + chunkSize < array.length ? i + chunkSize : array.length;
    result.add(array.sublist(i, end));
  }
  return result;
}
