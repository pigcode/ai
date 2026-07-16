import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../generate_text/active_tools.dart';
import '../generate_text/context.dart';
import '../generate_text/generate_text.dart';
import '../generate_text/lifecycle_events.dart';
import '../generate_text/output.dart';
import '../generate_text/prepare_step.dart';
import '../generate_text/step_result.dart';
import '../generate_text/stop_condition.dart';
import '../generate_text/stream_text.dart';
import '../generate_text/tool_call_repair.dart';
import '../generate_text/tool_order.dart';
import '../middleware/default_settings_merge.dart';
import '../prompt/model_message.dart';
import '../tool/tool.dart';
import 'agent.dart';

/// 复用 [generateText] / `streamText` 工具循环的轻量 Agent。
final class ToolLoopAgent<Complete, Partial, Element>
    implements Agent<Complete, Partial, Element> {
  /// 创建一个工具循环 Agent。
  const ToolLoopAgent({
    this.id,
    required this.model,
    this.instructions,
    this.tools,
    this.toolChoice,
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.topK,
    this.presencePenalty,
    this.frequencyPenalty,
    this.seed,
    this.stopSequences,
    this.reasoning,
    this.output,
    this.stopWhen,
    this.headers,
    this.providerOptions,
    this.runtimeContext,
    this.toolsContext,
    this.activeTools,
    this.toolOrder,
    this.prepareStep,
    this.toolApproval,
    this.repairToolCall,
    this.include,
    this.onStart,
    this.onStepStart,
    this.onStepEnd,
    this.onEnd,
  });

  @override
  String get version => 'agent-v1';

  /// Agent 标识,便于调用方区分多个 Agent。
  @override
  final String? id;

  /// Agent 默认使用的语言模型。
  final provider.LanguageModel model;

  /// Agent 默认系统指令。
  final String? instructions;

  /// Agent 默认可用工具。
  @override
  final ToolSet? tools;

  /// Agent 默认工具选择策略。
  final provider.ToolChoice? toolChoice;

  /// Agent 默认最大输出 token 数。
  final int? maxOutputTokens;

  /// Agent 默认 temperature。
  final double? temperature;

  /// Agent 默认 top-p。
  final double? topP;

  /// Agent 默认 top-k。
  final double? topK;

  /// Agent 默认 presence penalty。
  final double? presencePenalty;

  /// Agent 默认 frequency penalty。
  final double? frequencyPenalty;

  /// Agent 默认随机种子。
  final int? seed;

  /// Agent 默认停用词。
  final List<String>? stopSequences;

  /// Agent 默认 reasoning 力度。
  final provider.ReasoningEffort? reasoning;

  /// Agent 默认输出解析策略。
  final Output<Complete, Partial, Element>? output;

  /// Agent 默认停止条件;不传时按上游 Agent 语义最多运行 20 步。
  final Object? stopWhen;

  /// Agent 默认请求头。
  final Map<String, String>? headers;

  /// Agent 默认 provider 私有选项。
  final provider.ProviderOptions? providerOptions;

  /// Agent 默认运行时上下文。
  final RuntimeContext? runtimeContext;

  /// Agent 默认工具上下文。
  final ToolsContext? toolsContext;

  /// Agent 默认激活工具列表。
  final ActiveTools? activeTools;

  /// Agent 默认工具顺序。
  final ToolOrder? toolOrder;

  /// Agent 默认 step 准备函数。
  final PrepareStepFunction? prepareStep;

  /// Agent 默认工具审批配置。
  final Object? toolApproval;

  /// Agent 默认工具调用修复函数。
  final ToolCallRepairFunction? repairToolCall;

  /// Agent 默认流式 include 配置。
  final StreamTextInclude? include;

  /// Agent 默认开始回调。
  final GenerateTextOnStartCallback? onStart;

  /// Agent 默认步骤开始回调。
  final GenerateTextOnStepStartCallback? onStepStart;

  /// Agent 默认步骤结束回调。
  final void Function(StepResult step)? onStepEnd;

  /// Agent 默认结束回调。
  final GenerateTextOnEndCallback? onEnd;

  /// 非流式运行 Agent。
  @override
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
  }) {
    return generateText<Complete, Partial, Element>(
      model: model,
      prompt: prompt,
      messages: messages,
      instructions: instructions,
      tools: tools,
      toolChoice: toolChoice ?? this.toolChoice,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      seed: seed ?? this.seed,
      stopSequences: stopSequences ?? this.stopSequences,
      reasoning: reasoning ?? this.reasoning,
      output: output,
      stopWhen: stopWhen ?? this.stopWhen ?? isStepCount(20),
      cancellation: cancellation,
      headers: mergeHeaders(this.headers, headers),
      providerOptions: mergeProviderOptionsDeep(
        this.providerOptions,
        providerOptions,
      ),
      runtimeContext: runtimeContext ?? this.runtimeContext,
      toolsContext: toolsContext ?? this.toolsContext,
      activeTools: activeTools ?? this.activeTools,
      toolOrder: toolOrder ?? this.toolOrder,
      prepareStep: prepareStep ?? this.prepareStep,
      toolApproval: toolApproval ?? this.toolApproval,
      repairToolCall: repairToolCall ?? this.repairToolCall,
      onStart: _chain(this.onStart, onStart),
      onStepStart: _chain(this.onStepStart, onStepStart),
      onStepEnd: _chain(this.onStepEnd, onStepEnd),
      onEnd: _chain(this.onEnd, onEnd),
    );
  }

  /// 流式运行 Agent。
  @override
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
  }) {
    return streamText<Complete, Partial, Element>(
      model: model,
      prompt: prompt,
      messages: messages,
      instructions: instructions,
      tools: tools,
      toolChoice: toolChoice ?? this.toolChoice,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      seed: seed ?? this.seed,
      stopSequences: stopSequences ?? this.stopSequences,
      reasoning: reasoning ?? this.reasoning,
      output: output,
      stopWhen: stopWhen ?? this.stopWhen ?? isStepCount(20),
      cancellation: cancellation,
      headers: mergeHeaders(this.headers, headers),
      providerOptions: mergeProviderOptionsDeep(
        this.providerOptions,
        providerOptions,
      ),
      runtimeContext: runtimeContext ?? this.runtimeContext,
      toolsContext: toolsContext ?? this.toolsContext,
      activeTools: activeTools ?? this.activeTools,
      toolOrder: toolOrder ?? this.toolOrder,
      prepareStep: prepareStep ?? this.prepareStep,
      toolApproval: toolApproval ?? this.toolApproval,
      repairToolCall: repairToolCall ?? this.repairToolCall,
      include: include ?? this.include,
      onStart: _chain(this.onStart, onStart),
      onStepStart: _chain(this.onStepStart, onStepStart),
      onStepEnd: _chain(this.onStepEnd, onStepEnd),
      onEnd: _chain(this.onEnd, onEnd),
      onError: onError,
    );
  }
}

void Function(T value)? _chain<T>(
  void Function(T value)? first,
  void Function(T value)? second,
) {
  if (first == null) {
    return second;
  }
  if (second == null) {
    return first;
  }
  return (value) {
    first(value);
    second(value);
  };
}
