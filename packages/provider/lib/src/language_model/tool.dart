import 'package:equatable/equatable.dart';

import '../json_value/json.dart';
import '../shared/shared.dart';

/// 语言模型工具(判别联合):函数工具或 provider 内置工具。
sealed class LanguageModelTool extends Equatable {
  const LanguageModelTool();
}

/// 函数工具:由核心执行的可调用工具,input 由 JSON Schema 描述。
final class FunctionTool extends LanguageModelTool {
  const FunctionTool({
    required this.name,
    this.description,
    required this.inputSchema,
    this.inputExamples,
    this.strict,
    this.providerOptions,
  });

  /// 工具名(模型可见)。
  final String name;

  /// 工具用途描述(可空)。
  final String? description;

  /// 入参 JSON Schema。
  final JsonSchema inputSchema;

  /// 入参示例(few-shot 提示,v7 新增)。
  final List<JsonObject>? inputExamples;

  /// 是否要求严格 schema 校验(v7 新增)。
  final bool? strict;

  /// provider 私有选项。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => <Object?>[
        name,
        description,
        inputSchema,
        inputExamples,
        strict,
        providerOptions,
      ];
}

/// provider/native 工具定义(上游 "provider-defined");执行位置由具体
/// provider/tool 语义决定(server 侧如 web_search,或客户端如 computer)。
final class ProviderTool extends LanguageModelTool {
  const ProviderTool({
    required this.id,
    required this.name,
    required this.args,
    this.supportsDeferredResults = false,
  });

  /// 工具标识,形如 "ns.name"。
  final String id;

  /// 工具名。
  final String name;

  /// 工具配置参数。
  final Map<String, Object?> args;

  /// 该 provider 执行工具是否支持 deferred 结果:providerExecuted 调用的
  /// 结果可能不在同轮响应返回(programmatic tool calling:server 工具触发
  /// client 工具,server 结果延后到 client 结果回传之后,:295-319)。
  ///
  /// 仅核心工具循环消费(pendingDeferredToolCalls 续接判定);wire 适配器
  /// 按 id/name/args 组装请求体,**不得**序列化或发送该字段。
  final bool supportsDeferredResults;

  @override
  List<Object?> get props => <Object?>[id, name, args, supportsDeferredResults];
}

/// 工具选择策略(判别联合)。
sealed class ToolChoice extends Equatable {
  const ToolChoice();
}

/// 由模型自行决定是否调用工具。
final class ToolChoiceAuto extends ToolChoice {
  const ToolChoiceAuto();

  @override
  List<Object?> get props => const <Object?>[];
}

/// 禁止调用任何工具。
final class ToolChoiceNone extends ToolChoice {
  const ToolChoiceNone();

  @override
  List<Object?> get props => const <Object?>[];
}

/// 要求至少调用一个工具。
final class ToolChoiceRequired extends ToolChoice {
  const ToolChoiceRequired();

  @override
  List<Object?> get props => const <Object?>[];
}

/// 强制调用指定名称的工具。
final class ToolChoiceTool extends ToolChoice {
  const ToolChoiceTool(this.toolName);

  /// 目标工具名。
  final String toolName;

  @override
  List<Object?> get props => <Object?>[toolName];
}

/// 工具结果输出(判别联合)。execution-denied 为 v7 审批新增。
sealed class ToolResultOutput extends Equatable {
  const ToolResultOutput();
}

/// 纯文本结果。
final class ToolResultText extends ToolResultOutput {
  const ToolResultText(this.value, {this.providerOptions});

  /// 文本内容。
  final String value;

  /// provider 专属选项(可空):随工具结果透传给 provider 适配器。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => <Object?>[value, providerOptions];
}

/// JSON 结果(已解析值)。
final class ToolResultJson extends ToolResultOutput {
  const ToolResultJson(this.value, {this.providerOptions});

  /// JSON 值。
  final JsonValue value;

  /// provider 专属选项(可空)。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => <Object?>[value, providerOptions];
}

/// 审批拒绝执行(v7 审批新增)。
final class ToolResultExecutionDenied extends ToolResultOutput {
  const ToolResultExecutionDenied({this.reason, this.providerOptions});

  /// 拒绝原因(可空)。
  final String? reason;

  /// provider 专属选项(可空)。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => <Object?>[reason, providerOptions];
}

/// 错误文本结果。
final class ToolResultErrorText extends ToolResultOutput {
  const ToolResultErrorText(this.value, {this.providerOptions});

  /// 错误文本。
  final String value;

  /// provider 专属选项(可空)。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => <Object?>[value, providerOptions];
}

/// 错误 JSON 结果。
final class ToolResultErrorJson extends ToolResultOutput {
  const ToolResultErrorJson(this.value, {this.providerOptions});

  /// 错误 JSON 值。
  final JsonValue value;

  /// provider 专属选项(可空)。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => <Object?>[value, providerOptions];
}

/// 多媒体内容结果(文本 + 文件项列表)。
final class ToolResultContentOutput extends ToolResultOutput {
  const ToolResultContentOutput(this.items);

  /// 内容项列表。
  final List<ToolResultContentItem> items;

  @override
  List<Object?> get props => <Object?>[items];
}

/// 工具结果内容项(判别联合)。
sealed class ToolResultContentItem extends Equatable {
  const ToolResultContentItem();
}

/// 文本内容项。
final class ToolResultTextItem extends ToolResultContentItem {
  const ToolResultTextItem(this.text, {this.providerOptions});

  /// 文本内容。
  final String text;

  /// provider 专属选项(可空)。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => <Object?>[text, providerOptions];
}

/// 文件内容项。
final class ToolResultFileItem extends ToolResultContentItem {
  const ToolResultFileItem({
    required this.data,
    required this.mediaType,
    this.filename,
    this.providerOptions,
  });

  /// 文件数据。
  final FileData data;

  /// 媒体类型。
  final String mediaType;

  /// 文件名(可空)。
  final String? filename;

  /// provider 专属选项(可空)。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props =>
      <Object?>[data, mediaType, filename, providerOptions];
}

/// 自定义内容项(v7 provider 专属逃生口):仅承载 providerOptions,供适配器透传
/// provider 私有的工具结果负载,不必丢弃或错误编码。
final class ToolResultCustomItem extends ToolResultContentItem {
  const ToolResultCustomItem({this.providerOptions});

  /// provider 专属选项(承载自定义负载)。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => <Object?>[providerOptions];
}
