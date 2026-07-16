/// 用户面 content part 类型(pigcode_ai 自有,不与契约层同名类型冲突——通过前缀 import 区分)。
///
/// 对齐 v7 `@ai-sdk/provider-utils/content-part.ts` 的设计：用户面 part 与
/// provider 面 part 是两套独立类型，之间存在显式转换（见 `prompt/` 目录）。
library;

import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:equatable/equatable.dart';

/// 角色标记接口：允许出现在 [UserModelMessage] content 中的 part 类型实现它。
///
/// 把 part 放进不允许的角色列表（如把 [ReasoningPart] 放进
/// `List<UserContentPart>`）会在编译期报错，从而在类型层面约束 prompt 结构。
sealed class UserContentPart {}

/// 允许出现在 [AssistantModelMessage] content 中的 part 类型标记接口。
sealed class AssistantContentPart {}

/// 允许出现在 [ToolModelMessage] content 中的 part 类型标记接口。
sealed class ToolContentPart {}

/// 纯文本片段。可出现在 user 与 assistant 消息中。
final class TextPart
    with EquatableMixin
    implements UserContentPart, AssistantContentPart {
  const TextPart(this.text, {this.providerOptions});

  /// 文本内容。
  final String text;

  /// 各 provider 的透传选项，外层键为 provider 名。
  final provider.ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [text, providerOptions];
}

/// 文件片段（图片/文档等）。可出现在 user 与 assistant 消息中。
///
/// [data] 是用户面宽松数据载体（[DataContent]），转换层（`prompt/`）会将其
/// 归一到契约 `provider.FileData`。
final class FilePart
    with EquatableMixin
    implements UserContentPart, AssistantContentPart {
  const FilePart({
    required this.data,
    required this.mediaType,
    this.filename,
    this.providerOptions,
  });

  /// 用户面文件数据载体。
  final DataContent data;

  /// IANA 媒体类型，如 `image/png`。
  final String mediaType;

  /// 可选的原始文件名。
  final String? filename;

  /// 各 provider 的透传选项。
  final provider.ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [data, mediaType, filename, providerOptions];
}

/// 模型推理（思维链）文本片段。仅出现在 assistant 消息中。
final class ReasoningPart with EquatableMixin implements AssistantContentPart {
  const ReasoningPart(this.text, {this.providerOptions});

  /// 推理文本内容。
  final String text;

  /// 各 provider 的透传选项。
  final provider.ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [text, providerOptions];
}

/// 以文件形式承载的推理内容。仅出现在 assistant 消息中。
///
/// [data] 是用户面宽松数据载体（[DataContent]），转换层（`prompt/`）会将其
/// 归一到契约 `provider.FileData`。
final class ReasoningFilePart
    with EquatableMixin
    implements AssistantContentPart {
  const ReasoningFilePart({
    required this.data,
    required this.mediaType,
    this.providerOptions,
  });

  /// 用户面推理文件数据载体。
  final DataContent data;

  /// IANA 媒体类型。
  final String mediaType;

  /// 各 provider 的透传选项。
  final provider.ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [data, mediaType, providerOptions];
}

/// provider 自定义内容片段。仅出现在 assistant 消息中。
final class CustomPart with EquatableMixin implements AssistantContentPart {
  const CustomPart(this.kind, {this.providerOptions});

  /// 自定义种类，形如 `ns.name`。
  final String kind;

  /// 各 provider 的透传选项。
  final provider.ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [kind, providerOptions];
}

/// 用户面工具调用片段。仅出现在 assistant 消息中。
///
/// 与契约层 `provider.ToolCallPart` 一致：[input] 是**已解析的 JSON 对象**
/// （[provider.JsonValue]），而非字符串化 JSON。
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
  final provider.JsonValue input;

  /// 是否由 provider 侧直接执行（而非本地工具循环）。
  final bool? providerExecuted;

  /// 各 provider 的透传选项。
  final provider.ProviderOptions? providerOptions;

  @override
  List<Object?> get props =>
      [toolCallId, toolName, input, providerExecuted, providerOptions];
}

/// 用户面工具审批请求片段。仅出现在 assistant 消息中。
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
  final provider.ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [approvalId, toolCallId, providerOptions];
}

/// 用户面工具执行结果片段。既可出现在 assistant 消息，也可出现在 tool 消息。
///
/// [output] 直接复用契约 [provider.ToolResultOutput]（文本/JSON/错误/内容等变体）。
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

  /// 结果输出载体。
  final provider.ToolResultOutput output;

  /// 各 provider 的透传选项。
  final provider.ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [toolCallId, toolName, output, providerOptions];
}

/// 用户面工具审批回复片段。仅出现在 tool 消息中。
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
  final provider.ProviderOptions? providerOptions;

  @override
  List<Object?> get props => [approvalId, approved, reason, providerOptions];
}

/// 用户面宽松文件数据载体（v7 `DataContent | URL | ProviderReference`）。
///
/// 转换层（[convertToLanguageModelPrompt]）会将其归一到契约
/// `provider.FileData` 的对应变体。
///
/// **约定:叶子载荷视为不可变**——转换按引用透传可变叶子（[DataBytes.bytes]
/// 的 [Uint8List]、[DataProviderRef.reference]),不做深拷贝(与 v7 一致——v7
/// 亦按引用透传二进制、不克隆)。调用方一旦把 [DataContent] 传入
/// `generateText`/`streamText`,就不得再改动其字节/引用,否则可能影响本次调用
/// 已转换出的 provider prompt。需要复用缓冲区的调用方应自行传入副本。
sealed class DataContent {
  const DataContent();
}

/// 原始字节数据。
final class DataBytes extends DataContent with EquatableMixin {
  const DataBytes(this.bytes);

  /// 文件的原始字节内容。
  final Uint8List bytes;

  @override
  List<Object?> get props => [bytes];
}

/// base64 编码的字符串数据。
final class DataBase64 extends DataContent with EquatableMixin {
  const DataBase64(this.base64);

  /// base64 编码后的字符串。
  final String base64;

  @override
  List<Object?> get props => [base64];
}

/// 内联文本文件内容。
final class DataText extends DataContent with EquatableMixin {
  const DataText(this.text);

  /// 文件的纯文本内容。
  final String text;

  @override
  List<Object?> get props => [text];
}

/// 远程或 data URL。
final class DataUrl extends DataContent with EquatableMixin {
  const DataUrl(this.url);

  /// 文件的 URL（含 `data:` scheme 或远程 URL）。
  final Uri url;

  @override
  List<Object?> get props => [url];
}

/// provider 侧已上传资源的引用。
final class DataProviderRef extends DataContent with EquatableMixin {
  const DataProviderRef(this.reference);

  /// provider 侧资源引用。
  final provider.ProviderReference reference;

  @override
  List<Object?> get props => [reference];
}
