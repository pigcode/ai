import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../logger/log_warnings.dart';

/// `embed` 的结果:单值的 embedding、原始值、用量、告警与可选元数据。
///
/// 字段形状逐字对齐 v7 `EmbedResult`;[response] 复用契约层新增的
/// [provider.EmbeddingResponseInfo](非 `provider.ResponseInfo`)。
final class EmbedResult {
  const EmbedResult({
    required this.value,
    required this.embedding,
    required this.usage,
    required this.warnings,
    this.providerMetadata,
    this.response,
  });

  /// 被嵌入的原始值。
  final String value;

  /// 嵌入向量。
  final provider.Embedding embedding;

  /// 本次调用的 token 用量。
  final provider.EmbeddingUsage usage;

  /// provider 侧告警(如不支持的设置)。
  final List<provider.Warning> warnings;

  /// provider 私有元数据。
  final provider.ProviderMetadata? providerMetadata;

  /// 响应侧元数据(headers/body)。
  final provider.EmbeddingResponseInfo? response;
}

/// 用给定的 [model] 生成单个 [value] 的 embedding。
///
/// 把 [value] 包成 `values: [value]` 调用一次 [provider.EmbeddingModel.doEmbed],
/// 取回结果的 `embeddings` 单个元素作为 [EmbedResult.embedding]。
///
/// **越界防御裁决**:v7 上游对 `modelResponse.embeddings[0]` 无任何长度校验,
/// 若 provider 实现返回空 `embeddings` 列表,上游会拿到 `undefined`
/// (JS 数组越界访问不抛错,产出 `undefined`),后续 `result.embedding`
/// 会是 `undefined`——即 raw 对这一异常场景没有专门处理,属于"信任 provider
/// 实现正确性"的隐式契约。Dart 的 `List.first`/下标越界会抛
/// `RangeError`——若原样对齐(不加任何守卫),provider 违反"必须为每个
/// value 返回一个 embedding"的契约时,调用方会看到一个语义不明的
/// `RangeError('No element')`。本实现**主动偏离**:在越界访问前加一层
/// 断言级 [StateError],携带清晰诊断信息(provider/modelId),这不改变
/// 正常路径行为(provider 正确实现时永远不触发),只是把"provider 违反
/// 契约"这一编程错误的报错信息从裸 `RangeError` 换成可诊断的消息
/// ——不属于契约行为变化,属于错误信息质量改进。
///
/// 多于 1 个 embedding 时对齐 raw 只取首个、静默丢弃多余元素的行为,
/// 不额外加"长度必须恰好为 1"的校验。
Future<EmbedResult> embed({
  required provider.EmbeddingModel model,
  required String value,
  provider.ProviderOptions? providerOptions,
  Map<String, String>? headers,
  provider.CancellationSignal? cancellation,
}) async {
  final modelResponse = await model.doEmbed(
    provider.EmbeddingModelCallOptions(
      values: [value],
      headers: headers,
      providerOptions: providerOptions,
      cancellation: cancellation,
    ),
  );
  logWarnings(
    warnings: modelResponse.warnings,
    provider: model.provider,
    model: model.modelId,
  );

  if (modelResponse.embeddings.isEmpty) {
    throw StateError(
      'Embedding model "${model.modelId}" (provider "${model.provider}") '
      'returned no embeddings for a single-value doEmbed call.',
    );
  }

  return EmbedResult(
    value: value,
    embedding: modelResponse.embeddings.first,
    usage: modelResponse.usage,
    warnings: modelResponse.warnings,
    providerMetadata: modelResponse.providerMetadata,
    response: modelResponse.response,
  );
}
