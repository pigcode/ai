import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../prompt/model_message.dart';
import 'active_tools.dart';
import 'context.dart';
import 'request_options_snapshot.dart';
import 'step_result.dart';
import 'tool_order.dart';

/// 每步模型调用前的动态配置回调。
typedef PrepareStepFunction = FutureOr<PrepareStepResult?> Function(
  PrepareStepOptions options,
);

/// [PrepareStepFunction] 收到的当前循环上下文。
final class PrepareStepOptions {
  /// 创建 prepare-step 上下文。
  PrepareStepOptions({
    required List<StepResult> steps,
    required this.stepNumber,
    required this.model,
    required List<ModelMessage> messages,
    required List<ModelMessage> initialMessages,
    required List<ModelMessage> responseMessages,
    required RuntimeContext runtimeContext,
    required ToolsContext toolsContext,
  })  : steps = List<StepResult>.unmodifiable(steps),
        messages = List<ModelMessage>.unmodifiable(messages),
        initialMessages = List<ModelMessage>.unmodifiable(initialMessages),
        responseMessages = List<ModelMessage>.unmodifiable(responseMessages),
        runtimeContext = snapshotRuntimeContext(runtimeContext),
        toolsContext = snapshotToolsContext(toolsContext);

  /// 已经完成的步骤。
  final List<StepResult> steps;

  /// 即将执行的步骤序号,从 0 开始。
  final int stepNumber;

  /// 外层调用传入的默认模型。
  final provider.LanguageModel model;

  /// 当前步骤默认会发送给模型的消息。
  final List<ModelMessage> messages;

  /// 外层调用标准化后的初始消息。
  final List<ModelMessage> initialMessages;

  /// 已完成步骤累计产生的 assistant/tool 响应消息。
  final List<ModelMessage> responseMessages;

  /// 当前步骤使用的运行时上下文。
  final RuntimeContext runtimeContext;

  /// 当前步骤使用的按工具名索引的上下文。
  final ToolsContext toolsContext;
}

/// [PrepareStepFunction] 可返回的每步覆盖设置。
final class PrepareStepResult {
  /// 创建 prepare-step 覆盖结果。
  PrepareStepResult({
    this.model,
    this.toolChoice,
    ActiveTools? activeTools,
    ToolOrder? toolOrder,
    List<ModelMessage>? messages,
    RuntimeContext? runtimeContext,
    ToolsContext? toolsContext,
    this.providerOptions,
  })  : activeTools =
            activeTools == null ? null : List<String>.unmodifiable(activeTools),
        toolOrder =
            toolOrder == null ? null : List<String>.unmodifiable(toolOrder),
        messages =
            messages == null ? null : List<ModelMessage>.unmodifiable(messages),
        runtimeContext = runtimeContext == null
            ? null
            : snapshotRuntimeContext(runtimeContext),
        toolsContext =
            toolsContext == null ? null : snapshotToolsContext(toolsContext);

  /// 当前步骤使用的模型。未提供时使用外层模型。
  final provider.LanguageModel? model;

  /// 当前步骤使用的工具选择策略。未提供时使用外层 [provider.ToolChoice]。
  final provider.ToolChoice? toolChoice;

  /// 当前步骤启用的工具名列表。未提供时使用外层 activeTools。
  final ActiveTools? activeTools;

  /// 当前步骤的工具广告顺序。未提供时使用外层 toolOrder。
  final ToolOrder? toolOrder;

  /// 当前步骤发送给模型的完整消息列表。
  ///
  /// 返回该字段后,它会成为后续步骤继续追加 assistant/tool 响应消息的基础。
  final List<ModelMessage>? messages;

  /// 当前步骤之后继续使用的运行时上下文。
  final RuntimeContext? runtimeContext;

  /// 当前步骤之后继续使用的按工具名索引的上下文。
  final ToolsContext? toolsContext;

  /// 当前步骤额外的 provider 选项。与外层 providerOptions 按 provider key 合并。
  final provider.ProviderOptions? providerOptions;
}
