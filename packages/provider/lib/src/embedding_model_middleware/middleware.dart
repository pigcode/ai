import 'dart:async';

import '../embedding_model/embedding_model.dart';

/// `wrapEmbed` 内部委托的 embedding 闭包：执行被包裹模型的 `doEmbed`。
typedef EmbeddingModelDoEmbed = Future<EmbeddingModelResult> Function();

/// embedding 模型中间件：一组可空的钩子函数字段。
///
/// 对齐语言模型中间件的形状。未设置的钩子为 `null`，由核心侧
/// `wrapEmbeddingModel` 按需调用。
final class EmbeddingModelMiddleware {
  /// 构造 embedding 中间件。所有钩子缺省即 `null`。
  const EmbeddingModelMiddleware({
    this.overrideProvider,
    this.overrideModelId,
    this.overrideMaxEmbeddingsPerCall,
    this.overrideSupportsParallelCalls,
    this.transformParams,
    this.wrapEmbed,
  });

  /// 改写被包裹模型对外暴露的 provider 名；返回 `null` 表示不改写。
  final String? Function(EmbeddingModel model)? overrideProvider;

  /// 改写被包裹模型对外暴露的 modelId；返回 `null` 表示不改写。
  final String? Function(EmbeddingModel model)? overrideModelId;

  /// 改写单次 `doEmbed` 最多可处理的输入数量。
  final FutureOr<int?> Function(EmbeddingModel model)?
      overrideMaxEmbeddingsPerCall;

  /// 改写模型是否支持并发 embedding 调用。
  final FutureOr<bool> Function(EmbeddingModel model)?
      overrideSupportsParallelCalls;

  /// 在调用底层模型前重建调用参数。
  final Future<EmbeddingModelCallOptions> Function({
    required EmbeddingModelCallOptions params,
    required EmbeddingModel model,
  })? transformParams;

  /// 包裹 embedding 调用：可在调用 `doEmbed` 前后插入逻辑或短路返回。
  final Future<EmbeddingModelResult> Function({
    required EmbeddingModelDoEmbed doEmbed,
    required EmbeddingModelCallOptions params,
    required EmbeddingModel model,
  })? wrapEmbed;
}
