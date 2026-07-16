import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../generate_text/generate_text.dart';
import '../generate_text/active_tools.dart';
import '../generate_text/context.dart';
import '../generate_text/lifecycle_events.dart';
import '../generate_text/prepare_step.dart';
import '../generate_text/step_result.dart';
import '../generate_text/stream_text.dart';
import '../generate_text/tool_call_repair.dart';
import '../generate_text/tool_order.dart';
import '../prompt/model_message.dart';
import '../tool/tool.dart';

/// 可生成或流式生成多步结果的 Agent 契约。
abstract interface class Agent<Complete, Partial, Element> {
  /// Agent 契约版本。
  String get version;

  /// Agent 标识,便于调用方区分多个 Agent。
  String? get id;

  /// Agent 默认可用工具。
  ToolSet? get tools;

  /// 非流式运行 Agent。
  Future<GenerateTextResult<Complete>> generate({
    String? prompt,
    List<ModelMessage>? messages,
    provider.ToolChoice? toolChoice,
    int? maxOutputTokens,
    double? temperature,
    double? topP,
    double? topK,
    double? presencePenalty,
    double? frequencyPenalty,
    int? seed,
    List<String>? stopSequences,
    provider.ReasoningEffort? reasoning,
    Object? stopWhen,
    provider.CancellationSignal? cancellation,
    Map<String, String>? headers,
    provider.ProviderOptions? providerOptions,
    RuntimeContext? runtimeContext,
    ToolsContext? toolsContext,
    ActiveTools? activeTools,
    ToolOrder? toolOrder,
    PrepareStepFunction? prepareStep,
    Object? toolApproval,
    ToolCallRepairFunction? repairToolCall,
    GenerateTextOnStartCallback? onStart,
    GenerateTextOnStepStartCallback? onStepStart,
    void Function(StepResult step)? onStepEnd,
    GenerateTextOnEndCallback? onEnd,
  });

  /// 流式运行 Agent。
  StreamTextResult<Complete, Partial, Element> stream({
    String? prompt,
    List<ModelMessage>? messages,
    provider.ToolChoice? toolChoice,
    int? maxOutputTokens,
    double? temperature,
    double? topP,
    double? topK,
    double? presencePenalty,
    double? frequencyPenalty,
    int? seed,
    List<String>? stopSequences,
    provider.ReasoningEffort? reasoning,
    Object? stopWhen,
    provider.CancellationSignal? cancellation,
    Map<String, String>? headers,
    provider.ProviderOptions? providerOptions,
    RuntimeContext? runtimeContext,
    ToolsContext? toolsContext,
    ActiveTools? activeTools,
    ToolOrder? toolOrder,
    PrepareStepFunction? prepareStep,
    Object? toolApproval,
    ToolCallRepairFunction? repairToolCall,
    StreamTextInclude? include,
    GenerateTextOnStartCallback? onStart,
    GenerateTextOnStepStartCallback? onStepStart,
    void Function(StepResult step)? onStepEnd,
    GenerateTextOnEndCallback? onEnd,
    void Function(Object? error)? onError,
  });
}
