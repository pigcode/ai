import 'dart:async';

import '../image_model/image_model.dart';

/// `wrapGenerate` 内部委托的 image 生成闭包：执行被包裹模型的
/// `doGenerate`。
typedef ImageModelDoGenerate = Future<ImageModelResult> Function();

/// image 模型中间件：一组可空的钩子函数字段。
///
/// 对齐上游 v4 image middleware 的形状。未设置的钩子为 `null`，由核心侧
/// `wrapImageModel` 按需调用。
final class ImageModelMiddleware {
  /// 构造 image 中间件。所有钩子缺省即 `null`。
  const ImageModelMiddleware({
    this.overrideProvider,
    this.overrideModelId,
    this.overrideMaxImagesPerCall,
    this.transformParams,
    this.wrapGenerate,
  });

  /// 改写被包裹模型对外暴露的 provider 名；返回 `null` 表示不改写。
  final String? Function(ImageModel model)? overrideProvider;

  /// 改写被包裹模型对外暴露的 modelId；返回 `null` 表示不改写。
  final String? Function(ImageModel model)? overrideModelId;

  /// 改写单次 `doGenerate` 最多可生成的图片数量。
  final FutureOr<int?> Function(ImageModel model)? overrideMaxImagesPerCall;

  /// 在调用底层模型前重建调用参数。
  final Future<ImageModelCallOptions> Function({
    required ImageModelCallOptions params,
    required ImageModel model,
  })? transformParams;

  /// 包裹 image 生成调用：可在调用 `doGenerate` 前后插入逻辑或短路返回。
  final Future<ImageModelResult> Function({
    required ImageModelDoGenerate doGenerate,
    required ImageModelCallOptions params,
    required ImageModel model,
  })? wrapGenerate;
}
