import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import '../logger/log_warnings.dart';
import '../prompt/from_language_model_prompt.dart';
import '../prompt/to_language_model_prompt.dart';
import '../telemetry/telemetry_dispatcher.dart';
import '../telemetry/telemetry_events.dart';
import '../tool/tool.dart';
import 'active_tools.dart';
import 'context.dart';
import 'lifecycle_events.dart';
import 'performance.dart';
import 'prepare_step.dart';
import 'request_timeout.dart';
import 'request_options_snapshot.dart';
import 'step_result.dart';
import 'stop_condition.dart';
import 'tool_approval.dart';
import 'tool_call_parser.dart';
import 'tool_call_repair.dart';
import 'tool_order.dart';

/// 共享的多步工具循环引擎(非流式)。
///
/// [generateText] 直接使用其结果;[streamText] 走独立的流式引擎(另文件),
/// 但共享同样的续/停判定逻辑。
///
/// 续 iff:末步 `finishReason.unified == toolCalls` 且至少一个工具调用命中
/// 「带 execute 的工具」且不存在「无 execute 的工具调用」且调用方**提供了**
/// [stopWhen] 且其尚未命中;否则收尾。未传 [stopWhen] 时恒为单步——即便本步
/// 命中工具调用且已执行,也不会发起第二次模型调用(v7 行为:不传 stopWhen
/// 就在第一步后停)。
///
/// **provider 侧已执行工具的边缘态**:某步 `finishReason == toolCalls` 且只含
/// `providerExecuted == true` 的调用(及其自带结果)时,循环**停止**、不发起
/// 后续模型调用(v7 语义:provider 内置工具的「结果喂回模型」发生在 provider
/// 服务器内部、同一次请求里,客户端回传 server-side 结果可能违反 wire 协议)。
/// 例外:标记 `supportsDeferredResults` 的 provider 工具,其 providerExecuted
/// 调用在同响应无配对结果时记入 `pendingDeferredToolCalls` 并自动续接,直至
/// 结果跨轮到达解销(仍受 stopWhen 约束;pending-only 续接只追加 assistant
/// 消息)。其余场景仍可把 `responseMessages`(已完整保留 provider 侧结果)
/// 续入下一轮请求自行发起。
Future<List<StepResult>> runToolLoopGenerate({
  required provider.LanguageModel model,
  required List<provider.LanguageModelMessage> initialMessages,
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
  provider.ResponseFormat? responseFormat,
  provider.CancellationSignal? cancellation,
  TimeoutConfiguration timeout = const TimeoutConfiguration(),
  Map<String, String>? headers,
  provider.ProviderOptions? providerOptions,
  RuntimeContext runtimeContext = const {},
  ToolsContext toolsContext = const {},
  ActiveTools? activeTools,
  ToolOrder? toolOrder,
  PrepareStepFunction? prepareStep,
  Object? toolApproval,
  ToolCallRepairFunction? repairToolCall,
  Object? stopWhen,
  GenerateTextOnStepStartCallback? onStepStart,
  void Function(StepResult step)? onStepEnd,
  void Function(provider.ToolMessage message)? onResumedToolMessage,
  TelemetryDispatcher? dispatcher,
}) async {
  final stopConditions = _normalizeStopWhen(stopWhen);
  final toolApprovalSnapshot = toolApproval is Map<String, Object?>
      ? Map<String, Object?>.unmodifiable(toolApproval)
      : toolApproval;
  // 循环开始前对 caller 持有的 tools map 拍不可变快照:advertisedTools(广告给
  // 模型)与后续按名查表执行必须基于同一快照;否则 caller 在 await doGenerate
  // 期间改动/清空该 map,会让已广告的工具在执行时查不到而被当作 blocking、
  // 或换成别的回调。循环内只读该快照,不读原始 tools。
  final toolSet = tools == null ? null : Map<String, Tool>.unmodifiable(tools);
  final activeToolsSnapshot =
      activeTools == null ? null : List<String>.unmodifiable(activeTools);
  final toolOrderSnapshot =
      toolOrder == null ? null : List<String>.unmodifiable(toolOrder);
  // 调用时刻快照 stopSequences(可变 List<String>):归一发生在调用方同步前缀
  // 内,此后 caller 改动原列表不应改掉本次(含后续步)请求的停用词。
  final stopSequencesSnapshot =
      stopSequences == null ? null : List<String>.unmodifiable(stopSequences);
  // 调用级 request maps 与停用词一样按整轮固定。否则 caller 或 async
  // middleware 在 await 间隙改动 Map,会污染当前或后续步的模型请求。
  final headersSnapshot = snapshotHeaders(headers);
  final providerOptionsSnapshot = snapshotProviderOptions(providerOptions);
  var currentRuntimeContext = snapshotRuntimeContext(runtimeContext);
  var currentToolsContext = snapshotToolsContext(toolsContext);
  final initialMessagesSnapshot =
      List<provider.LanguageModelMessage>.unmodifiable(initialMessages);
  final initialModelMessagesSnapshot =
      convertFromLanguageModelPrompt(initialMessagesSnapshot);
  var messagesForNextStep =
      List<provider.LanguageModelMessage>.of(initialMessagesSnapshot);
  final responseMessages = <provider.LanguageModelMessage>[];
  final resumedToolMessage = await _executeResumedToolApprovals(
    messages: initialMessagesSnapshot,
    tools: toolSet,
    toolsContext: currentToolsContext,
    toolApproval: toolApprovalSnapshot,
    repairToolCall: repairToolCall,
    instructions: instructions,
    cancellation: cancellation,
    timeout: timeout,
    dispatcher: dispatcher,
  );
  if (resumedToolMessage != null) {
    messagesForNextStep.add(resumedToolMessage);
    responseMessages.add(resumedToolMessage);
    onResumedToolMessage?.call(resumedToolMessage);
  }
  final steps = <StepResult>[];
  final generateApprovalId = createIdGenerator(prefix: 'approval');
  final generateModelCallId = createIdGenerator(prefix: 'lmcall');
  // provider 工具自动续接的 pending 表(toolCallId → toolName):跨步存续、
  // 单次调用级(:780-783)。providerExecuted 且标记 supportsDeferredResults
  // 的调用在同响应无配对结果时记入,结果跨轮到达时解销。
  final pendingDeferredToolCalls = <String, String>{};

  while (true) {
    throwIfCancelled(cancellation);
    final stepInputMessages =
        List<provider.LanguageModelMessage>.unmodifiable(messagesForNextStep);
    final prepareStepResult = prepareStep == null
        ? null
        : await interruptFutureOnCancellation(
            prepareStep(PrepareStepOptions(
              steps: steps,
              stepNumber: steps.length,
              model: model,
              messages: convertFromLanguageModelPrompt(stepInputMessages),
              initialMessages: initialModelMessagesSnapshot,
              responseMessages:
                  convertFromLanguageModelPrompt(responseMessages),
              runtimeContext: currentRuntimeContext,
              toolsContext: currentToolsContext,
            )),
            cancellation,
          );
    if (prepareStepResult?.runtimeContext != null) {
      currentRuntimeContext =
          snapshotRuntimeContext(prepareStepResult!.runtimeContext);
    }
    if (prepareStepResult?.toolsContext != null) {
      currentToolsContext =
          snapshotToolsContext(prepareStepResult!.toolsContext);
    }
    final stepModel = prepareStepResult?.model ?? model;
    final stepMessages = prepareStepResult?.messages == null
        ? stepInputMessages
        : List<provider.LanguageModelMessage>.unmodifiable(
            convertModelMessagesToLanguageModelPrompt(
              prepareStepResult!.messages!,
            ),
          );
    final stepTools = filterActiveTools(
      toolSet,
      prepareStepResult?.activeTools ?? activeToolsSnapshot,
    );
    final stepToolChoice = filterToolChoiceForTools(
      prepareStepResult?.toolChoice ?? toolChoice,
      stepTools,
    );
    final stepToolOrder = prepareStepResult?.toolOrder ?? toolOrderSnapshot;
    // 广告给模型的工具列表每步冻结:activeTools/prepareStep 可能让每步广告集
    // 不同,但 provider/中间件仍不得原地改动当前步骤的 callOptions.tools。
    final advertisedTools = stepTools == null || stepTools.isEmpty
        ? const <provider.LanguageModelTool>[]
        : List<provider.LanguageModelTool>.unmodifiable(
            buildOrderedLanguageModelTools(
              stepTools,
              stepToolOrder,
              toolSet,
            ),
          );
    final stepProviderOptions = mergeProviderOptions(
      providerOptionsSnapshot,
      prepareStepResult?.providerOptions,
    );
    final stepScope = CancellationScope(
      parent: cancellation,
      timeout: timeout.step,
      label: 'Step',
    );
    final stepCancellation = stepScope.signal;
    final callOptions = provider.LanguageModelCallOptions(
      // 每步传入 messages 的不可变快照:后续追加工具结果不会改动上一次调用
      // 保留的 prompt(保值对象语义,不污染 provider/中间件的 tracing/replay)。
      prompt: stepMessages,
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
      topP: topP,
      topK: topK,
      presencePenalty: presencePenalty,
      frequencyPenalty: frequencyPenalty,
      seed: seed,
      stopSequences: stopSequencesSnapshot,
      responseFormat: responseFormat,
      tools: advertisedTools.isEmpty ? null : advertisedTools,
      toolChoice: stepToolChoice,
      reasoning: reasoning,
      cancellation: stepCancellation,
      headers: headersSnapshot,
      providerOptions: stepProviderOptions,
    );

    onStepStart?.call(GenerateTextStepStartEvent(
      stepNumber: steps.length,
      model: stepModel,
      messages: convertFromLanguageModelPrompt(stepMessages),
      steps: steps,
    ));
    final telemetryCallId = generateModelCallId();
    if (dispatcher != null && dispatcher.isActive) {
      final stepModelMessages = convertFromLanguageModelPrompt(stepMessages);
      await dispatcher.dispatchStepStart(GenerateTextStepStartEvent(
        stepNumber: steps.length,
        model: stepModel,
        messages: stepModelMessages,
        steps: steps,
      ));
      await dispatcher
          .dispatchLanguageModelCallStart(LanguageModelCallStartEvent(
        callId: telemetryCallId,
        providerId: stepModel.provider,
        modelId: stepModel.modelId,
        stepNumber: steps.length,
        messages: stepModelMessages,
      ));
    }
    final stepStopwatch = Stopwatch()..start();
    final provider.LanguageModelGenerateResult result;
    try {
      result = await interruptFutureOnCancellation(
        stepModel.doGenerate(callOptions),
        stepCancellation,
      );
    } catch (error) {
      stepScope.dispose();
      // 模型调用本身抛错(provider/网络/取消)时,补派 lmEnd(finishReason=error)
      // 使 lmStart 恒配对;随后 rethrow 交外层(generateText)派 onError。
      if (dispatcher != null && dispatcher.isActive) {
        await dispatcher.dispatchLanguageModelCallEnd(LanguageModelCallEndEvent(
          callId: telemetryCallId,
          providerId: stepModel.provider,
          modelId: stepModel.modelId,
          stepNumber: steps.length,
          content: const [],
          usage: const provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(),
            outputTokens: provider.OutputTokens(),
          ),
          finishReason: const provider.LanguageModelFinishReason(
            provider.FinishReasonType.error,
          ),
          warnings: const [],
          response: null,
          responseTime: stepStopwatch.elapsed,
        ));
      }
      rethrow;
    }
    try {
      final responseTime = stepStopwatch.elapsed;
      if (dispatcher != null && dispatcher.isActive) {
        await dispatcher.dispatchLanguageModelCallEnd(LanguageModelCallEndEvent(
          callId: telemetryCallId,
          providerId: stepModel.provider,
          modelId: stepModel.modelId,
          stepNumber: steps.length,
          content: result.content,
          usage: result.usage,
          finishReason: result.finishReason,
          warnings: result.warnings,
          response: result.response,
          responseTime: responseTime,
        ));
      }
      logWarnings(
        warnings: result.warnings,
        provider: stepModel.provider,
        model: stepModel.modelId,
      );

      final stepContent = <provider.LanguageModelContent>[
        ...result.content,
      ];
      final executableCalls = <ParsedToolCall>[];
      final blockingCalls = <provider.ToolCall>[];
      final toolResults = <provider.ToolResult>[];
      final toolResultOutputs = <provider.ToolResultOutput>[];
      final toolApprovalResponses = <provider.ToolApprovalResponsePart>[];
      final toolExecutionTimes = <String, Duration>{};
      final providerApprovalRequestsByToolCallId =
          <String, provider.ToolApprovalRequest>{
        for (final content in result.content)
          if (content is provider.ToolApprovalRequest)
            content.toolCallId: content,
      };
      for (var contentIndex = 0;
          contentIndex < result.content.length;
          contentIndex++) {
        final content = result.content[contentIndex];
        if (content is provider.ToolCall) {
          var toolCall = content;
          ParsedToolCall? parsedCall;
          final providerExecutedApprovalRequest =
              providerApprovalRequestsByToolCallId[content.toolCallId];
          // provider 已侧执行(`providerExecuted == true`)的调用会由 provider 自带
          // 结果,本地循环不得再跑同名 `execute`,也不做 repair(否则可能误改
          // provider-managed 工具协议)。
          if (content.providerExecuted == true) {
            if (providerExecutedApprovalRequest != null) {
              final approval = await resolveToolApproval(
                toolApproval: toolApprovalSnapshot,
                toolCall: content,
                messages: stepMessages,
                tools: stepTools,
              );
              switch (approval.type) {
                case ToolApprovalStatusType.approved:
                  toolApprovalResponses.add(provider.ToolApprovalResponsePart(
                    approvalId: providerExecutedApprovalRequest.approvalId,
                    approved: true,
                    reason: approval.reason,
                    providerOptions:
                        providerExecutedApprovalRequest.providerMetadata,
                  ));
                case ToolApprovalStatusType.denied:
                  toolApprovalResponses.add(provider.ToolApprovalResponsePart(
                    approvalId: providerExecutedApprovalRequest.approvalId,
                    approved: false,
                    reason: approval.reason,
                    providerOptions:
                        providerExecutedApprovalRequest.providerMetadata,
                  ));
                case ToolApprovalStatusType.notApplicable:
                case ToolApprovalStatusType.userApproval:
                  blockingCalls.add(content);
              }
            }
            continue;
          }
          final originalTool = stepTools?[content.toolName];
          if (originalTool != null && originalTool.execute == null) {
            blockingCalls.add(content);
            continue;
          }
          if (originalTool == null && repairToolCall != null) {
            var repairReturnedNull = false;
            var repairReturnedNonNull = false;
            try {
              parsedCall = await parseOrRepairToolCall(
                toolCall: content,
                tools: stepTools,
                repairToolCall: (options) async {
                  final repaired = await repairToolCall(options);
                  if (repaired == null) {
                    repairReturnedNull = true;
                  } else {
                    repairReturnedNonNull = true;
                  }
                  return repaired;
                },
                instructions: instructions,
                messages: stepMessages,
              );
              toolCall = parsedCall.toolCall;
              stepContent[contentIndex] = toolCall;
            } on NoSuchToolError {
              if (repairReturnedNonNull || !repairReturnedNull) {
                rethrow;
              }
              blockingCalls.add(content);
              continue;
            }
          }
          final tool = stepTools?[toolCall.toolName];
          if (tool == null || tool.execute == null) {
            blockingCalls.add(toolCall);
            continue;
          }

          Future<ParsedToolCall> parseForExecution({
            required bool allowIdentityChange,
          }) async {
            if (parsedCall != null) {
              return parsedCall!;
            }
            if (repairToolCall != null) {
              parsedCall = await parseOrRepairToolCall(
                toolCall: toolCall,
                tools: stepTools,
                repairToolCall: repairToolCall,
                instructions: instructions,
                messages: stepMessages,
              );
              final repairedToolCall = parsedCall!.toolCall;
              if (!allowIdentityChange &&
                  (repairedToolCall.toolName != toolCall.toolName ||
                      repairedToolCall.toolCallId != toolCall.toolCallId)) {
                throw StateError(
                  'repairToolCall cannot change toolName or toolCallId after '
                  'tool approval has been resolved.',
                );
              }
              toolCall = repairedToolCall;
              stepContent[contentIndex] = toolCall;
              return parsedCall!;
            }
            parsedCall = parseToolCall(toolCall: toolCall, tools: stepTools);
            final parsedToolCall = parsedCall!.toolCall;
            if (parsedToolCall != toolCall) {
              toolCall = parsedToolCall;
              stepContent[contentIndex] = toolCall;
            }
            return parsedCall!;
          }

          if (toolApprovalRequiresInput(
                toolApproval: toolApprovalSnapshot,
                toolCall: toolCall,
              ) ||
              (repairToolCall != null &&
                  !toolApprovalMayBlockBeforeInput(
                    toolApproval: toolApprovalSnapshot,
                    toolCall: toolCall,
                  ))) {
            await parseForExecution(allowIdentityChange: true);
            final repairedTool = stepTools?[toolCall.toolName];
            if (repairedTool == null || repairedTool.execute == null) {
              blockingCalls.add(toolCall);
              continue;
            }
          }

          if (tool.onInputStart != null || tool.onInputAvailable != null) {
            final callbackCall =
                await parseForExecution(allowIdentityChange: true);
            final callbackTool = stepTools?[callbackCall.toolCall.toolName];
            if (callbackTool != null) {
              final callbackMessages =
                  List<provider.LanguageModelMessage>.unmodifiable(
                stepMessages
                    .where((message) => message is! provider.SystemMessage),
              );
              final callbackContext = _validateToolContext(
                toolName: callbackCall.toolCall.toolName,
                tool: callbackTool,
                toolsContext: currentToolsContext,
              );
              if (callbackTool.onInputStart case final callback?) {
                await interruptFutureOnCancellation(
                  callback(ToolInputStartOptions(
                    toolCallId: callbackCall.toolCall.toolCallId,
                    messages: callbackMessages,
                    context: callbackContext,
                    cancellation: stepCancellation,
                  )),
                  stepCancellation,
                );
              }
              if (callbackTool.onInputAvailable case final callback?) {
                await interruptFutureOnCancellation(
                  callback(ToolInputAvailableOptions(
                    input: callbackCall.input,
                    toolCallId: callbackCall.toolCall.toolCallId,
                    messages: callbackMessages,
                    context: callbackContext,
                    cancellation: stepCancellation,
                  )),
                  stepCancellation,
                );
              }
            }
          }

          final approval = await resolveToolApproval(
            toolApproval: toolApprovalSnapshot,
            toolCall: toolCall,
            messages: stepMessages,
            tools: stepTools,
          );

          switch (approval.type) {
            case ToolApprovalStatusType.notApplicable:
              if (providerApprovalRequestsByToolCallId
                  .containsKey(toolCall.toolCallId)) {
                blockingCalls.add(toolCall);
              } else {
                executableCalls.add(
                  await parseForExecution(allowIdentityChange: false),
                );
              }
            case ToolApprovalStatusType.approved:
              final request =
                  providerApprovalRequestsByToolCallId[toolCall.toolCallId] ??
                      provider.ToolApprovalRequest(
                        approvalId: generateApprovalId(),
                        toolCallId: toolCall.toolCallId,
                      );
              final response = provider.ToolApprovalResponsePart(
                approvalId: request.approvalId,
                approved: true,
                reason: approval.reason,
                providerOptions: request.providerMetadata,
              );
              if (!providerApprovalRequestsByToolCallId
                  .containsKey(toolCall.toolCallId)) {
                stepContent.add(request);
              }
              toolApprovalResponses.add(response);
              executableCalls.add(
                await parseForExecution(allowIdentityChange: false),
              );
            case ToolApprovalStatusType.denied:
              final request =
                  providerApprovalRequestsByToolCallId[toolCall.toolCallId] ??
                      provider.ToolApprovalRequest(
                        approvalId: generateApprovalId(),
                        toolCallId: toolCall.toolCallId,
                      );
              final response = provider.ToolApprovalResponsePart(
                approvalId: request.approvalId,
                approved: false,
                reason: approval.reason,
                providerOptions: request.providerMetadata,
              );
              final resultOutput = provider.ToolResultExecutionDenied(
                reason: approval.reason,
              );
              if (!providerApprovalRequestsByToolCallId
                  .containsKey(toolCall.toolCallId)) {
                stepContent.add(request);
              }
              toolApprovalResponses.add(response);
              toolResultOutputs.add(resultOutput);
              toolResults.add(provider.ToolResult(
                toolCallId: toolCall.toolCallId,
                toolName: toolCall.toolName,
                result: _toolResultOutputValue(resultOutput),
              ));
            case ToolApprovalStatusType.userApproval:
              if (!providerApprovalRequestsByToolCallId
                  .containsKey(toolCall.toolCallId)) {
                stepContent.add(provider.ToolApprovalRequest(
                  approvalId: generateApprovalId(),
                  toolCallId: toolCall.toolCallId,
                ));
              }
              blockingCalls.add(toolCall);
          }
        }
      }

      for (final parsedCall in executableCalls) {
        final call = parsedCall.toolCall;
        final tool = stepTools![call.toolName]!;
        final input = parsedCall.input;
        // 在 telemetry start 之前完成 context 校验,保证 start/end 恒配对:
        // 校验失败则不派 start(工具从未执行),错误照旧向上传播。
        final toolContext = _validateToolContext(
          toolName: call.toolName,
          tool: tool,
          toolsContext: currentToolsContext,
        );
        if (dispatcher != null && dispatcher.isActive) {
          await dispatcher.dispatchToolExecutionStart(ToolExecutionStartEvent(
            callId: call.toolCallId,
            toolCallId: call.toolCallId,
            toolName: call.toolName,
            input: input,
            toolContext: toolContext,
          ));
        }
        final toolStopwatch = Stopwatch()..start();
        final toolScope = CancellationScope(
          parent: stepCancellation,
          timeout: timeout.forTool(call.toolName),
          label: 'Tool ${call.toolName}',
        );
        final Object? output;
        try {
          output = await interruptFutureOnCancellation(
            tool.execute!(
              input,
              ToolExecuteOptions(
                toolCallId: call.toolCallId,
                // v7:ToolExecuteOptions.messages 不含 system prompt;传不可变副本,
                // 避免向工具暴露 system 指令、也防工具改动循环内部历史。
                messages: List<provider.LanguageModelMessage>.unmodifiable(
                  stepMessages.where((m) => m is! provider.SystemMessage),
                ),
                context: toolContext,
                cancellation: toolScope.signal,
              ),
            ),
            toolScope.signal,
          );
        } catch (error) {
          // per-tool error 变体(与 step 级 onError 不同粒度,不重复);记时后 rethrow。
          toolExecutionTimes[call.toolCallId] = toolStopwatch.elapsed;
          if (dispatcher != null && dispatcher.isActive) {
            await dispatcher.dispatchToolExecutionEnd(ToolExecutionEndError(
              callId: call.toolCallId,
              toolCallId: call.toolCallId,
              toolName: call.toolName,
              error: error,
              toolExecutionMs: toolStopwatch.elapsed.inMilliseconds,
            ));
          }
          rethrow;
        } finally {
          toolScope.dispose();
        }
        toolExecutionTimes[call.toolCallId] = toolStopwatch.elapsed;
        if (dispatcher != null && dispatcher.isActive) {
          await dispatcher.dispatchToolExecutionEnd(ToolExecutionEndSuccess(
            callId: call.toolCallId,
            toolCallId: call.toolCallId,
            toolName: call.toolName,
            output: output,
            toolExecutionMs: toolStopwatch.elapsed.inMilliseconds,
          ));
        }
        final resultOutput = tool.toModelOutput != null
            ? tool.toModelOutput!(input, output)
            : _defaultToModelOutput(output);
        toolResultOutputs.add(resultOutput);
        toolResults.add(provider.ToolResult(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          result: _toolResultOutputValue(resultOutput),
          isError: _isErrorOutput(resultOutput) ? true : null,
        ));
      }

      final step = StepResult(
        content: stepContent,
        finishReason: result.finishReason,
        usage: result.usage,
        response: result.response,
        // 结果级 provider 元数据带出(如 anthropic container id),供
        // steps[i].providerMetadata / prepareStep 转发消费。
        providerMetadata: result.providerMetadata,
        executedToolResults: toolResults,
        toolResultOutputs: toolResultOutputs,
        toolApprovalResponses: toolApprovalResponses,
        // 保留 provider 告警(如选项被忽略/降级),供非流式调用方经
        // StepResult.warnings 感知,与流式 StartStepPart.warnings 对称。
        warnings: result.warnings,
        runtimeContext: currentRuntimeContext,
        toolsContext: currentToolsContext,
        performance: buildStepPerformance(
          usage: result.usage,
          responseTime: responseTime,
          stepTime: stepStopwatch.elapsed,
          toolExecutionTimes: toolExecutionTimes,
        ),
      );
      steps.add(step);
      onStepEnd?.call(step);
      if (dispatcher != null && dispatcher.isActive) {
        await dispatcher.dispatchStepEnd(step);
      }

      // 追踪(:1231-1251):本步 providerExecuted 且 deferred-capable 的调用,
      // 同响应无配对 tool-result → 记入 pending。判定读用户 ToolSet 快照
      // (toolSet,非 wire 列表、非 activeTools 过滤集)。
      for (final item in step.content.whereType<provider.ToolCall>()) {
        if (item.providerExecuted != true) {
          continue;
        }
        if (toolSet?[item.toolName]?.providerTool?.supportsDeferredResults !=
            true) {
          continue;
        }
        final hasResultInResponse = step.content.any(
          (part) =>
              part is provider.ToolResult && part.toolCallId == item.toolCallId,
        );
        if (!hasResultInResponse) {
          pendingDeferredToolCalls[item.toolCallId] = item.toolName;
        }
      }
      // 解销(:1253-1258):对本响应全部 tool-result 无条件 remove(不限定
      // deferred 工具、不看 isError)——跨步到达的 deferred 结果在此闭环。
      for (final item in step.content.whereType<provider.ToolResult>()) {
        pendingDeferredToolCalls.remove(item.toolCallId);
      }

      final hasToolContentForNextStep =
          toolResults.isNotEmpty || toolApprovalResponses.isNotEmpty;
      final hasBlockingCalls = blockingCalls.isNotEmpty;
      final isToolCallsFinish =
          step.finishReason.unified == provider.FinishReasonType.toolCalls;
      final hasStopConditions = stopConditions.isNotEmpty;
      final stopWhenSatisfied =
          await _anyStopConditionTrue(stopConditions, steps);

      // 无 stopWhen 时恒为单步(v7 行为):即便本步命中工具调用,也不发起第二次
      // 模型调用。pending 支与 client-complete 支平级 OR(:1340-1350),不受
      // isToolCallsFinish/hasToolContentForNextStep/blocking 闸门约束(deferred
      // 悬置步的 finishReason 未必是 toolCalls;审批悬置不阻塞 deferred 闭环)。
      final clientComplete =
          isToolCallsFinish && hasToolContentForNextStep && !hasBlockingCalls;
      final shouldContinue =
          (clientComplete || pendingDeferredToolCalls.isNotEmpty) &&
              hasStopConditions &&
              !stopWhenSatisfied;

      if (!shouldContinue) {
        return steps;
      }

      final assistantMessage = _toAssistantMessage(step.content);
      responseMessages.add(assistantMessage);
      messagesForNextStep = List<provider.LanguageModelMessage>.of(stepMessages)
        ..add(assistantMessage);
      // pending-only 续接(本步无本地工具输出/审批回复)只追加 assistant 消息,
      // 禁止产生空 tool role 消息(对齐 :1325 与 :208-216:tool 消息仅当存在
      // client 工具输出/审批回复才构造)。responseMessages 公开面同受此约束。
      if (hasToolContentForNextStep) {
        final toolMessage = provider.ToolMessage(
          // 内容列表冻结,理由同上。
          List<provider.ToolContentPart>.unmodifiable([
            ...step.toolApprovalResponses,
            for (var i = 0; i < toolResults.length; i++)
              provider.ToolResultPart(
                toolCallId: toolResults[i].toolCallId,
                toolName: toolResults[i].toolName,
                output: toolResultOutputs[i],
              ),
          ]),
        );
        responseMessages.add(toolMessage);
        messagesForNextStep.add(toolMessage);
      }
    } finally {
      stepScope.dispose();
    }
  }
}

