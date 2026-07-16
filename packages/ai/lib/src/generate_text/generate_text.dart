import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../prompt/content_part.dart';
import '../prompt/from_language_model_prompt.dart';
import '../prompt/model_message.dart';
import '../prompt/standardize_prompt.dart';
import '../prompt/to_language_model_prompt.dart';
import '../telemetry/telemetry_dispatcher.dart';
import '../telemetry/telemetry_settings.dart';
import '../tool/tool.dart';
import 'active_tools.dart';
import 'context.dart';
import 'lifecycle_events.dart';
import 'output.dart';
import 'prepare_step.dart';
import 'request_options_snapshot.dart';
import 'step_result.dart';
import 'stop_condition.dart';
import 'tool_call_repair.dart';
import 'tool_order.dart';
import 'tool_loop.dart';

/// [generateText] 的非流式聚合结果。
///
/// 由多步工具循环跑完后的 [steps] 派生而来:末步文本/终止原因、
/// 跨全部步骤聚合的内容/工具/用量/告警,以及可供下一轮续接的完整回复消息列表。
final class GenerateTextResult<Complete> {
  /// 创建一个 [GenerateTextResult]。
  ///
  /// [steps] 在构造时固化为不可变视图:结果一旦返回即稳定,调用方无法通过
  /// `result.steps.clear()`/重排静默改变 [finalStep]/[text]/[usage]/
  /// [responseMessages](与流式结果返回不可变 steps 快照对齐)。因需
  /// `List.unmodifiable` 包装,本构造函数非 const(结果恒由运行时数据构造,
  /// 本就无 const 用途)。
  GenerateTextResult({
    required List<StepResult> steps,
    required Complete? output,
    required bool hasOutput,
    List<ModelMessage> responseMessages = const [],
  })  : steps = List<StepResult>.unmodifiable(steps),
        _responseMessages = List<ModelMessage>.unmodifiable(responseMessages),
        _output = output,
        _hasOutput = hasOutput;

  /// 多步工具循环的逐步结果,顺序即执行顺序,至少含一步。
  final List<StepResult> steps;
  final List<ModelMessage> _responseMessages;

  final Complete? _output;
  final bool _hasOutput;

  /// 解析后的最终输出。
  ///
  /// 仅当最终终止原因是 stop(完整完成)时可用;若模型以工具调用、长度限制、
  /// 内容过滤或错误等非 stop 原因结束,没有完整输出可解析,访问本 getter 会
  /// 抛出契约层错误。
  Complete get output {
    if (!_hasOutput) {
      throw const provider.NoOutputGeneratedError();
    }
    return _output as Complete;
  }

  /// 循环的最后一步。
  StepResult get finalStep => steps.last;

  /// 最终文本:最后一步的聚合文本。
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

  /// 最终终止原因(取最后一步)。
  provider.LanguageModelFinishReason get finishReason => finalStep.finishReason;

  /// 跨全部步骤累加的 token 用量。
  ///
  /// 输入/输出 total 逐步相加(某步为 `null` 时按 0 计);仅当所有步骤该字段
  /// 均为 `null` 时,汇总结果该字段才为 `null`。provider 原始用量对象
  /// ([provider.LanguageModelUsage.raw]) 不参与求和,汇总结果恒为 `null`
  /// ——单一 provider 原始对象无法代表跨步之和。
  provider.LanguageModelUsage get usage => _sumUsage(steps);

  /// 最后一步的响应侧元数据。
  provider.ResponseInfo? get response => finalStep.response;

  /// 所有步骤的 provider 侧告警。
  List<provider.Warning> get warnings =>
      steps.expand((step) => step.warnings).toList(growable: false);

  /// 供多轮续接的完整回复消息:先包含恢复审批执行产生的工具结果,再按步骤顺序
  /// 拼接每步产出的消息(assistant 文本/工具调用 + 工具结果),不含调用方原始
  /// 输入消息。
  List<ModelMessage> get responseMessages => <ModelMessage>[
        ..._responseMessages,
        ...steps.expand(_stepResponseMessages),
      ].toList(growable: false);
}

provider.LanguageModelUsage _sumUsage(List<StepResult> steps) {
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
    inputTokens: provider.InputTokens(
      total: hasInputTotal ? inputTotal : null,
    ),
    outputTokens: provider.OutputTokens(
      total: hasOutputTotal ? outputTotal : null,
    ),
  );
}

