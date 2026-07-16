import 'dart:math' as math;

/// 计算两个向量的余弦相似度,常用于比较 embedding 的相似程度。
///
/// 对齐 v7 `cosineSimilarity`:[a]/[b] 长度不等时抛 [ArgumentError]
/// (英文文案)。两向量长度均为 0 时返回 `0`(空向量场景,先于零向量
/// 判断独立返回,不抛错)。任一向量模长平方和为 0(非空但全零向量)
/// 时同样返回 `0`(避免除零产生 NaN,对齐 raw 的短路判断)。
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError(
      'Vectors must have the same length '
      '(vector1Length: ${a.length}, vector2Length: ${b.length})',
    );
  }

  final n = a.length;
  if (n == 0) {
    return 0;
  }

  var magnitudeSquared1 = 0.0;
  var magnitudeSquared2 = 0.0;
  var dotProduct = 0.0;

  for (var i = 0; i < n; i++) {
    final value1 = a[i];
    final value2 = b[i];
    magnitudeSquared1 += value1 * value1;
    magnitudeSquared2 += value2 * value2;
    dotProduct += value1 * value2;
  }

  if (magnitudeSquared1 == 0 || magnitudeSquared2 == 0) {
    return 0;
  }
  return dotProduct /
      (math.sqrt(magnitudeSquared1) * math.sqrt(magnitudeSquared2));
}
