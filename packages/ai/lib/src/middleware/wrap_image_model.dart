import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

/// 用中间件包装一个 [provider.ImageModel]，返回一个新的
/// [provider.ImageModel]。
///
/// 缺省时透传被包裹模型的原始行为；传入 [providerId]/[modelId] 时优先于
/// middleware 的身份改写钩子。
provider.ImageModel wrapImageModel(
  provider.ImageModel model,
  provider.ImageModelMiddleware middleware, {
  String? providerId,
  String? modelId,
}) {
  return _WrappedImageModel(
    model,
    middleware,
    providerId: providerId,
    modelId: modelId,
  );
}

typedef _ImageModel = provider.ImageModel;
typedef _ImageModelMiddleware = provider.ImageModelMiddleware;
typedef _ImageModelCallOptions = provider.ImageModelCallOptions;
typedef _ImageModelResult = provider.ImageModelResult;

const _imageModelSpecVersion = provider.imageModelSpecVersion;

final class _WrappedImageModel implements _ImageModel {
  const _WrappedImageModel(
    this._model,
    this._middleware, {
    String? providerId,
    String? modelId,
  })  : _providerId = providerId,
        _modelId = modelId;

  final _ImageModel _model;
  final _ImageModelMiddleware _middleware;
  final String? _providerId;
  final String? _modelId;

  @override
  String get specificationVersion => _imageModelSpecVersion;

  @override
  String get provider =>
      _providerId ??
      _middleware.overrideProvider?.call(_model) ??
      _model.provider;

  @override
  String get modelId =>
      _modelId ?? _middleware.overrideModelId?.call(_model) ?? _model.modelId;

  @override
  FutureOr<int?> get maxImagesPerCall {
    final overrideMaxImagesPerCall = _middleware.overrideMaxImagesPerCall;
    if (overrideMaxImagesPerCall == null) {
      return _model.maxImagesPerCall;
    }
    return overrideMaxImagesPerCall(_model);
  }

  @override
  Future<_ImageModelResult> doGenerate(
    _ImageModelCallOptions options,
  ) async {
    final params = await _transformParams(options);
    final wrapGenerate = _middleware.wrapGenerate;
    if (wrapGenerate == null) {
      return _model.doGenerate(params);
    }
    return wrapGenerate(
      doGenerate: () => _model.doGenerate(params),
      params: params,
      model: _model,
    );
  }

  Future<_ImageModelCallOptions> _transformParams(
    _ImageModelCallOptions params,
  ) async {
    final transformParams = _middleware.transformParams;
    if (transformParams == null) {
      return params;
    }
    return transformParams(params: params, model: _model);
  }
}