/// 把 `stopWhen`(单个或列表)归一为 `List<StopCondition>`;`null` → 空列表。
List<StopCondition> _normalizeStopWhen(Object? stopWhen) {
  if (stopWhen == null) {
    return const [];
  }
  if (stopWhen is StopCondition) {
    return [stopWhen];
  }
  if (stopWhen is List<StopCondition>) {
    // 拍不可变副本:归一发生在循环开始时(调用方同步前缀内),此后 caller 改动
    // 原列表不应改掉本次已激活的停条件集。
    return List<StopCondition>.unmodifiable(stopWhen);
  }
  throw ArgumentError.value(
    stopWhen,
    'stopWhen',
    'must be a StopCondition or List<StopCondition>',
  );
}

/// 任一条件为真即算命中(短路)。
Future<bool> _anyStopConditionTrue(
  List<StopCondition> conditions,
  List<StepResult> steps,
) async {
  // 传只读快照给用户谓词:防止 stopWhen 实现改动循环内部的 steps 累加器
  // (steps.clear()/增删),否则会污染最终结果与续/停判定。谓词只需读取,故
  // List.unmodifiable 足够(不深拷贝 StepResult 值对象)。
  final snapshot = List<StepResult>.unmodifiable(steps);
  for (final condition in conditions) {
    if (await condition(snapshot)) {
      return true;
    }
  }
  return false;
}

