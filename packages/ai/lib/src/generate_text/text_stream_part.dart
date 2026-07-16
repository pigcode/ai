import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:equatable/equatable.dart';

/// pigcode_ai 用户面流式分块(判别联合),对应 `streamText` 的 `stream`/`fullStream`。
///
/// 这是对齐 v7 `TextStreamPart`(共 26 型)的**裁剪脊柱集**;与契约层
/// `provider.LanguageModelStreamPart` 不同——后者是 provider 适配器产出的
/// 中性事件,本类型是工具循环聚合/转发给最终用户的高层分块。
///
/// **延后**(additive,不动脊柱):`source`、`file`、`reasoning-file`、
/// `custom`、`tool-error`、`tool-output-denied`。这些 v7 型号暂不建模,
/// 后续可增量补充。
sealed class TextStreamPart extends Equatable {
  const TextStreamPart();
}

/// 文本块开始(id 关联同一文本块的 start/delta/end)。
final class TextStartPart extends TextStreamPart {
  /// 创建文本块开始分块。
  const TextStartPart(this.id, {this.providerMetadata});

  /// 文本块 id。
  final String id;

  /// provider 侧元数据。
  final provider.ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, providerMetadata];
}

/// 文本块增量。
final class TextDeltaPart extends TextStreamPart {
  /// 创建文本块增量分块。
  const TextDeltaPart(this.id, this.delta, {this.providerMetadata});

  /// 文本块 id。
  final String id;

  /// 本次增量文本。
  final String delta;

  /// provider 侧元数据。
  final provider.ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, delta, providerMetadata];
}

/// 文本块结束。
final class TextEndPart extends TextStreamPart {
  /// 创建文本块结束分块。
  const TextEndPart(this.id, {this.providerMetadata});

  /// 文本块 id。
  final String id;

  /// provider 侧元数据。
  final provider.ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, providerMetadata];
}

/// 推理块开始(id 关联同一推理块的 start/delta/end)。
final class ReasoningStartPart extends TextStreamPart {
  /// 创建推理块开始分块。
  const ReasoningStartPart(this.id, {this.providerMetadata});

  /// 推理块 id。
  final String id;

  /// provider 侧元数据。
  final provider.ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, providerMetadata];
}

/// 推理块增量。
final class ReasoningDeltaPart extends TextStreamPart {
  /// 创建推理块增量分块。
  const ReasoningDeltaPart(this.id, this.delta, {this.providerMetadata});

  /// 推理块 id。
  final String id;

  /// 本次增量推理文本。
  final String delta;

  /// provider 侧元数据。
  final provider.ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, delta, providerMetadata];
}

/// 推理块结束。
final class ReasoningEndPart extends TextStreamPart {
  /// 创建推理块结束分块。
  const ReasoningEndPart(this.id, {this.providerMetadata});

  /// 推理块 id。
  final String id;

  /// provider 侧元数据。
  final provider.ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [id, providerMetadata];
}

/// 工具调用分块:原样包裹契约 [provider.ToolCall]。
///
/// 命名为 `ToolCallStreamPart` 而非 `ToolCallPart`,以避免与 pigcode_ai
/// 用户面消息层的 `ToolCallPart`(`prompt/content_part.dart`)撞名。
final class ToolCallStreamPart extends TextStreamPart {
  /// 创建工具调用分块。
  const ToolCallStreamPart(this.toolCall);

  /// 契约层工具调用。
  final provider.ToolCall toolCall;

  @override
  List<Object?> get props => [toolCall];
}

/// 工具结果分块:原样包裹契约 [provider.ToolResult]。
///
/// 命名为 `ToolResultStreamPart` 而非 `ToolResultPart`,理由同
/// [ToolCallStreamPart]。
final class ToolResultStreamPart extends TextStreamPart {
  /// 创建工具结果分块。
  const ToolResultStreamPart(this.toolResult);

  /// 契约层工具结果。
  final provider.ToolResult toolResult;

  @override
  List<Object?> get props => [toolResult];
}

/// 工具审批请求分块。
final class ToolApprovalRequestStreamPart extends TextStreamPart {
  /// 创建工具审批请求分块。
  const ToolApprovalRequestStreamPart(this.request);

  /// 契约层审批请求。
  final provider.ToolApprovalRequest request;

  @override
  List<Object?> get props => [request];
}

/// 工具审批回复分块。
final class ToolApprovalResponseStreamPart extends TextStreamPart {
  /// 创建工具审批回复分块。
  const ToolApprovalResponseStreamPart(this.response);

