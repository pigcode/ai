import 'package:equatable/equatable.dart';

import '../json_value/json.dart';
import '../shared/shared.dart';
import 'tool.dart';

/// 角色标记接口：每个 part 类型实现它"被允许出现的消息角色"。
///
/// 把 part 放进不允许的角色列表（如把 [ReasoningPart] 放进 `List<UserContentPart>`）
/// 会在编译期报错，从而在类型层面约束 prompt 结构。
sealed class UserContentPart {}

/// assistant 角色允许携带的内容 part 标记接口。
sealed class AssistantContentPart {}

/// tool 角色允许携带的内容 part 标记接口。
sealed class ToolContentPart {}

/// 纯文本片段。可出现在 user 与 assistant 消息中。
final class TextPart
    with EquatableMixin
    implements UserContentPart, AssistantContentPart {
  const TextPart(this.text, {this.providerOptions});

  /// 文本内容。
  final String text;

  /// 各 provider 的透传选项，外层键为 provider 名。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [text, providerOptions];
}

/// 文件片段（图片/文档等）。可出现在 user 与 assistant 消息中。
final class FilePart
    with EquatableMixin
    implements UserContentPart, AssistantContentPart {
  const FilePart({
    required this.data,
    required this.mediaType,
    this.filename,
    this.providerOptions,
  });

  /// 文件数据载体（字节/base64/URL/引用等变体）。
  final FileData data;

  /// IANA 媒体类型，如 `image/png`。
  final String mediaType;

  /// 可选的原始文件名。
  final String? filename;

  /// 各 provider 的透传选项。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [data, mediaType, filename, providerOptions];
}

/// 模型推理（思维链）文本片段。仅出现在 assistant 消息中。
final class ReasoningPart with EquatableMixin implements AssistantContentPart {
  const ReasoningPart(this.text, {this.providerOptions});

  /// 推理文本内容。
  final String text;

  /// 各 provider 的透传选项。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [text, providerOptions];
}

/// 以文件形式承载的推理内容。仅出现在 assistant 消息中。
final class ReasoningFilePart
    with EquatableMixin
    implements AssistantContentPart {
  const ReasoningFilePart({
    required this.data,
    required this.mediaType,
    this.providerOptions,
  });

  /// 推理文件数据载体。
  final FileData data;

  /// IANA 媒体类型。
  final String mediaType;

  /// 各 provider 的透传选项。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [data, mediaType, providerOptions];
}

/// provider 自定义内容片段。仅出现在 assistant 消息中。
final class CustomPart with EquatableMixin implements AssistantContentPart {
  const CustomPart(this.kind, {this.providerOptions});

  /// 自定义种类，形如 `ns.name`（点号命名空间在使用点运行时校验）。
  final String kind;

  /// 各 provider 的透传选项。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [kind, providerOptions];
}

/// prompt 侧工具调用。仅出现在 assistant 消息中。
///
/// 注意：这里 [input] 是**已解析的 JSON 对象**（[JsonValue]），
/// 与输出/流侧 `ToolCall.input`（stringified JSON 字符串）刻意不对称。
final class ToolCallPart with EquatableMixin implements AssistantContentPart {
  const ToolCallPart({
    required this.toolCallId,
    required this.toolName,
    required this.input,
    this.providerExecuted,
    this.providerOptions,
  });

  /// 工具调用 id，用于与结果配对。
  final String toolCallId;

  /// 被调用工具名。
  final String toolName;

  /// 已解析的调用入参。
  final JsonValue input;

  /// 是否由 provider 侧直接执行（而非本地工具循环）。
  final bool? providerExecuted;

  /// 各 provider 的透传选项。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props =>
      [toolCallId, toolName, input, providerExecuted, providerOptions];
}

/// 工具审批请求片段。仅出现在 assistant 消息中。
final class ToolApprovalRequestPart
    with EquatableMixin
    implements AssistantContentPart {
  const ToolApprovalRequestPart({
    required this.approvalId,
    required this.toolCallId,
    this.providerOptions,
  });

  /// 审批请求 id。
  final String approvalId;

  /// 关联的工具调用 id。
  final String toolCallId;

  /// 各 provider 的透传选项。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [approvalId, toolCallId, providerOptions];
}

/// 工具执行结果片段。既可出现在 assistant 消息，也可出现在 tool 消息。
final class ToolResultPart
    with EquatableMixin
    implements AssistantContentPart, ToolContentPart {
  const ToolResultPart({
    required this.toolCallId,
    required this.toolName,
    required this.output,
    this.providerOptions,
  });

  /// 对应 [ToolCallPart.toolCallId]。
  final String toolCallId;

  /// 工具名。
  final String toolName;

  /// 结果输出载体（文本/JSON/错误/内容等变体）。
  final ToolResultOutput output;

  /// 各 provider 的透传选项。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [toolCallId, toolName, output, providerOptions];
}

/// 工具审批回复片段。回传在 tool 消息中，仅出现在 tool 角色。
final class ToolApprovalResponsePart
    with EquatableMixin
    implements ToolContentPart {
  const ToolApprovalResponsePart({
    required this.approvalId,
    required this.approved,
    this.reason,
    this.providerOptions,
  });

  /// 审批请求 id。
  final String approvalId;

  /// 是否批准执行。
  final bool approved;

  /// 可选的批准/拒绝原因。
  final String? reason;

  /// 各 provider 的透传选项。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [approvalId, approved, reason, providerOptions];
}