Future<provider.ToolMessage?> _executeResumedToolApprovals({
  required List<provider.LanguageModelMessage> messages,
  required ToolSet? tools,
  required ToolsContext toolsContext,
  required Object? toolApproval,
  required ToolCallRepairFunction? repairToolCall,
  required String? instructions,
  required provider.CancellationSignal? cancellation,
  required TimeoutConfiguration timeout,
  TelemetryDispatcher? dispatcher,
}) async {
  final approvals = collectToolApprovals(messages);
  if (approvals.isEmpty) {
    return null;
  }

  final parts = <provider.ToolContentPart>[];
  for (final approval in approvals.approvedToolApprovals) {
    if (approval.toolCall.providerExecuted == true) {
      continue;
    }
    final originalToolCall = _toolCallFromApprovalPart(approval.toolCall);
    if (toolApprovalMayBlockBeforeInput(
      toolApproval: toolApproval,
      toolCall: originalToolCall,
    )) {
      final approvalStatus = await resolveToolApprovalFromInput(
        toolApproval: toolApproval,
        toolCallId: approval.toolCall.toolCallId,
        toolName: approval.toolCall.toolName,
        input: approval.toolCall.input,
        toolCall: originalToolCall,
        providerExecuted: approval.toolCall.providerExecuted,
        providerMetadata: approval.toolCall.providerOptions,
        messages: approval.messages,
        tools: tools,
      );
      if (approvalStatus.type == ToolApprovalStatusType.denied) {
        parts.add(provider.ToolResultPart(
          toolCallId: approval.toolCall.toolCallId,
          toolName: approval.toolCall.toolName,
          output: provider.ToolResultExecutionDenied(
            reason: approvalStatus.reason,
          ),
        ));
        continue;
      }
    }

    final tool = tools?[approval.toolCall.toolName];
    if (tool == null || tool.execute == null) {
      throw StateError(
        'Cannot resume approved tool call ${approval.toolCall.toolCallId} '
        'because executable tool ${approval.toolCall.toolName} is unavailable',
      );
    }
    final parsedCall = await parseOrRepairToolCall(
      toolCall: originalToolCall,
      tools: tools,
      repairToolCall: repairToolCall,
      instructions: instructions,
      messages: approval.messages,
    );
    final toolCall = parsedCall.toolCall;
    if (toolCall.toolName != originalToolCall.toolName ||
        toolCall.toolCallId != originalToolCall.toolCallId) {
      throw StateError(
        'repairToolCall cannot change toolName or toolCallId after '
        'tool approval has been resolved.',
      );
    }
    final approvalStatus = await resolveToolApprovalFromInput(
      toolApproval: toolApproval,
      toolCallId: toolCall.toolCallId,
      toolName: toolCall.toolName,
      input: parsedCall.input,
      toolCall: toolCall,
      providerExecuted: toolCall.providerExecuted,
      providerMetadata: toolCall.providerMetadata,
      messages: approval.messages,
      tools: tools,
    );
    if (approvalStatus.type == ToolApprovalStatusType.denied) {
      parts.add(provider.ToolResultPart(
        toolCallId: approval.toolCall.toolCallId,
        toolName: approval.toolCall.toolName,
        output: provider.ToolResultExecutionDenied(
          reason: approvalStatus.reason,
        ),
      ));
      continue;
    }

    final input = parsedCall.input;
    final toolContext = _validateToolContext(
      toolName: toolCall.toolName,
      tool: tool,
      toolsContext: toolsContext,
    );
    if (dispatcher != null && dispatcher.isActive) {
      await dispatcher.dispatchToolExecutionStart(ToolExecutionStartEvent(
        callId: toolCall.toolCallId,
        toolCallId: toolCall.toolCallId,
        toolName: toolCall.toolName,
        input: input,
        toolContext: toolContext,
      ));
    }
    final resumedStopwatch = Stopwatch()..start();
    final stepScope = CancellationScope(
      parent: cancellation,
      timeout: timeout.step,
      label: 'Step',
    );
    final toolScope = CancellationScope(
      parent: stepScope.signal,
      timeout: timeout.forTool(toolCall.toolName),
      label: 'Tool ${toolCall.toolName}',
    );
    final Object? output;
    try {
      output = await interruptFutureOnCancellation(
        tool.execute!(
          input,
          ToolExecuteOptions(
            toolCallId: toolCall.toolCallId,
            messages: approval.messages,
            context: toolContext,
            cancellation: toolScope.signal,
          ),
        ),
        toolScope.signal,
      );
    } catch (error) {
      if (dispatcher != null && dispatcher.isActive) {
        await dispatcher.dispatchToolExecutionEnd(ToolExecutionEndError(
          callId: toolCall.toolCallId,
          toolCallId: toolCall.toolCallId,
          toolName: toolCall.toolName,
          error: error,
          toolExecutionMs: resumedStopwatch.elapsed.inMilliseconds,
        ));
      }
      rethrow;
    } finally {
      toolScope.dispose();
      stepScope.dispose();
    }
    if (dispatcher != null && dispatcher.isActive) {
      await dispatcher.dispatchToolExecutionEnd(ToolExecutionEndSuccess(
        callId: toolCall.toolCallId,
        toolCallId: toolCall.toolCallId,
        toolName: toolCall.toolName,
        output: output,
        toolExecutionMs: resumedStopwatch.elapsed.inMilliseconds,
      ));
    }
    final resultOutput = tool.toModelOutput != null
        ? tool.toModelOutput!(input, output)
        : _defaultToModelOutput(output);
    parts.add(provider.ToolResultPart(
      toolCallId: toolCall.toolCallId,
      toolName: toolCall.toolName,
      output: resultOutput,
    ));
  }
  for (final approval in approvals.deniedToolApprovals) {
    if (approval.toolCall.providerExecuted == true) {
      continue;
    }
    parts.add(provider.ToolResultPart(
      toolCallId: approval.toolCall.toolCallId,
      toolName: approval.toolCall.toolName,
      output: provider.ToolResultExecutionDenied(
        reason: approval.approvalResponse.reason,
      ),
    ));
  }

  if (parts.isEmpty) {
    return null;
  }
  return provider.ToolMessage(
    List<provider.ToolContentPart>.unmodifiable(parts),
  );
}

