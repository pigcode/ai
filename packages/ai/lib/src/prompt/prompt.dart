import 'package:equatable/equatable.dart';

import 'model_message.dart';

/// 指令文本的类型别名(脊柱阶段仅支持纯字符串;上游还支持
/// `SystemModelMessage` 或其数组形式,延后到后续版本支持)。
typedef Instructions = String;

/// 顶层 prompt 输入:承载调用方传入的 `prompt`/`messages`/`instructions`
/// 三个可选字段,作为归一化前的原始载体。
///
/// `prompt` 与 `messages` 是二选一关系(字符串捷径 vs 完整消息列表);
/// 但这一约束在类型层不强制——两者同时为空或同时非空在构造时都合法,
/// 真正的“恰好一个非空”校验发生在 `standardizePrompt`(见
/// `prompt/standardize_prompt.dart`,非本文件职责)。
final class Prompt extends Equatable {
  /// 构造一个顶层 prompt 输入,所有字段均可选。
  const Prompt({this.prompt, this.messages, this.instructions});

  /// 字符串捷径形式的 prompt,归一化后对应单条 user 消息。
  final String? prompt;

  /// 完整消息列表形式的 prompt。
  final List<ModelMessage>? messages;

  /// 系统级指令文本。
  final Instructions? instructions;

  @override
  List<Object?> get props => [prompt, messages, instructions];
}
