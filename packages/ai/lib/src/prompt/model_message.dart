import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:equatable/equatable.dart';

import 'content_part.dart';

/// pigcode_ai 用户面的模型消息:按角色分为 system/user/assistant/tool 四种。
///
/// `providerOptions` 复用契约层的 [provider.ProviderOptions] primitive,
/// 供各 provider 透传自定义选项;不参与角色区分。
sealed class ModelMessage extends Equatable {
  const ModelMessage({this.providerOptions});

  /// provider 私有选项透传(外层键为 provider 名)。
  final provider.ProviderOptions? providerOptions;
}

/// 系统消息:内容恒为字符串(v7 的 `SystemModelMessage[]` instructions 形态延后)。
final class SystemModelMessage extends ModelMessage {
  const SystemModelMessage(this.content, {super.providerOptions});

  /// 系统提示文本。
  final String content;

  @override
  List<Object?> get props => <Object?>[content, providerOptions];
}

/// 用户消息:内容始终归一为 part 列表;`.text()` 提供字符串捷径。
final class UserModelMessage extends ModelMessage {
  const UserModelMessage(this.content, {super.providerOptions});

  /// 由单条文本构造用户消息的快捷工厂。
  factory UserModelMessage.text(
    String text, {
    provider.ProviderOptions? providerOptions,
  }) =>
      UserModelMessage(
        <UserContentPart>[TextPart(text)],
        providerOptions: providerOptions,
      );

  /// 用户面 content part 列表,见 `content_part.dart`。
  final List<UserContentPart> content;

  @override
  List<Object?> get props => <Object?>[content, providerOptions];
}

/// 助手消息:内容始终归一为 part 列表;`.text()` 提供字符串捷径。
final class AssistantModelMessage extends ModelMessage {
  const AssistantModelMessage(this.content, {super.providerOptions});

  /// 由单条文本构造助手消息的快捷工厂。
  factory AssistantModelMessage.text(
    String text, {
    provider.ProviderOptions? providerOptions,
  }) =>
      AssistantModelMessage(
        <AssistantContentPart>[TextPart(text)],
        providerOptions: providerOptions,
      );

  /// 助手面 content part 列表,见 `content_part.dart`。
  final List<AssistantContentPart> content;

  @override
  List<Object?> get props => <Object?>[content, providerOptions];
}

/// 工具消息:承载工具执行结果与工具审批回复,供多步工具循环回填给模型。
final class ToolModelMessage extends ModelMessage {
  const ToolModelMessage(this.content, {super.providerOptions});

  /// 工具面 content part 列表,见 `content_part.dart`。
  final List<ToolContentPart> content;

  @override
  List<Object?> get props => <Object?>[content, providerOptions];
}