provider.ToolCall _toolCallFromApprovalPart(provider.ToolCallPart toolCall) {
  return provider.ToolCall(
    toolCallId: toolCall.toolCallId,
    toolName: toolCall.toolName,
    input: jsonEncode(toolCall.input),
    providerExecuted: toolCall.providerExecuted,
    providerMetadata: toolCall.providerOptions,
  );
}

Object? _validateToolContext({
  required String toolName,
  required Tool tool,
  required ToolsContext toolsContext,
}) {
  final context = toolsContext[toolName];
  final schema = tool.contextSchema;
  if (schema == null) {
    return context;
  }
  return validateTypes(context, JsonSchemaValidator.fromContract(schema));
}

/// 默认结果→模型输出映射:`String` → 文本结果,其余 → JSON 结果。
provider.ToolResultOutput _defaultToModelOutput(Object? output) {
  if (output is String) {
    return provider.ToolResultText(output);
  }
  return provider.ToolResultJson(output);
}

/// 把 `ToolResultOutput` 拆箱为 `provider.ToolResult.result` 的 JSON 值
/// (可为 `null`:工具合法返回 null 时原样保留,不规范化为 `{}`——否则
/// `toolResults` 与 `responseMessages` 观察到的结果会不一致)。
///
/// `ToolResultText`/`ToolResultJson` 是脊柱当前默认/自定义输出的主路径;
/// 其余审批/错误/多媒体变体(§1 非目标,暂不深度建模)在此做兜底映射,
/// 保证 `Tool.toModelOutput` 返回任意合法 `ToolResultOutput` 都不会让循环抛异常。
Object? _toolResultOutputValue(provider.ToolResultOutput output) {
  return switch (output) {
    provider.ToolResultText(:final value) => value,
    provider.ToolResultJson(:final value) => value,
    provider.ToolResultErrorText(:final value) => value,
    provider.ToolResultExecutionDenied(:final reason) =>
      reason ?? 'Tool execution denied',
    provider.ToolResultErrorJson(:final value) => value,
    provider.ToolResultContentOutput(:final items) => <String, Object?>{
        'items': [
          for (final item in items)
            switch (item) {
              provider.ToolResultTextItem(:final text) => <String, Object?>{
                  'type': 'text',
                  'text': text,
                },
              provider.ToolResultFileItem(
                :final data,
                :final mediaType,
                :final filename,
              ) =>
                <String, Object?>{
                  'type': 'file',
                  'mediaType': mediaType,
                  if (filename != null) 'filename': filename,
                  // 保留文件数据载荷(FileData:bytes/base64/url/reference),供
                  // 消费者从 toolResults.result 取回文件内容;此前仅取
                  // mediaType/filename 会丢失 data(§1 多媒体为非目标,但不应丢数据)。
                  'data': data,
                },
              provider.ToolResultCustomItem() => <String, Object?>{
                  'type': 'custom',
                },
            },
        ],
      },
  };
}