/// 非流式便捷入口:标准化 prompt、转换为契约面消息、跑完内置多步工具循环,
/// 并把结果聚合为 [GenerateTextResult]。
///
/// 参数二选一:`prompt` 或 `messages`(恰好一个非空,否则
/// [provider.InvalidPromptError],校验发生在 [standardizePrompt] 内)。
/// `stopWhen` 缺省时循环只跑一步(与 v7 一致)。
///
/// provider 侧已执行(`providerExecuted`)的工具不驱动续接(v7 语义,详见
/// `generate_text/tool_loop.dart` 的边缘态说明);需要时可把 [GenerateTextResult.responseMessages]
/// 续入下一轮请求自行发起。
Future<GenerateTextResult<Complete>> generateText<Complete, Partial, Element>({
  required provider.LanguageModel model,
  String? prompt,
  List<ModelMessage>? messages,
  String? instructions,
  ToolSet? tools,
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
  Output<Complete, Partial, Element>? output,
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
  TelemetrySettings? telemetry,
}) async {
  final outputSpec =
      output ?? (Output.text() as Output<Complete, Partial, Element>);
  final dispatcher = TelemetryDispatcher(telemetry);
  // preflight(prompt 校验/转换)失败也要进 telemetry onError(与流式路径对称:
  // 流式的 promptError 经 driver catch 派 onError)。失败时不派 onStart,
  // 与流式一致(操作未真正开始)。
  final List<provider.LanguageModelMessage> initialMessages;
  final List<ModelMessage> startMessages;
  try {
    final standardized = standardizePrompt(
      prompt: prompt,
      messages: messages,
      instructions: instructions,
    );
    initialMessages = convertToLanguageModelPrompt(standardized);
    startMessages = convertFromLanguageModelPrompt(
      initialMessages.where((message) => message is! provider.SystemMessage),
    );
  } catch (error) {
    await dispatcher.dispatchError(error);
    rethrow;
  }
  final toolSet = tools == null ? null : Map<String, Tool>.unmodifiable(tools);
  final stopWhenSnapshot = stopWhen is List<StopCondition>
      ? List<StopCondition>.unmodifiable(stopWhen)
      : stopWhen;
  final stopSequencesSnapshot =
      stopSequences == null ? null : List<String>.unmodifiable(stopSequences);
  final headersSnapshot = snapshotHeaders(headers);
  final providerOptionsSnapshot = snapshotProviderOptions(providerOptions);
  final runtimeContextSnapshot = snapshotRuntimeContext(runtimeContext);
  final toolsContextSnapshot = snapshotToolsContext(toolsContext);
  final activeToolsSnapshot =
      activeTools == null ? null : List<String>.unmodifiable(activeTools);
  final toolOrderSnapshot =
      toolOrder == null ? null : List<String>.unmodifiable(toolOrder);
  final responseFormat =
      output == null ? null : outputResponseFormat(outputSpec);
  final toolApprovalSnapshot = toolApproval is Map<String, Object?>
      ? Map<String, Object?>.unmodifiable(toolApproval)
      : toolApproval;
  onStart?.call(GenerateTextStartEvent(
    model: model,
    messages: startMessages,
  ));
  await dispatcher.dispatchStart(GenerateTextStartEvent(
    model: model,
    messages: startMessages,
  ));

  final responseMessages = <ModelMessage>[];
  final List<StepResult> steps;
  try {
    steps = await runToolLoopGenerate(
      model: model,
      initialMessages: initialMessages,
      instructions: instructions,
      tools: toolSet,
      toolChoice: toolChoice,
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
      topP: topP,
      topK: topK,
      presencePenalty: presencePenalty,
      frequencyPenalty: frequencyPenalty,
      seed: seed,
      stopSequences: stopSequencesSnapshot,
      reasoning: reasoning,
      responseFormat: responseFormat,
      stopWhen: stopWhenSnapshot,
      cancellation: cancellation,
      headers: headersSnapshot,
      providerOptions: providerOptionsSnapshot,
      runtimeContext: runtimeContextSnapshot,
      toolsContext: toolsContextSnapshot,
      activeTools: activeToolsSnapshot,
      toolOrder: toolOrderSnapshot,
      prepareStep: prepareStep,
      toolApproval: toolApprovalSnapshot,
      repairToolCall: repairToolCall,
      onStepStart: onStepStart,
      onStepEnd: onStepEnd,
      onResumedToolMessage: (message) {
        responseMessages.add(_toModelToolMessage(message));
      },
      dispatcher: dispatcher,
    );
  } catch (error) {
    await dispatcher.dispatchError(error);
    rethrow;
  }

  final finalStep = steps.last;
  final usage = _sumUsage(steps);
  onEnd?.call(GenerateTextEndEvent(steps: steps));
  final shouldParseOutput =
      finalStep.finishReason.unified == provider.FinishReasonType.stop;
  // C3:telemetry `dispatchEnd` 放到 parse 成功之后;parse 失败 → dispatchError
  // (此时尚未 dispatchEnd),故 telemetry 永不出现 onEnd → onError。用户既有
  // onEnd?.call 保持原位(parse 之前),不改既有语义。
  final Complete? parsedOutput;
  try {
    parsedOutput = shouldParseOutput
        ? await outputSpec.parseCompleteOutput(
            OutputText(finalStep.text),
            OutputParseContext(
              response: finalStep.response,
              usage: usage,
              finishReason: finalStep.finishReason,
            ),
          )
        : null;
  } catch (error) {
    await dispatcher.dispatchError(error);
    rethrow;
  }
  await dispatcher.dispatchEnd(GenerateTextEndEvent(steps: steps));

  final result = GenerateTextResult<Complete>(
    steps: steps,
    output: parsedOutput,
    hasOutput: shouldParseOutput,
    responseMessages: responseMessages,
  );
  return result;
}

