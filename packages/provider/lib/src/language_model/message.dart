import 'package:equatable/equatable.dart';

import 'content_part.dart';
import '../shared/shared.dart';

/// 语言模型 prompt 中的一条消息(sealed 四角色)。
///
/// 忠实映射上游 prompt 消息:每条消息绑定一个固定角色(system / user /
/// assistant / tool),并可携带 provider 私有的 [providerOptions]。作为不可变
/// 值对象参与相等比较(见各子类的 [props]);内容列表由 `equatable` 深比较。
sealed class LanguageModelMessage with EquatableMixin {
  /// 常量构造,供各角色子类在 `const` 上下文向上委托。
  const LanguageModelMessage({this.providerOptions});

  /// provider 私有的消息级选项(外层键=provider 名)。
  final ProviderOptions? providerOptions;
}

/// 系统消息:纯字符串指令(非 parts)。
///
/// [content] 直接持有 [String],与其他角色的 parts 列表不同;其角色恒为 system。
final class SystemMessage extends LanguageModelMessage {
  /// 用系统指令文本构造一条系统消息。
  const SystemMessage(this.content, {super.providerOptions});

  /// 系统指令的纯文本内容。
  final String content;

  @override
  List<Object?> get props => [content, providerOptions];
}

/// 用户消息:承载 [UserContentPart] 列表(文本、文件等)。
final class UserMessage extends LanguageModelMessage {
  /// 用用户侧内容部件列表构造一条用户消息。
  const UserMessage(this.content, {super.providerOptions});

  /// 用户侧内容部件(角色标记接口约束合法成员)。
  final List<UserContentPart> content;

  @override
  List<Object?> get props => [content, providerOptions];
}

/// 助手消息:承载 [AssistantContentPart] 列表(文本、推理、工具调用等)。
final class AssistantMessage extends LanguageModelMessage {
  /// 用助手侧内容部件列表构造一条助手消息。
  const AssistantMessage(this.content, {super.providerOptions});

  /// 助手侧内容部件(角色标记接口约束合法成员)。
  final List<AssistantContentPart> content;

  @override
  List<Object?> get props => [content, providerOptions];
}

/// 工具消息:承载 [ToolContentPart] 列表(工具结果、审批回复等)。
final class ToolMessage extends LanguageModelMessage {
  /// 用工具侧内容部件列表构造一条工具消息。
  const ToolMessage(this.content, {super.providerOptions});

  /// 工具侧内容部件(角色标记接口约束合法成员)。
  final List<ToolContentPart> content;

  @override
  List<Object?> get props => [content, providerOptions];
}

/// 语言模型 prompt:按顺序排列的消息列表。
typedef LanguageModelPrompt = List<LanguageModelMessage>;