/// 判断 `ToolResultOutput` 是否为错误变体(`ToolResultErrorText`/
/// `ToolResultErrorJson`),供构造结果 API `provider.ToolResult.isError` 使用。
bool _isErrorOutput(provider.ToolResultOutput output) {
  return switch (output) {
    provider.ToolResultErrorText() => true,
    provider.ToolResultErrorJson() => true,
    _ => false,
  };
}

/// 把本步 `LanguageModelContent` 重建为一条 `provider.AssistantMessage`,
/// 追加进消息历史供下一步续接:text/reasoning/file/reasoning-file/custom 等可
/// 表示内容项 + tool-call + tool-approval-request + provider 侧已执行的
/// tool-result 均参与重建,避免多步工具流丢失模型上一步产出的
/// 文件/推理/自定义内容;SourceContent 暂无对应 assistant part,略过。
///
/// provider 已侧执行(`providerExecuted == true`)的调用会随一条自带的
/// `provider.ToolResult` 一起出现在本步内容里;若不将其重建进历史,
/// 下一步模型请求会丢失该结果,导致模型看不到 provider 侧已执行的产出。
provider.AssistantMessage _toAssistantMessage(
  List<provider.LanguageModelContent> content,
) {
  final parts = <provider.AssistantContentPart>[];
  for (final item in content) {
    if (item is provider.TextContent) {
      parts.add(provider.TextPart(
        item.text,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ReasoningContent) {
      parts.add(provider.ReasoningPart(
        item.text,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.FileContent) {
      parts.add(provider.FilePart(
        data: item.data,
        mediaType: item.mediaType,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ReasoningFileContent) {
      parts.add(provider.ReasoningFilePart(
        data: item.data,
        mediaType: item.mediaType,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.CustomContentBlock) {
      parts.add(provider.CustomPart(
        item.kind,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ToolCall) {
      parts.add(provider.ToolCallPart(
        toolCallId: item.toolCallId,
        toolName: item.toolName,
        input: jsonDecode(item.input),
        providerExecuted: item.providerExecuted,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ToolApprovalRequest) {
      parts.add(provider.ToolApprovalRequestPart(
        approvalId: item.approvalId,
        toolCallId: item.toolCallId,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ToolResult) {
      parts.add(provider.ToolResultPart(
        toolCallId: item.toolCallId,
        toolName: item.toolName,
        output: item.isError == true
            ? provider.ToolResultErrorJson(item.result)
            : provider.ToolResultJson(item.result),
        providerOptions: item.providerMetadata,
      ));
    }
  }
  // 内容列表冻结:该消息进入跨步复用的 prompt,provider/中间件的原地改动
  // 不得污染循环历史(理由同 convertToLanguageModelPrompt 的构造处冻结)。
  return provider.AssistantMessage(
    List<provider.AssistantContentPart>.unmodifiable(parts),
  );
}
