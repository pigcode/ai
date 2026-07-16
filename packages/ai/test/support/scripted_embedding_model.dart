import 'dart:async';

// 前缀刻意不用 `provider`:实现 [spec.EmbeddingModel] 的类自带 `provider`
// 成员,会在类作用域内遮蔽同名 import 前缀导致无法引用契约类型
// (同 `scripted_model.dart` 选用 `lm` 前缀的先例)。
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as spec;

/// 脚本化 [spec.EmbeddingModel] 的一次预设批次响应。
///
/// 每次 [ScriptedEmbeddingModel.doEmbed] 调用按序消费下一个
/// [ScriptedEmbeddingBatch](除非该调用序号命中 [ScriptedEmbeddingModel.errors],
/// 此时改为抛出对应异常,见 [ScriptedEmbeddingModel] 类文档)。仅供测试支撑,
/// 不进入 `lib/` 正式产物。
final class ScriptedEmbeddingBatch {
  const ScriptedEmbeddingBatch({
    required this.embeddings,
    this.usage = const spec.EmbeddingUsage(),
    this.warnings = const [],
    this.providerMetadata,
    this.response,
  });

  final List<spec.Embedding> embeddings;
  final spec.EmbeddingUsage usage;
  final List<spec.Warning> warnings;
  final spec.ProviderMetadata? providerMetadata;
  final spec.EmbeddingResponseInfo? response;

  spec.EmbeddingModelResult toResult() => spec.EmbeddingModelResult(
        embeddings: embeddings,
        usage: usage,
        warnings: warnings,
        providerMetadata: providerMetadata,
        response: response,
      );
}

/// 可脚本化的 fake [spec.EmbeddingModel],仅用于测试支撑
/// (`test/support/`)。
///
/// 按构造时给定的 [batches] 顺序消费:每调用一次 [doEmbed] 就取用下一个
/// [ScriptedEmbeddingBatch]。若某批次应当抛错,改用 [errors](按调用序号
/// 映射,命中则 `throw`,优先于 [batches] 消费)。
///
/// [maxEmbeddingsPerCall]/[supportsParallelCalls] 均为 [FutureOr],
/// 可传同步值(含裸 `null`)或 `Future<...>`,覆盖"能力值本身是异步"的
/// 测试场景。
///
/// 每次 [doEmbed] 调用都会把收到的 [spec.EmbeddingModelCallOptions]
/// 追加进 [receivedCallOptions],供上层测试断言透传字段(如
/// providerOptions/headers/values 分批内容)。调用次数超出 [batches]
/// 长度且未命中 [errors] 时抛出 [StateError](编程错误,非模型失败)。
final class ScriptedEmbeddingModel implements spec.EmbeddingModel {
  ScriptedEmbeddingModel({
    required this.batches,
    this.errors = const {},
    String? provider,
    String? modelId,
    FutureOr<int?> maxEmbeddingsPerCall,
    FutureOr<bool> supportsParallelCalls = true,
  })  : provider = provider ?? 'scripted-embedding-provider',
        modelId = modelId ?? 'scripted-embedding-model',
        _maxEmbeddingsPerCall = maxEmbeddingsPerCall,
        _supportsParallelCalls = supportsParallelCalls;

  @override
  String get specificationVersion => 'v4';

  /// 按调用顺序消费的批次脚本。
  final List<ScriptedEmbeddingBatch> batches;

  /// 按调用序号(从 0 起)映射到应抛出的异常;命中时优先于 [batches]。
  final Map<int, Object> errors;

  @override
  final String provider;

  @override
  final String modelId;

  final FutureOr<int?> _maxEmbeddingsPerCall;
  final FutureOr<bool> _supportsParallelCalls;

  @override
  FutureOr<int?> get maxEmbeddingsPerCall => _maxEmbeddingsPerCall;

  @override
  FutureOr<bool> get supportsParallelCalls => _supportsParallelCalls;

  /// 已发生的 doEmbed 调用次数。
  int get callCount => _callCount;
  int _callCount = 0;

  /// 每次 doEmbed 收到的调用参数,按调用顺序追加。
  final List<spec.EmbeddingModelCallOptions> receivedCallOptions = [];

  @override
  Future<spec.EmbeddingModelResult> doEmbed(
    spec.EmbeddingModelCallOptions options,
  ) async {
    receivedCallOptions.add(options);
    final index = _callCount;
    _callCount++;

    final error = errors[index];
    if (error != null) {
      throw error;
    }

    if (index >= batches.length) {
      throw StateError(
        'ScriptedEmbeddingModel: no scripted batch left for call ${index + 1}',
      );
    }
    return batches[index].toResult();
  }
}
