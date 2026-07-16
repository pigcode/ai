import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../logger/log_warnings.dart';
import '../util/split_array.dart';

/// `embedMany` 的结果:批量 embedding(保序)、原始值列表、
/// 求和用量(null 传染)、串接告警、合并后的 provider 元数据、逐批响应。
final class EmbedManyResult {
  const EmbedManyResult({
    required this.values,
    required this.embeddings,
    required this.usage,
    required this.warnings,
    this.providerMetadata,
    required this.responses,
  });

  /// 被嵌入的原始值列表。
  final List<String> values;

  /// 嵌入向量列表,与 [values] 保序对应。
  final List<provider.Embedding> embeddings;

  /// 汇总 token 用量:任一参与批次的 `tokens` 为 `null`,汇总即为 `null`
  /// (对齐 v7 NaN 传染语义,pigcode 侧以 null 表达——raw 以
  /// `usage ?? { tokens: NaN }` 兜底后 `tokens +=` 传染;pigcode 契约
  /// `EmbeddingUsage` 容器非空、字段可空,"usage 对象缺席"唯一等价投影
  /// 即 `usage.tokens == null`,sentinel 从 NaN 换成 null,传染语义不变)。
  final provider.EmbeddingUsage usage;

  /// 全部批次的告警按批次顺序串接。
  final List<provider.Warning> warnings;

  /// 全部批次的 provider 元数据按 provider 名浅合并(同名键后批覆盖前批,
  /// 详见 `_mergeProviderMetadata`)。
  final provider.ProviderMetadata? providerMetadata;

  /// 逐批响应元数据,与批次顺序对应(单个元素可能为 `null`)。
  final List<provider.EmbeddingResponseInfo?> responses;
}

