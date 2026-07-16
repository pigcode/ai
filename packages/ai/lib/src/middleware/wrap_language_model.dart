import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

/// 用中间件包装一个 [provider.LanguageModel]，返回一个新的
/// [provider.LanguageModel]。
///
/// 各钩子按需应用，缺省时透传被包裹模型的原始行为：
/// - `provider`/`modelId` 分别经 `overrideProvider`/`overrideModelId`
///   改写；未设置时透传被包裹模型的对应值。
/// - `supportedUrls` 经 `overrideSupportedUrls` 改写；未设置时透传。
/// - `doGenerate`/`doStream` 调用前先经 `transformParams`（若设置）重建
///   调用参数，再交给 `wrapGenerate`/`wrapStream`（若设置）；未设置对应
///   包裹钩子时，直接调用被包裹模型的 `doGenerate`/`doStream`。
///
/// 多层中间件通过嵌套调用 `wrapLanguageModel` 叠加：外层（先传入的）
/// 中间件的 `transformParams` 在调用链上先执行（对原始入参先做变换），
/// 其产出的参数再交给内层（后传入、离被包裹模型最近）的中间件继续
/// 处理；内层的 `transformParams` 最后执行，直接作用在紧邻真实模型的
/// 调用参数上。因此对同一字段的冲突改写，内层（最后包裹的那一层）
/// 生效——这与 v7 `wrapLanguageModel`（`wrap-language-model.ts`：
/// "the first middleware will transform the input first, and the last
/// middleware will be wrapped directly around the model"，实现上通过
/// 反转中间件数组令最后一个中间件最贴近模型）语义一致。
/// `wrapGenerate`/`wrapStream` 同理：外层先包裹，内层离模型最近，
/// 内层的结果处理离真实调用结果更近。
provider.LanguageModel wrapLanguageModel(
  provider.LanguageModel model,
  provider.LanguageModelMiddleware middleware,
) {
  return _WrappedLanguageModel(model, middleware);
}

// 局部类型别名：`_WrappedLanguageModel` 必须实现名为 `provider` 的 getter
// （契约接口字段），这会在类体内遮蔽 `provider` 这个 import 前缀本身，导致
// `provider.LanguageModel` 等限定名无法解析。这里为类体内需要用到的契约
// 类型起局部别名以绕开遮蔽，公共函数签名与文档注释仍使用 `provider.` 前缀。
typedef _LanguageModel = provider.LanguageModel;
typedef _LanguageModelMiddleware = provider.LanguageModelMiddleware;
typedef _LanguageModelCallOptions = provider.LanguageModelCallOptions;
typedef _LanguageModelGenerateResult = provider.LanguageModelGenerateResult;
typedef _LanguageModelStreamResult = provider.LanguageModelStreamResult;

const _languageModelSpecVersion = provider.languageModelSpecVersion;

/// [wrapLanguageModel] 内部使用的包装实现，库私有。
final class _WrappedLanguageModel implements _LanguageModel {
  const _WrappedLanguageModel(this._model, this._middleware);

  final _LanguageModel _model;
  final _LanguageModelMiddleware _middleware;

  @override
  String get specificationVersion => _languageModelSpecVersion;

  @override
  String get provider =>
      _middleware.overrideProvider?.call(_model) ?? _model.provider;

  @override
  String get modelId =>
      _middleware.overrideModelId?.call(_model) ?? _model.modelId;

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls =>
      _middleware.overrideSupportedUrls?.call(_model) ?? _model.supportedUrls;

  @override
  Future<_LanguageModelGenerateResult> doGenerate(
    _LanguageModelCallOptions options,
  ) async {
    final params = await _transformParams(stream: false, params: options);
    final wrapGenerate = _middleware.wrapGenerate;
    if (wrapGenerate == null) {
      return _model.doGenerate(params);
    }
    return wrapGenerate(
      doGenerate: () => _model.doGenerate(params),
      doStream: () => _model.doStream(params),
      params: params,
      model: _model,
    );
  }

  @override
  Future<_LanguageModelStreamResult> doStream(
    _LanguageModelCallOptions options,
  ) async {
    final params = await _transformParams(stream: true, params: options);
    final wrapStream = _middleware.wrapStream;
    if (wrapStream == null) {
      return _model.doStream(params);
    }
    return wrapStream(
      doGenerate: () => _model.doGenerate(params),
      doStream: () => _model.doStream(params),
      params: params,
      model: _model,
    );
  }

  Future<_LanguageModelCallOptions> _transformParams({
    required bool stream,
    required _LanguageModelCallOptions params,
  }) async {
    final transformParams = _middleware.transformParams;
    if (transformParams == null) {
      return params;
    }
    return transformParams(stream: stream, params: params, model: _model);
  }
}