  /// 契约层审批回复。
  final provider.ToolApprovalResponsePart response;

  @override
  List<Object?> get props => [response];
}

/// 工具输入流式开始。
final class ToolInputStartPart extends TextStreamPart {
  /// 创建工具输入流式开始分块。
  const ToolInputStartPart(this.id, this.toolName);

  /// 工具输入块 id。
  final String id;

  /// 被调用的工具名。
  final String toolName;

  @override
  List<Object?> get props => [id, toolName];
}

/// 工具输入流式增量。
final class ToolInputDeltaPart extends TextStreamPart {
  /// 创建工具输入流式增量分块。
  const ToolInputDeltaPart(this.id, this.delta);

  /// 工具输入块 id。
  final String id;

  /// 本次增量输入片段。
  final String delta;

  @override
  List<Object?> get props => [id, delta];
}

/// 工具输入流式结束。
final class ToolInputEndPart extends TextStreamPart {
  /// 创建工具输入流式结束分块。
  const ToolInputEndPart(this.id);

  /// 工具输入块 id。
  final String id;

  @override
  List<Object?> get props => [id];
}

/// 步骤开始:携带请求侧元数据(可空)与本步告警。
final class StartStepPart extends TextStreamPart {
  /// 创建步骤开始分块。
  ///
  /// [warnings] 在构造时固化为不可变视图:`StreamTextResult` 会缓冲并向多个
  /// 订阅者重放**同一** part 实例,早订阅者对列表的改动不得让后订阅者看到
  /// 不同的告警。因需 `List.unmodifiable` 包装,本构造函数非 const。
  StartStepPart({this.request, required List<provider.Warning> warnings})
      : warnings = List<provider.Warning>.unmodifiable(warnings);

  /// 请求侧元数据(可空)。
  final provider.RequestInfo? request;

  /// 本步产生的告警。
  final List<provider.Warning> warnings;

  @override
  List<Object?> get props => [request, warnings];
}

/// 步骤结束:携带本步用量、终止原因与响应侧元数据(可空)。
final class FinishStepPart extends TextStreamPart {
  /// 创建步骤结束分块。
  const FinishStepPart({
    required this.usage,
    required this.finishReason,
    this.response,
  });

  /// 本步 token 用量。
  final provider.LanguageModelUsage usage;

  /// 本步终止原因。
  final provider.LanguageModelFinishReason finishReason;

  /// 响应侧元数据(可空;已按 v7 语义剔除 messages/body)。
  final provider.ResponseInfo? response;

  @override
  List<Object?> get props => [usage, finishReason, response];
}

/// 流首事件(整条 `streamText` 调用的开始,而非某一步)。
final class StartPart extends TextStreamPart {
  /// 创建流首分块。
  const StartPart();

  @override
  List<Object?> get props => const [];
}

/// 流终止事件:携带最终终止原因与累计用量。
final class FinishPart extends TextStreamPart {
  /// 创建流终止分块。
  const FinishPart({required this.finishReason, required this.totalUsage});

  /// 最终终止原因(末步)。
  final provider.LanguageModelFinishReason finishReason;

  /// 各步累加的 token 用量。
  final provider.LanguageModelUsage totalUsage;

  @override
  List<Object?> get props => [finishReason, totalUsage];
}

/// 错误分块:**终端事件**(error-as-event 终端模型)。一旦发出即视为流结束。
final class ErrorPart extends TextStreamPart {
  /// 创建错误分块。
  const ErrorPart(this.error);

  /// 承载的错误对象(可为 null)。
  final Object? error;

  @override
  List<Object?> get props => [error];
}

/// 中止分块:调用方通过 [provider.CancellationSignal] 主动取消。
final class AbortPart extends TextStreamPart {
  /// 创建中止分块。
  const AbortPart({this.reason});

  /// 中止原因(可空)。
  final String? reason;

  @override
  List<Object?> get props => [reason];
}

/// 原始分块:仅在 `includeRawChunks` 开启时出现,承载 provider 原始负载。
///
/// 命名为 `RawStreamPart` 而非 `RawPart`,避免歧义(见设计文档 §9.1)。
final class RawStreamPart extends TextStreamPart {
  /// 创建原始分块。
  const RawStreamPart(this.rawValue);

  /// provider 原始负载。
  final Object? rawValue;

  @override
  List<Object?> get props => [rawValue];
}
