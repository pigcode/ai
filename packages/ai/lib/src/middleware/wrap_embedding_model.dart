import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

/// 用中间件包装一个 [provider.EmbeddingModel]，返回一个新的
/// [provider.EmbeddingModel]。
///
/// 缺省时透传被包裹模型的原始行为；传入 [providerId]/[modelId] 时优先于
/// middleware 的身份改写钩子。
provider.EmbeddingModel wrapEmbeddingModel(
  provider.EmbeddingModel model,
  provider.EmbeddingModelMiddleware middleware, {
  String? providerId,
  String? modelId,
}) {
  return _WrappedEmbeddingModel(
    model,
    middleware,
    providerId: providerId,
    modelId: modelId,
  );
}

typedef _EmbeddingModel = provider.EmbeddingModel;
typedef _EmbeddingModelMiddleware = provider.EmbeddingModelMiddleware;
typedef _EmbeddingModelCallOptions = provider.EmbeddingModelCallOptions;
typedef _EmbeddingModelResult = provider.EmbeddingModelResult;

const _embeddingModelSpecVersion = provider.embeddingModelSpecVersion;

final class _WrappedEmbeddingModel implements _EmbeddingModel {
  const _WrappedEmbeddingModel(
    this._model,
    this._middleware, {
    String? providerId,
    String? modelId,
  })  : _providerId = providerId,
        _modelId = modelId;

  final _EmbeddingModel _model;
  final _EmbeddingModelMiddleware _middleware;
  final String? _providerId;
  final String? _modelId;

  @override
  String get specificationVersion => _embeddingModelSpecVersion;

  @override
  String get provider =>
      _providerId ??
      _middleware.overrideProvider?.call(_model) ??
      _model.provider;

  @override
  String get modelId =>
      _modelId ?? _middleware.overrideModelId?.call(_model) ?? _model.modelId;

  @override
  FutureOr<int?> get maxEmbeddingsPerCall {
    final overrideMaxEmbeddingsPerCall =
        _middleware.overrideMaxEmbeddingsPerCall;
    if (overrideMaxEmbeddingsPerCall == null) {
      return _model.maxEmbeddingsPerCall;
    }
    return overrideMaxEmbeddingsPerCall(_model);
  }

  @override
  FutureOr<bool> get supportsParallelCalls =>
      _middleware.overrideSupportsParallelCalls?.call(_model) ??
      _model.supportsParallelCalls;

  @override
  Future<_EmbeddingModelResult> doEmbed(
    _EmbeddingModelCallOptions options,
  ) async {
    final params = await _transformParams(options);
    final wrapEmbed = _middleware.wrapEmbed;
    if (wrapEmbed == null) {
      return _model.doEmbed(params);
    }
    return wrapEmbed(
      doEmbed: () => _model.doEmbed(params),
      params: params,
      model: _model,
    );
  }

  Future<_EmbeddingModelCallOptions> _transformParams(
    _EmbeddingModelCallOptions params,
  ) async {
    final transformParams = _middleware.transformParams;
    if (transformParams == null) {
      return params;
    }
    return transformParams(params: params, model: _model);
  }
}