/// 用给定的 [model] 批量生成 [values] 的 embedding。
///
/// 若模型 `maxEmbeddingsPerCall` 为 `null`,走单次全量快路径(usage/
/// warnings/response 直接取该次 doEmbed 结果本身,`responses` 为长度 1
/// 的列表——元素可能为 `null` 也照放,对齐 raw 快路径行为);否则按
/// [splitArray] 切成值批,再按 `supportsParallelCalls`/[maxParallelCalls]
/// 分组并发(组间串行、组内并发),逐批聚合结果。算法逐字对齐 v7
/// `embedMany` 两级切分:先按 `maxEmbeddingsPerCall` 切"值批",再把
/// 值批列表按并行度切"并行组",外层 for 串行 await 每组的
/// `Future.wait`——组内并发、组间顺序,即 [maxParallelCalls] 限流语义。
Future<EmbedManyResult> embedMany({
  required provider.EmbeddingModel model,
  required List<String> values,
  int? maxParallelCalls,
  provider.ProviderOptions? providerOptions,
  Map<String, String>? headers,
  provider.CancellationSignal? cancellation,
}) async {
  // 入口守卫:非正值直接拒绝,避免内部 splitArray 的 'chunkSize'
  // 参数名泄漏给调用方(此处以 embedMany 自己的参数名报错)。
  if (maxParallelCalls != null && maxParallelCalls <= 0) {
    throw ArgumentError.value(
      maxParallelCalls,
      'maxParallelCalls',
      'must be greater than 0',
    );
  }

  // 顺序 await 两能力值:FutureOr<int?>/FutureOr<bool> 均可直接 await,
  // 无需 Future.wait 包装(两次读取之间无顺序依赖,顺序 await 与并发
  // 读取在行为上无差异)。
  final maxEmbeddingsPerCall = await model.maxEmbeddingsPerCall;
  final supportsParallelCalls = await model.supportsParallelCalls;

  if (maxEmbeddingsPerCall == null) {
    // 单次全量快路径:不切批、不做多批聚合,usage/warnings/response
    // 直接取该次 doEmbed 结果本身。
    final modelResponse = await model.doEmbed(
      provider.EmbeddingModelCallOptions(
        values: values,
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

    return EmbedManyResult(
      values: values,
      embeddings: modelResponse.embeddings,
      usage: modelResponse.usage,
      warnings: modelResponse.warnings,
      providerMetadata: modelResponse.providerMetadata,
      responses: [modelResponse.response],
    );
  }

  final valueChunks = splitArray(values, maxEmbeddingsPerCall);
  final parallelChunks = _groupForParallelism(
    valueChunks,
    supportsParallelCalls: supportsParallelCalls,
    maxParallelCalls: maxParallelCalls,
  );

  final embeddings = <provider.Embedding>[];
  final warnings = <provider.Warning>[];
  final responses = <provider.EmbeddingResponseInfo?>[];
  // tokenTotal 初始为 0、tokensPoisoned 初始为 false:逐字对齐 raw
  // `let tokens = 0`(从未被 `+=` 修改时,字面结果就是 0——覆盖"零批次
  // 参与"这一边界,即空 values 场景)。
  var tokenTotal = 0;
  var tokensPoisoned = false;
  provider.ProviderMetadata? providerMetadata;

  for (final parallelChunk in parallelChunks) {
    // 组内并发:Future.wait 保序返回,与 parallelChunk 顺序一致。
    final results = await Future.wait(
      parallelChunk.map(
        (chunk) => model.doEmbed(
          provider.EmbeddingModelCallOptions(
            values: chunk,
            headers: headers,
            providerOptions: providerOptions,
            cancellation: cancellation,
          ),
        ),
      ),
    );

    for (final result in results) {
      logWarnings(
        warnings: result.warnings,
        provider: model.provider,
        model: model.modelId,
      );
      embeddings.addAll(result.embeddings);
      warnings.addAll(result.warnings);
      responses.add(result.response);

      final tokens = result.usage.tokens;
      if (tokens == null) {
        // null 传染:一旦有批次缺席 tokens,总和永久污染为 null
        // (对齐 raw NaN 传染语义)。
        tokensPoisoned = true;
      } else {
        tokenTotal += tokens;
      }

      final batchMetadata = result.providerMetadata;
      if (batchMetadata != null) {
        providerMetadata = _mergeProviderMetadata(
          providerMetadata,
          batchMetadata,
        );
      }
    }
  }

  return EmbedManyResult(
    values: values,
    embeddings: embeddings,
    usage: provider.EmbeddingUsage(
      tokens: tokensPoisoned ? null : tokenTotal,
    ),
    warnings: warnings,
    providerMetadata: providerMetadata,
    responses: responses,
  );
}

/// 把「值批列表」按并行度分组:`supportsParallelCalls == false` 时强制
/// 分组大小为 1(组间串行执行,效果等价于全部值批严格串行);
/// `true` 且 [maxParallelCalls] 为 `null` 时不限并行度——把全部值批放进
/// **唯一一组**(对齐 raw `splitArray(valueChunks, Infinity)` 只产出一组
/// 的行为;`splitArray` 签名是 `int chunkSize`,无法直接表达 `Infinity`,
/// 故在此单独处理);否则按 [maxParallelCalls] 切分。
List<List<List<String>>> _groupForParallelism(
  List<List<String>> valueChunks, {
  required bool supportsParallelCalls,
  required int? maxParallelCalls,
}) {
  if (!supportsParallelCalls) {
    return splitArray(valueChunks, 1);
  }
  if (maxParallelCalls == null) {
    return valueChunks.isEmpty ? <List<List<String>>>[] : [valueChunks];
  }
  return splitArray(valueChunks, maxParallelCalls);
}

/// 按 provider 名做「内层 spread 合并」:同一 provider 名下,本批
/// [incoming] 的键覆盖累积 [existing] 的同名键;不同 provider 名的键
/// 各自独立累积。外层整体不做替换(对齐 raw 逐 provider 名
/// `{...existing[providerName] ?? {}, ...metadata}` 的合并层级)。
provider.ProviderMetadata _mergeProviderMetadata(
  provider.ProviderMetadata? existing,
  provider.ProviderMetadata incoming,
) {
  final merged = <String, provider.JsonObject>{
    if (existing != null) ...existing,
  };
  for (final entry in incoming.entries) {
    merged[entry.key] = <String, Object?>{
      ...?merged[entry.key],
      ...entry.value,
    };
  }
  return merged;
}
