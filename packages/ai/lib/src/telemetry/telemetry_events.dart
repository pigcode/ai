import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:equatable/equatable.dart';

import '../prompt/model_message.dart';

/// 模型调用开始事件(telemetry)。在 provider `doGenerate` / `doStream` 之前触发,
/// 仅覆盖 model 侧,不含后续本地工具执行。
///
/// `providerId` = `LanguageModel.provider`、`modelId` = `LanguageModel.modelId`。
final class LanguageModelCallStartEvent extends Equatable {
  /// 创建模型调用开始事件。
  LanguageModelCallStartEvent({
    required this.callId,
    required this.providerId,
    required this.modelId,
    required this.stepNumber,
    required List<ModelMessage> messages,
  }) : messages = List<ModelMessage>.unmodifiable(messages);

  /// 本次模型调用的唯一标识,与对应 [LanguageModelCallEndEvent.callId] 配对。
  final String callId;

  /// provider 名(如 'openai')。
  final String providerId;

  /// 模型 id(如 'gpt-4o')。
  final String modelId;

  /// 步骤序号,从 0 开始。
  final int stepNumber;

  /// 发往模型的用户面消息(input 侧,受 recordInputs 脱敏)。
  final List<ModelMessage> messages;

  @override
  List<Object?> get props =>
      [callId, providerId, modelId, stepNumber, messages];
}

/// 模型调用结束事件(telemetry)。在模型响应规范化解析后、本地工具执行前触发。
///
/// 流式路径于"模型侧流读完"处派发(拿到 usage/finishReason/content/response 之后、
/// 工具执行之前),使工具执行错误路径上该事件已先于 rethrow 配对好。
final class LanguageModelCallEndEvent extends Equatable {
  /// 创建模型调用结束事件。
  LanguageModelCallEndEvent({
    required this.callId,
    required this.providerId,
    required this.modelId,
    required this.stepNumber,
    required List<provider.LanguageModelContent> content,
    required this.usage,
    required this.finishReason,
    required List<provider.Warning> warnings,
    required this.response,
    required this.responseTime,
  })  : content = List<provider.LanguageModelContent>.unmodifiable(content),
        warnings = List<provider.Warning>.unmodifiable(warnings);

  /// 与 [LanguageModelCallStartEvent.callId] 配对。
  final String callId;

  /// provider 名。
  final String providerId;

  /// 模型 id。
  final String modelId;

  /// 步骤序号。
  final int stepNumber;

  /// 模型产出的内容项(output 侧,受 recordOutputs 脱敏)。
  final List<provider.LanguageModelContent> content;

  /// 本次调用的 token 用量。
  final provider.LanguageModelUsage usage;

  /// 本次调用的终止原因。
  final provider.LanguageModelFinishReason finishReason;

  /// provider 侧告警。
  final List<provider.Warning> warnings;

  /// 响应元数据(含 responseId 等),可空。
  final provider.ResponseInfo? response;

  /// 模型响应耗时。
  final Duration responseTime;

  @override
  List<Object?> get props => [
        callId,
        providerId,
        modelId,
        stepNumber,
        content,
        usage,
        finishReason,
        warnings,
        response,
        responseTime,
      ];
}

/// 工具执行开始事件(telemetry)。在工具 `execute` 之前触发。
///
/// 刻意**不携带** `provider.ToolCall`——它内含 stringified `input`,若只脱敏
/// [input] 会从 `toolCall.input` 旁路泄露入参。此处只放 [toolCallId] / [toolName]
/// 与已解析的 [input] 单一入参出口,便于单点脱敏。
final class ToolExecutionStartEvent extends Equatable {
  /// 创建工具执行开始事件。
  const ToolExecutionStartEvent({
    required this.callId,
    required this.toolCallId,
    required this.toolName,
    required this.input,
    required this.toolContext,
  });

  /// 本次工具执行的唯一标识,与对应 [ToolExecutionEndEvent.callId] 配对。
  final String callId;

  /// 触发本次执行的工具调用 id。
  final String toolCallId;

  /// 工具名。
  final String toolName;

  /// 已解析的工具入参(受 recordInputs 脱敏)。
  final Object? input;

  /// 该工具的上下文(受 includeToolsContext 脱敏)。
  final Object? toolContext;

  @override
  List<Object?> get props => [callId, toolCallId, toolName, input, toolContext];
}

/// 工具执行结束事件(telemetry)。sealed 判别联合:成功走
/// [ToolExecutionEndSuccess](带 output),失败走 [ToolExecutionEndError](带 error);
/// 由子类类型区分。
sealed class ToolExecutionEndEvent extends Equatable {
  /// 创建工具执行结束事件基类。
  const ToolExecutionEndEvent({
    required this.callId,
    required this.toolCallId,
    required this.toolName,
    required this.toolExecutionMs,
  });

  /// 与 [ToolExecutionStartEvent.callId] 配对。
  final String callId;

  /// 触发本次执行的工具调用 id。
  final String toolCallId;

  /// 工具名。
  final String toolName;

  /// 工具执行耗时(毫秒)。
  final int toolExecutionMs;
}

/// 工具执行成功结束。
final class ToolExecutionEndSuccess extends ToolExecutionEndEvent {
  /// 创建成功结束事件。
  const ToolExecutionEndSuccess({
    required super.callId,
    required super.toolCallId,
    required super.toolName,
    required this.output,
    required super.toolExecutionMs,
  });

  /// 工具输出(受 recordOutputs 脱敏)。
  final Object? output;

  @override
  List<Object?> get props =>
      [callId, toolCallId, toolName, toolExecutionMs, output];
}

/// 工具执行失败结束。
final class ToolExecutionEndError extends ToolExecutionEndEvent {
  /// 创建失败结束事件。
  const ToolExecutionEndError({
    required super.callId,
    required super.toolCallId,
    required super.toolName,
    required this.error,
    required super.toolExecutionMs,
  });

  /// 工具执行抛出的错误。
  final Object? error;

  @override
  List<Object?> get props =>
      [callId, toolCallId, toolName, toolExecutionMs, error];
}
