import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import 'model_message.dart';

/// [standardizePrompt] 的归一化结果：`instructions` 与非空 `messages` 列表。
final class StandardizedPrompt {
  const StandardizedPrompt(
      {required this.instructions, required this.messages});

  /// 归一后的系统级指令。
  final String? instructions;

  /// 归一后的消息列表，保证非空且不含 system 消息。
  final List<ModelMessage> messages;
}

/// 将 `prompt`/`messages` 二选一输入 + `instructions` 归一为
/// [StandardizedPrompt]。
///
/// 规则：
/// - `prompt` 与 `messages` 必须恰好提供一个，否则抛 [provider.InvalidPromptError]。
/// - 字符串 `prompt` 归一为单条 `UserModelMessage.text(prompt)`。
/// - `messages` 必须非空，且不允许出现 [SystemModelMessage]
///   （脊柱阶段恒禁止；`allowSystemInMessages` 留待后续扩展）。
StandardizedPrompt standardizePrompt({
  String? prompt,
  List<ModelMessage>? messages,
  String? instructions,
}) {
  if ((prompt == null) == (messages == null)) {
    throw provider.InvalidPromptError(
      prompt: prompt ?? messages,
      message: 'prompt and messages are mutually exclusive; '
          'exactly one of them must be provided.',
    );
  }

  if (prompt != null) {
    return StandardizedPrompt(
      instructions: instructions,
      messages: <ModelMessage>[UserModelMessage.text(prompt)],
    );
  }

  final resolvedMessages = messages!;
  if (resolvedMessages.isEmpty) {
    throw const provider.InvalidPromptError(
      prompt: <ModelMessage>[],
      message: 'messages must not be empty.',
    );
  }
  if (resolvedMessages.any((message) => message is SystemModelMessage)) {
    throw provider.InvalidPromptError(
      prompt: resolvedMessages,
      message: 'system messages are not allowed inside messages; '
          'use the system/instructions parameter instead.',
    );
  }

  return StandardizedPrompt(
    instructions: instructions,
    messages: resolvedMessages,
  );
}