/// 把输出侧 `provider.OutputFileData`(bytes/base64/url)还原为用户面
/// [DataContent],供 `responseMessages` 续接往返(转换层正向映射的对偶)。
DataContent _toDataContent(provider.OutputFileData data) {
  return switch (data) {
    provider.FileDataBytes(:final bytes) => DataBytes(bytes),
    provider.FileDataBase64(:final base64) => DataBase64(base64),
    provider.FileDataUrl(:final url) => DataUrl(url),
  };
}

/// 把一步 [StepResult] 还原为供下一轮续接的 pigcode_ai 用户面消息:
/// 先是一条携带该步文本/推理/文件/推理文件/自定义内容/工具调用/provider 侧
/// 已执行工具结果/审批请求的 [AssistantModelMessage](若有内容),再是(若有
/// 自动审批回复或本地执行的工具结果)一条 [ToolModelMessage]。SourceContent
/// 暂无对应用户面 part,略过。
///
/// provider 已侧执行(`providerExecuted == true`)的调用会随一条自带的
/// `provider.ToolResult` 一起出现在本步内容里;若不将其重建进
/// [AssistantModelMessage],调用方把 `responseMessages` 续接进下一轮请求时
/// 会丢失该结果(与 `generate_text/tool_loop.dart`/本文件邻近流式实现的
/// `_toAssistantMessage` 保持一致)。
Iterable<ModelMessage> _stepResponseMessages(StepResult step) sync* {
  final assistantParts = <AssistantContentPart>[];
  for (final item in step.content) {
    if (item is provider.TextContent) {
      assistantParts.add(TextPart(
        item.text,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ReasoningContent) {
      assistantParts.add(ReasoningPart(
        item.text,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.FileContent) {
      assistantParts.add(FilePart(
        data: _toDataContent(item.data),
        mediaType: item.mediaType,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ReasoningFileContent) {
      assistantParts.add(ReasoningFilePart(
        data: _toDataContent(item.data),
        mediaType: item.mediaType,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.CustomContentBlock) {
      assistantParts.add(CustomPart(
        item.kind,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ToolCall) {
      assistantParts.add(ToolCallPart(
        toolCallId: item.toolCallId,
        toolName: item.toolName,
        input: jsonDecode(item.input) as provider.JsonValue,
        providerExecuted: item.providerExecuted,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ToolApprovalRequest) {
      assistantParts.add(ToolApprovalRequestPart(
        approvalId: item.approvalId,
        toolCallId: item.toolCallId,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ToolResult) {
      assistantParts.add(ToolResultPart(
        toolCallId: item.toolCallId,
        toolName: item.toolName,
        output: item.isError == true
            ? provider.ToolResultErrorJson(item.result)
            : provider.ToolResultJson(item.result),
        providerOptions: item.providerMetadata,
      ));
    }
  }
  if (assistantParts.isNotEmpty) {
    yield AssistantModelMessage(assistantParts);
  }

  if (step.toolResults.isNotEmpty || step.toolApprovalResponses.isNotEmpty) {
    yield ToolModelMessage(
      <ToolContentPart>[
        for (final response in step.toolApprovalResponses)
          ToolApprovalResponsePart(
            approvalId: response.approvalId,
            approved: response.approved,
            reason: response.reason,
            providerOptions: response.providerOptions,
          ),
        for (var i = 0; i < step.toolResults.length; i++)
          ToolResultPart(
            toolCallId: step.toolResults[i].toolCallId,
            toolName: step.toolResults[i].toolName,
            output: step.toolResultOutputs[i],
          ),
      ],
    );
  }
}

ToolModelMessage _toModelToolMessage(provider.ToolMessage message) {
  return ToolModelMessage(<ToolContentPart>[
    for (final part in message.content)
      if (part is provider.ToolApprovalResponsePart)
        ToolApprovalResponsePart(
          approvalId: part.approvalId,
          approved: part.approved,
          reason: part.reason,
          providerOptions: part.providerOptions,
        )
      else if (part is provider.ToolResultPart)
        ToolResultPart(
          toolCallId: part.toolCallId,
          toolName: part.toolName,
          output: part.output,
          providerOptions: part.providerOptions,
        ),
  ]);
}
