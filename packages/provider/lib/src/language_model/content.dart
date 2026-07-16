part of 'language_model_events.dart';

/// 文本内容项(仅 doGenerate 聚合输出)。
///
/// **不**属于 [LanguageModelStreamPart]:流侧文本由 id 关联的
/// [TextStart]/[TextDelta]/[TextEnd] 表达;若允许无 id、无闭合边界的聚合文本
/// 进流,消费者无法可靠定位/闭合,会导致流文本丢失或错序。
final class TextContent extends LanguageModelContent with EquatableMixin {
  /// 创建一段文本内容。
  const TextContent(this.text, {this.providerMetadata});

  /// 文本正文。
  final String text;

  /// 该内容项携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [text, providerMetadata];
}

/// 推理(reasoning / thinking)内容项(仅 doGenerate 聚合输出)。
///
/// **不**属于 [LanguageModelStreamPart]:流侧推理由 id 关联的
/// [ReasoningStart]/[ReasoningDelta]/[ReasoningEnd] 表达,理由同 [TextContent]。
final class ReasoningContent extends LanguageModelContent with EquatableMixin {
  /// 创建一段推理内容。
  const ReasoningContent(this.text, {this.providerMetadata});

  /// 推理正文。
  final String text;

  /// 该内容项携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [text, providerMetadata];
}

/// 输出/流侧工具调用。
///
/// 注意:此处 [input] 是 **stringified JSON**(与 prompt 侧
/// `ToolCallPart.input` 的已解析 `JsonValue` 不对称),忠实照搬上游口径。
final class ToolCall extends LanguageModelContent
    with EquatableMixin
    implements LanguageModelStreamPart {
  /// 创建一次工具调用。
  const ToolCall({
    required this.toolCallId,
    required this.toolName,
    required this.input,
    this.providerExecuted,
    this.isDynamic,
    this.providerMetadata,
  });

  /// 工具调用 id(关联后续结果/审批)。
  final String toolCallId;

  /// 被调用的工具名。
  final String toolName;

  /// 工具入参的 **stringified JSON**。
  final String input;

  /// 是否由 provider 侧直接执行。
  final bool? providerExecuted;

  /// 是否为动态(MCP)工具。
  final bool? isDynamic;

  /// 该内容项携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [
        toolCallId,
        toolName,
        input,
        providerExecuted,
        isDynamic,
        providerMetadata,
      ];
}

/// provider 执行工具的结果。
///
/// [preliminary] 为真表示这是可被后续结果替换的部分结果。
final class ToolResult extends LanguageModelContent
    with EquatableMixin
    implements LanguageModelStreamPart {
  /// 创建一条工具结果。
  const ToolResult({
    required this.toolCallId,
    required this.toolName,
    required this.result,
    this.isError,
    this.preliminary,
    this.isDynamic,
    this.providerMetadata,
  });

  /// 关联的工具调用 id。
  final String toolCallId;

  /// 产生该结果的工具名。
  final String toolName;

  /// 工具结果(JSON 值,可为 `null`——对齐 v7:`JSONValue` 含 null,工具
  /// 合法地可以产出 null 结果,不得被规范化/替换)。
  final Object? result;

  /// 结果是否表示错误。
  final bool? isError;

  /// 是否为可被替换的部分结果。
  final bool? preliminary;

  /// 是否为动态(MCP)工具。
  final bool? isDynamic;

  /// 该内容项携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [
        toolCallId,
        toolName,
        result,
        isError,
        preliminary,
        isDynamic,
        providerMetadata,
      ];
}

/// 工具审批请求(v7 新增)。
final class ToolApprovalRequest extends LanguageModelContent
    with EquatableMixin
    implements LanguageModelStreamPart {
  /// 创建一条审批请求。
  const ToolApprovalRequest({
    required this.approvalId,
    required this.toolCallId,
    this.providerMetadata,
  });

  /// 审批 id(回复时据此匹配)。
  final String approvalId;

  /// 关联的工具调用 id。
  final String toolCallId;

  /// 该内容项携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [approvalId, toolCallId, providerMetadata];
}

/// 来源引用内容项:URL 引用或文档引用两个变体。
final class SourceContent extends LanguageModelContent
    with EquatableMixin
    implements LanguageModelStreamPart {
  /// URL 来源:引用一个可访问链接。文档相关字段为空。
  const SourceContent.url({
    required this.id,
    required String this.url,
    this.title,
    this.providerMetadata,
  })  : sourceType = SourceType.url,
        mediaType = null,
        filename = null;

  /// 文档来源:引用一个带媒体类型与标题的文档。[url] 为空。
  const SourceContent.document({
    required this.id,
    required String this.mediaType,
    required String this.title,
    this.filename,
    this.providerMetadata,
  })  : sourceType = SourceType.document,
        url = null;

  /// 来源类型判别标记。
  final SourceType sourceType;

  /// 来源 id。
  final String id;

  /// URL 来源的链接;文档来源为空。
  final String? url;

  /// 文档来源的媒体类型;URL 来源为空。
  final String? mediaType;

  /// 来源标题。
  final String? title;

  /// 文档来源的文件名。
  final String? filename;

  /// 该内容项携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props =>
      [sourceType, id, url, mediaType, title, filename, providerMetadata];
}

/// 来源类型:URL 引用或文档引用(document 变体 v7 新增)。
enum SourceType {
  /// 引用一个可访问的 URL。
  url,

  /// 引用一个文档(带媒体类型与标题)。
  document,
}

/// 文件内容项。
final class FileContent extends LanguageModelContent
    with EquatableMixin
    implements LanguageModelStreamPart {
  /// 创建一个文件内容项。
  const FileContent({
    required this.data,
    required this.mediaType,
    this.providerMetadata,
  });

  /// 文件数据(输出侧子集:字节 / base64 / URL)。
  final OutputFileData data;

  /// 文件媒体类型。
  final String mediaType;

  /// 该内容项携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [data, mediaType, providerMetadata];
}

/// 推理产物文件内容项。
final class ReasoningFileContent extends LanguageModelContent
    with EquatableMixin
    implements LanguageModelStreamPart {
  /// 创建一个推理文件内容项。
  const ReasoningFileContent({
    required this.data,
    required this.mediaType,
    this.providerMetadata,
  });

  /// 推理文件数据(输出侧子集:字节 / base64 / URL)。
  final OutputFileData data;

  /// 文件媒体类型。
  final String mediaType;

  /// 该内容项携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [data, mediaType, providerMetadata];
}

/// 自定义内容块。[kind] 形如 "ns.name"。
final class CustomContentBlock extends LanguageModelContent
    with EquatableMixin
    implements LanguageModelStreamPart {
  /// 创建一个自定义内容块。
  const CustomContentBlock(this.kind, {this.providerMetadata});

  /// 内容块类型标识(形如 "ns.name")。
  final String kind;

  /// 该内容项携带的 provider 侧元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [kind, providerMetadata];
}
