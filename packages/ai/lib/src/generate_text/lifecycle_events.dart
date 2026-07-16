import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../prompt/from_language_model_prompt.dart';
import '../prompt/model_message.dart';
import '../prompt/to_language_model_prompt.dart';
import 'step_result.dart';

/// [generateText]/[streamText] 开始时触发的事件。
final class GenerateTextStartEvent {
  GenerateTextStartEvent({
    required this.model,
    required List<ModelMessage> messages,
  }) : messages = _snapshotMessages(messages);

  /// 本次调用使用的默认模型。
  final provider.LanguageModel model;

  /// 标准化后的初始用户面消息,不含系统指令。
  final List<ModelMessage> messages;
}

/// 每步模型调用开始前触发的事件。
final class GenerateTextStepStartEvent {
  GenerateTextStepStartEvent({
    required this.stepNumber,
    required this.model,
    required List<ModelMessage> messages,
    required List<StepResult> steps,
  })  : messages = _snapshotMessages(messages),
        steps = List<StepResult>.unmodifiable(steps);

  /// 即将执行的步骤序号,从 0 开始。
  final int stepNumber;

  /// 当前步骤使用的模型。
  final provider.LanguageModel model;

  /// 当前步骤将发送给模型的用户面消息快照。
  final List<ModelMessage> messages;

  /// 当前步骤之前已经完成的步骤快照。
  final List<StepResult> steps;
}

/// 所有步骤完成后触发的事件。
final class GenerateTextEndEvent {
  GenerateTextEndEvent({required List<StepResult> steps})
      : steps = List<StepResult>.unmodifiable(steps);

  /// 全部步骤结果。
  final List<StepResult> steps;

  /// 最后一步。
  StepResult get finalStep => steps.last;

  /// 最后一步文本。
  String get text => finalStep.text;

  /// 所有步骤生成的内容项。
  List<provider.LanguageModelContent> get content =>
      steps.expand((step) => step.content).toList(growable: false);

  /// 所有步骤生成的文件内容项。
  List<provider.FileContent> get files =>
      steps.expand((step) => step.files).toList(growable: false);

  /// 所有步骤生成的来源引用内容项。
  List<provider.SourceContent> get sources =>
      steps.expand((step) => step.sources).toList(growable: false);

  /// 所有步骤模型发起的工具调用。
  List<provider.ToolCall> get toolCalls =>
      steps.expand((step) => step.toolCalls).toList(growable: false);

  /// 所有步骤执行出的工具结果。
  List<provider.ToolResult> get toolResults =>
      steps.expand((step) => step.toolResults).toList(growable: false);

  /// 最终终止原因。
  provider.LanguageModelFinishReason get finishReason => finalStep.finishReason;

  /// 跨全部步骤累加的 token 用量。
  provider.LanguageModelUsage get usage {
    var hasInputTotal = false;
    var hasOutputTotal = false;
    var inputTotal = 0;
    var outputTotal = 0;
    for (final step in steps) {
      final input = step.usage.inputTokens.total;
      final output = step.usage.outputTokens.total;
      if (input != null) {
        hasInputTotal = true;
        inputTotal += input;
      }
      if (output != null) {
        hasOutputTotal = true;
        outputTotal += output;
      }
    }
    return provider.LanguageModelUsage(
      inputTokens:
          provider.InputTokens(total: hasInputTotal ? inputTotal : null),
      outputTokens:
          provider.OutputTokens(total: hasOutputTotal ? outputTotal : null),
    );
  }

  /// 所有步骤的 provider 侧告警。
  List<provider.Warning> get warnings =>
      steps.expand((step) => step.warnings).toList(growable: false);
}

/// [GenerateTextStartEvent] 回调。
typedef GenerateTextOnStartCallback = void Function(
  GenerateTextStartEvent event,
);

/// [GenerateTextStepStartEvent] 回调。
typedef GenerateTextOnStepStartCallback = void Function(
  GenerateTextStepStartEvent event,
);

/// [GenerateTextEndEvent] 回调。
typedef GenerateTextOnEndCallback = void Function(GenerateTextEndEvent event);

List<ModelMessage> _snapshotMessages(List<ModelMessage> messages) {
  return convertFromLanguageModelPrompt(
    convertModelMessagesToLanguageModelPrompt(messages),
  );
}
