import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../prompt/model_message.dart';
import '../tool/tool.dart';

/// 修复模型返回的工具调用。
///
/// 返回新的 [provider.ToolCall] 表示使用修复后的调用继续执行;返回 `null`
/// 表示放弃修复,沿用原始错误路径。
typedef ToolCallRepairFunction = FutureOr<provider.ToolCall?> Function(
  ToolCallRepairOptions options,
);

/// [ToolCallRepairFunction] 的调用上下文。
///
/// 只提供当前 API 面的字段:[instructions]、用户面 [messages]、原始
/// [toolCall]、当前可用 [tools]、按工具名取 schema 的 [inputSchema] 与
/// 触发修复的 [error]。不提供上游已废弃的 `system` 别名。
final class ToolCallRepairOptions {
  /// 创建工具调用修复上下文。
  ToolCallRepairOptions({
    required List<ModelMessage> messages,
    required this.toolCall,
    required this.tools,
    required this.inputSchema,
    required this.error,
    this.instructions,
  }) : messages = List<ModelMessage>.unmodifiable(messages);

  /// 本次请求的顶层指令。
  final String? instructions;

  /// 触发本次工具调用前的用户面消息,不含系统消息。
  final List<ModelMessage> messages;

  /// 模型返回的原始工具调用。
  final provider.ToolCall toolCall;

  /// 当前步骤可用的工具集合。
  final ToolSet tools;

  /// 按工具名获取当前工具的输入 schema。
  final provider.JsonSchema Function({required String toolName}) inputSchema;

  /// 触发修复的解析/匹配错误。
  final ToolCallRepairFailure error;
}

/// 工具调用修复相关错误的基类。
sealed class ToolCallRepairFailure implements Exception {
  /// 创建工具调用修复错误。
  const ToolCallRepairFailure(this.message, {this.cause});

  /// 面向人类的错误描述。
  final String message;

  /// 底层原因。
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (cause != null) {
      buffer.write(' (cause: $cause)');
    }
    return buffer.toString();
  }
}

/// 模型请求了当前步骤不存在的工具。
final class NoSuchToolError extends ToolCallRepairFailure {
  /// 创建未知工具错误。
  NoSuchToolError({
    required this.toolName,
    required List<String> availableTools,
    String? message,
    Object? cause,
  })  : availableTools = List<String>.unmodifiable(availableTools),
        super(
          message ??
              'No such tool: $toolName '
                  '(available tools: ${availableTools.join(', ')})',
          cause: cause,
        );

  /// 模型请求的工具名。
  final String toolName;

  /// 当前步骤可用工具名。
  final List<String> availableTools;
}

/// 工具输入 JSON 解析或 schema 校验失败。
final class InvalidToolInputError extends ToolCallRepairFailure {
  /// 创建无效工具输入错误。
  const InvalidToolInputError({
    required this.toolName,
    required this.toolInput,
    required Object cause,
    String? message,
  }) : super(
          message ?? 'Invalid input for tool: $toolName',
          cause: cause,
        );

  /// 工具名。
  final String toolName;

  /// 原始 stringified JSON 输入。
  final String toolInput;
}

/// 修复回调自身抛错。
final class ToolCallRepairError extends ToolCallRepairFailure {
  /// 创建修复回调错误。
  const ToolCallRepairError({
    required this.originalError,
    required Object cause,
    String? message,
  }) : super(
          message ?? 'Tool call repair failed',
          cause: cause,
        );

  /// 触发修复的原始错误。
  final ToolCallRepairFailure originalError;
}
