part of 'language_model_events.dart';

/// 文本块开始(id 关联同一文本块的 start/delta/end)。
final class TextStart extends Equatable implements LanguageModelStreamPart {
  /// 创建文本块开始事件。
  const TextStart(this.id, {this.providerMetadata});

  /// 文本块 id。
  final String id;

  /// 该分块携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, providerMetadata];
}

/// 文本块增量。
final class TextDelta extends Equatable implements LanguageModelStreamPart {
  /// 创建文本块增量事件。
  const TextDelta(this.id, this.delta, {this.providerMetadata});

  /// 文本块 id。
  final String id;

  /// 本次增量文本。
  final String delta;

  /// 该分块携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, delta, providerMetadata];
}

/// 文本块结束。
final class TextEnd extends Equatable implements LanguageModelStreamPart {
  /// 创建文本块结束事件。
  const TextEnd(this.id, {this.providerMetadata});

  /// 文本块 id。
  final String id;

  /// 该分块携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, providerMetadata];
}

/// 推理块开始(与文本块同构)。
final class ReasoningStart extends Equatable
    implements LanguageModelStreamPart {
  /// 创建推理块开始事件。
  const ReasoningStart(this.id, {this.providerMetadata});

  /// 推理块 id。
  final String id;

  /// 该分块携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, providerMetadata];
}

/// 推理块增量。
final class ReasoningDelta extends Equatable
    implements LanguageModelStreamPart {
  /// 创建推理块增量事件。
  const ReasoningDelta(this.id, this.delta, {this.providerMetadata});

  /// 推理块 id。
  final String id;

  /// 本次增量推理文本。
  final String delta;

  /// 该分块携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, delta, providerMetadata];
}

/// 推理块结束。
final class ReasoningEnd extends Equatable implements LanguageModelStreamPart {
  /// 创建推理块结束事件。
  const ReasoningEnd(this.id, {this.providerMetadata});

  /// 推理块 id。
  final String id;

  /// 该分块携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, providerMetadata];
}

/// 工具输入流式开始。
final class ToolInputStart extends Equatable
    implements LanguageModelStreamPart {
  /// 创建工具输入流式开始事件。
  const ToolInputStart({
    required this.id,
    required this.toolName,
    this.providerExecuted,
    this.isDynamic,
    this.title,
    this.providerMetadata,
  });

  /// 工具输入块 id。
  final String id;

  /// 被调用的工具名。
  final String toolName;

  /// 是否由 provider 侧直接执行。
  final bool? providerExecuted;

  /// 是否为动态(MCP)工具。
  final bool? isDynamic;

  /// 展示用标题。
  final String? title;

  /// 该分块携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props =>
      [id, toolName, providerExecuted, isDynamic, title, providerMetadata];
}

/// 工具输入流式增量。
final class ToolInputDelta extends Equatable
    implements LanguageModelStreamPart {
  /// 创建工具输入流式增量事件。
  const ToolInputDelta(this.id, this.delta, {this.providerMetadata});

  /// 工具输入块 id。
  final String id;

  /// 本次增量输入片段。
  final String delta;

  /// 该分块携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, delta, providerMetadata];
}

/// 工具输入流式结束。
final class ToolInputEnd extends Equatable implements LanguageModelStreamPart {
  /// 创建工具输入流式结束事件。
  const ToolInputEnd(this.id, {this.providerMetadata});

  /// 工具输入块 id。
  final String id;

  /// 该分块携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, providerMetadata];
}

/// 流首事件:携带本次调用的告警集合。
final class StreamStart extends Equatable implements LanguageModelStreamPart {
  /// 创建流首事件。
  const StreamStart(this.warnings);

  /// 本次调用产生的告警。
  final List<Warning> warnings;

  @override
  List<Object?> get props => [warnings];
}

/// 响应元数据分块。
final class ResponseMetadata extends Equatable
    implements LanguageModelStreamPart {
  /// 创建响应元数据分块。
  const ResponseMetadata({this.id, this.timestamp, this.modelId});

  /// 响应 id。
  final String? id;

  /// 响应时间戳。
  final DateTime? timestamp;

  /// 实际使用的模型 id。
  final String? modelId;

  @override
  List<Object?> get props => [id, timestamp, modelId];
}

/// 流终止分块:携带用量与终止原因。
final class FinishPart extends Equatable implements LanguageModelStreamPart {
  /// 创建流终止分块。
  const FinishPart({
    required this.usage,
    required this.finishReason,
    this.providerMetadata,
  });

  /// 本次调用的 token 用量。
  final LanguageModelUsage usage;

  /// 终止原因(统一分类 + provider 原值)。
  final LanguageModelFinishReason finishReason;

  /// 该分块携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [usage, finishReason, providerMetadata];
}

/// 原始分块:仅在 `includeRawChunks` 开启时出现,承载 provider 原始负载。
///
/// **有意的 opt-in 例外**:这是唯一可穿过 provider 边界的非中性数据,仅供高级/
/// 调试用途,默认关闭。消费者**不得**依赖其形状做常规处理。维护者已确认保留
/// (对齐 v7 的 includeRawChunks 能力),视为对 AGENTS.md 中性边界规则的显式豁免。
final class RawPart extends Equatable implements LanguageModelStreamPart {
  /// 创建原始分块。
  const RawPart(this.rawValue);

  /// provider 原始负载。
  final Object? rawValue;

  @override
  List<Object?> get props => [rawValue];
}

/// 错误分块:**终端事件**(error-as-event 终端模型,见 AGENTS.md)。
///
/// 一旦发出即视为流结束,其后**不应**再有任何分块;消费者/工具循环**不得**把
/// 出错后的内容当作有效续传。承载的错误对象可保留已产出内容的 partial 语义。
final class ErrorPart extends Equatable implements LanguageModelStreamPart {
  /// 创建错误分块。
  const ErrorPart(this.error);

  /// 承载的错误对象(可为 null)。
  final Object? error;

  @override
  List<Object?> get props => [error];
}
