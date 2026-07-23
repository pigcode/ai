import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:logging/logging.dart';

import '../generate_text/context.dart';
import '../generate_text/lifecycle_events.dart';
import '../generate_text/request_options_snapshot.dart';
import '../generate_text/step_result.dart';
import 'telemetry.dart';
import 'telemetry_events.dart';
import 'telemetry_registry.dart';
import 'telemetry_settings.dart';

final Logger _logger = Logger('pigcode_ai.telemetry');

/// 内部组件:把生成生命周期事件脱敏后扇出给生效的 telemetry 集成。
///
/// 每次 `generateText`/`streamText` 调用构造一个 dispatcher:解析生效集成集合
/// (`isEnabled==false` → 空;per-call integrations 非空则用之,否则用全局),
/// 从 `TelemetrySettings` 构造 [TelemetryMetadata] 注入每个回调,并按 record/include
/// 开关产出"投递给集成"的脱敏视图(不改原事件)。集成回调抛错被隔离并记 warning。
final class TelemetryDispatcher {
  /// 从 [settings] 构造 dispatcher。
  TelemetryDispatcher(TelemetrySettings? settings)
      : _integrations = _resolve(settings),
        // 调用时刻快照 context 白名单(深拷贝不可变):流式/异步下事件延后投递,
        // 若惰性读取调用方的可变 map,caller 事后改动会中途改白名单、泄露未包含
        // 的 context 键。与 integrations 快照及其他可变请求输入一致。
        _includeRuntimeContext = _snapshotRuntimeInclude(
          settings?.includeRuntimeContext,
        ),
        _includeToolsContext = _snapshotToolsInclude(
          settings?.includeToolsContext,
        ),
        _metadata = TelemetryMetadata(
          functionId: settings?.functionId,
          recordInputs: settings?.recordInputs ?? true,
          recordOutputs: settings?.recordOutputs ?? true,
        );

  final List<Telemetry> _integrations;
  final Map<String, bool>? _includeRuntimeContext;
  final Map<String, Map<String, bool>>? _includeToolsContext;
  final TelemetryMetadata _metadata;

  static Map<String, bool>? _snapshotRuntimeInclude(Map<String, bool>? m) =>
      m == null ? null : Map<String, bool>.unmodifiable(m);

  static Map<String, Map<String, bool>>? _snapshotToolsInclude(
    Map<String, Map<String, bool>>? m,
  ) =>
      m == null
          ? null
          : Map<String, Map<String, bool>>.unmodifiable({
              for (final e in m.entries)
                e.key: Map<String, bool>.unmodifiable(e.value),
            });

  static List<Telemetry> _resolve(TelemetrySettings? settings) {
    if (settings?.isEnabled == false) return const [];
    final local = settings?.integrations ?? const [];
    // 调用时刻快照 per-call integrations:流式下事件延后投递,若返回调用方的
    // 可变列表,caller 在 streamText() 返回后(或回调在 _fan 迭代中)改动它会
    // 污染已开始的调用、破坏隔离。与全局 registry 的不可变快照行为一致。
    if (local.isNotEmpty) return List<Telemetry>.unmodifiable(local);
    return globalTelemetryIntegrations();
  }

  /// 是否有生效集成。接线方可用它跳过无谓的事件构造。
  bool get isActive => _integrations.isNotEmpty;

  // ---- dispatch 入口(供 generate/stream 接线调用) ----

  /// 派发 operation 开始。
  Future<void> dispatchStart(GenerateTextStartEvent e) async {
    if (!isActive) return;
    final view = _metadata.recordInputs
        ? e
        : GenerateTextStartEvent(model: e.model, messages: const []);
    await _fan((i) => i.onStart(view, _metadata));
  }

  /// 派发单步开始。
  Future<void> dispatchStepStart(GenerateTextStepStartEvent e) async {
    if (!isActive) return;
    final view = GenerateTextStepStartEvent(
      stepNumber: e.stepNumber,
      model: e.model,
      messages: _metadata.recordInputs ? e.messages : const [],
      steps: e.steps.map(_sanitizeStep).toList(growable: false),
    );
    await _fan((i) => i.onStepStart(view, _metadata));
  }

  /// 派发模型调用开始。
  Future<void> dispatchLanguageModelCallStart(
      LanguageModelCallStartEvent e) async {
    if (!isActive) return;
    final view = _metadata.recordInputs
        ? e
        : LanguageModelCallStartEvent(
            callId: e.callId,
            providerId: e.providerId,
            modelId: e.modelId,
            stepNumber: e.stepNumber,
            messages: const [],
          );
    await _fan((i) => i.onLanguageModelCallStart(view, _metadata));
  }

  /// 派发模型调用结束。
  Future<void> dispatchLanguageModelCallEnd(LanguageModelCallEndEvent e) async {
    if (!isActive) return;
    // 恒重建投递视图:content 经 _sanitizeContent(按 recordInputs 脱敏 ToolCall、
    // 恒深冻 ToolResult.result),response 经 _sanitizeResponse(按 recordInputs
    // 剥离或深冻 body)——集成拿到的可变结构改不动,不会污染尚未拷入
    // StepResult/responseMessages 的 provider 原始对象(观察者不影响生成)。
    final view = LanguageModelCallEndEvent(
      callId: e.callId,
      providerId: e.providerId,
      modelId: e.modelId,
      stepNumber: e.stepNumber,
      content: _metadata.recordOutputs ? _sanitizeContent(e.content) : const [],
      usage: e.usage,
      finishReason: e.finishReason,
      warnings: e.warnings,
      response: _metadata.recordOutputs ? _sanitizeResponse(e.response) : null,
      responseTime: e.responseTime,
    );
    await _fan((i) => i.onLanguageModelCallEnd(view, _metadata));
  }

  /// 派发工具执行开始。
  Future<void> dispatchToolExecutionStart(ToolExecutionStartEvent e) async {
    if (!isActive) return;
    final view = ToolExecutionStartEvent(
      callId: e.callId,
      toolCallId: e.toolCallId,
      toolName: e.toolName,
      // 深不可变视图:input 与后续 tool.execute 用的是同一份可变 JSON,若原样
      // 递给集成,集成原地改动会改掉实际工具参数(观察者不得影响生成)。
      input: _metadata.recordInputs ? deepUnmodifiableValue(e.input) : null,
      toolContext: deepUnmodifiableValue(
        _sanitizeToolContext(e.toolName, e.toolContext),
      ),
    );
    await _fan((i) => i.onToolExecutionStart(view, _metadata));
  }

  /// 派发工具执行结束。
  Future<void> dispatchToolExecutionEnd(ToolExecutionEndEvent e) async {
    if (!isActive) return;
    // success 变体恒重建:output 与随后 toModelOutput/默认映射消费的是同一份
    // 可变对象,原样递给集成会让回调改动污染喂回模型的工具结果(观察者不得
    // 影响生成)——深不可变视图 + recordOutputs 脱敏一并处理。error 变体的
    // error 对象原样透传(与 onError 一致)。
    final ToolExecutionEndEvent view = switch (e) {
      ToolExecutionEndSuccess s => ToolExecutionEndSuccess(
          callId: s.callId,
          toolCallId: s.toolCallId,
          toolName: s.toolName,
          output:
              _metadata.recordOutputs ? deepUnmodifiableValue(s.output) : null,
          toolExecutionMs: s.toolExecutionMs,
        ),
      ToolExecutionEndError _ => e,
    };
    await _fan((i) => i.onToolExecutionEnd(view, _metadata));
  }

  /// 派发单步结束。
  Future<void> dispatchStepEnd(StepResult step) async {
    if (!isActive) return;
    final view = _sanitizeStep(step);
    await _fan((i) => i.onStepEnd(view, _metadata));
  }

  /// 派发 operation 结束。
  Future<void> dispatchEnd(GenerateTextEndEvent e) async {
    if (!isActive) return;
    final view = GenerateTextEndEvent(
      steps: e.steps.map(_sanitizeStep).toList(growable: false),
    );
    await _fan((i) => i.onEnd(view, _metadata));
  }

  /// 派发调用方主动取消。已完成步骤走与 onEnd 相同的输出脱敏和 context
  /// 白名单过滤；取消原因按上游契约原样传递。
  Future<void> dispatchAbort(GenerateTextAbortEvent e) async {
    if (!isActive) return;
    final view = GenerateTextAbortEvent(
      steps: e.steps.map(_sanitizeStep).toList(growable: false),
      reason: e.reason,
    );
    await _fan((i) => i.onAbort(view, _metadata));
  }

  /// 派发错误。错误对象总体原样传递(对齐上游 onError;通用错误脱敏是集成方
  /// 责任,已文档化);唯一例外:契约层 [provider.InvalidPromptError] 的 `prompt`
  /// 字段携带调用方原始输入,`recordInputs=false` 时重建为 prompt=null 的副本
  /// 再派——该错误由本层 preflight 主动派入 telemetry,不得绕过输入脱敏。
  Future<void> dispatchError(Object? error) async {
    if (!isActive) return;
    final view =
        (!_metadata.recordInputs && error is provider.InvalidPromptError)
            ? provider.InvalidPromptError(
                prompt: null,
                message: error.message,
                cause: error.cause,
              )
            : error;
    await _fan((i) => i.onError(view, _metadata));
  }

  // ---- 内部 ----

  /// 逐集成调用 [call],await 完成;单集成抛错被隔离并记 warning(不冒泡)。
  Future<void> _fan(FutureOr<void> Function(Telemetry) call) async {
    for (final integration in _integrations) {
      try {
        final result = call(integration);
        if (result is Future) await result;
      } catch (error, stackTrace) {
        _logger.warning(
          'telemetry integration threw and was isolated',
          error,
          stackTrace,
        );
      }
    }
  }

  /// 对 [StepResult] 产出脱敏视图:`recordOutputs=false` 清空 output 侧
  /// (content/executedToolResults/toolResultOutputs/response),保留
  /// usage/finishReason/performance/warnings;并按白名单过滤
  /// runtimeContext/toolsContext(默认全排除)。
  StepResult _sanitizeStep(StepResult s) {
    final keepOutputs = _metadata.recordOutputs;
    return StepResult(
      // keepOutputs 时保留 content,但仍按 recordInputs 脱敏其中 ToolCall 的 input
      // (工具参数受 recordInputs 管);recordOutputs=false 时整体清空。
      content: keepOutputs
          ? _sanitizeContent(s.content)
          : const <provider.LanguageModelContent>[],
      finishReason: s.finishReason,
      usage: s.usage,
      response: keepOutputs ? _sanitizeResponse(s.response) : null,
      // 输出侧元数据(源自模型响应)归 recordOutputs 管:false → null;
      // true → 按引用透传,不深冻(providerMetadata 全库按引用共享的既有
      // 文档化裁决,契约层才是深冻的正确修复位)。三路(onStepStart 内嵌
      // steps / onStepEnd / onEnd 内嵌 steps)共走本重建,实现即此一处。
      providerMetadata: keepOutputs ? s.providerMetadata : null,
      // keepOutputs 时同样深冻:executedToolResults 的 result 与
      // toolResultOutputs 的 JSON 载荷与真实 StepResult(流式下还包括下一步
      // prompt 的工具输出)共享,集成改动不得污染生成(观察者隔离,与
      // ToolExecutionEnd/LanguageModelCallEnd 一致)。
      // denied 的拆箱 result 载荷就是审批 reason(输入侧):recordInputs=false 时
      // 按与 toolResultOutputs 的一一对应索引识别 denied 项,替换为不含 reason
      // 的默认文案(与 _toolResultOutputValue 的兜底文案一致)。
      executedToolResults: keepOutputs
          ? List<provider.ToolResult>.unmodifiable([
              for (var i = 0; i < s.executedToolResults.length; i++)
                if (!_metadata.recordInputs &&
                    i < s.toolResultOutputs.length &&
                    s.toolResultOutputs[i]
                        is provider.ToolResultExecutionDenied)
                  provider.ToolResult(
                    toolCallId: s.executedToolResults[i].toolCallId,
                    toolName: s.executedToolResults[i].toolName,
                    result: 'Tool execution denied',
                    isError: s.executedToolResults[i].isError,
                    preliminary: s.executedToolResults[i].preliminary,
                    isDynamic: s.executedToolResults[i].isDynamic,
                    providerMetadata: s.executedToolResults[i].providerMetadata,
                  )
                else
                  _freezeToolResult(s.executedToolResults[i]),
            ])
          : const <provider.ToolResult>[],
      toolResultOutputs: keepOutputs
          ? _freezeToolResultOutputs(s.toolResultOutputs)
          : const <provider.ToolResultOutput>[],
      toolApprovalResponses: _redactApprovalResponses(s.toolApprovalResponses),
      warnings: s.warnings,
      runtimeContext: _filterRuntimeContext(s.runtimeContext),
      toolsContext: _filterToolsContext(s.toolsContext),
      performance: s.performance,
    );
  }

  /// runtime context 顶层键白名单过滤(默认全排除)。
  RuntimeContext _filterRuntimeContext(RuntimeContext ctx) {
    final include = _includeRuntimeContext;
    if (include == null || ctx.isEmpty) return const {};
    return {
      for (final entry in ctx.entries)
        if (include[entry.key] == true) entry.key: entry.value,
    };
  }

  /// tools context(键为工具名)按 includeToolsContext 过滤;每工具的 context
  /// 仅当为 `Map<String,Object?>` 时按键过滤,非 map 排除;未白名单的工具排除。
  ToolsContext _filterToolsContext(ToolsContext toolsCtx) {
    final include = _includeToolsContext;
    if (include == null || toolsCtx.isEmpty) return const {};
    final result = <String, Object?>{};
    for (final entry in toolsCtx.entries) {
      final forTool = include[entry.key];
      if (forTool == null) continue;
      final filtered = _filterToolContextValue(entry.value, forTool);
      if (filtered != null) result[entry.key] = filtered;
    }
    return result;
  }

  /// 单个工具 context 的键白名单过滤(仅对 map 生效,非 map 返回 null=排除)。
  Object? _sanitizeToolContext(String toolName, Object? ctx) {
    final forTool = _includeToolsContext?[toolName];
    if (forTool == null) return null;
    return _filterToolContextValue(ctx, forTool);
  }

  Object? _filterToolContextValue(Object? ctx, Map<String, bool> include) {
    if (ctx is Map<String, Object?>) {
      return {
        for (final entry in ctx.entries)
          if (include[entry.key] == true) entry.key: entry.value,
      };
    }
    return null;
  }

  /// recordInputs=false 时,把 content 里每个 [provider.ToolCall] 的 `input`
  /// (工具参数,input 侧)置空,其余内容项原样保留;recordInputs=true 时原样返回。
  /// 使工具参数在所有 telemetry 出口(ToolExecutionStart.input 与模型响应 content)
  /// 都一致受 recordInputs 管辖,不从 content 旁路泄露。
  List<provider.LanguageModelContent> _sanitizeContent(
    List<provider.LanguageModelContent> content,
  ) {
    return content.map<provider.LanguageModelContent>((c) {
      if (c is provider.ToolCall && !_metadata.recordInputs) {
        return provider.ToolCall(
          toolCallId: c.toolCallId,
          toolName: c.toolName,
          // 契约定义 input 为 stringified JSON;脱敏值用合法 JSON '{}',
          // 避免集成 jsonDecode 脱敏事件时崩溃。
          input: '{}',
          providerExecuted: c.providerExecuted,
          isDynamic: c.isDynamic,
          // providerMetadata 也置空:provider 常把原始 tool-call item(含
          // 参数/命令,如 OpenAI Responses / custom / shell 工具)存于此,
          // 否则工具参数会绕过 input 脱敏从 metadata 泄露。
          providerMetadata: null,
        );
      }
      if (c is provider.ToolResult) {
        // provider 直出的 ToolResult.result 可能是可变 Map/List,且此时尚未
        // 拷入 StepResult——深冻视图防集成改动污染实际结果。其余 content 项的
        // providerMetadata 按引用透传(与 DataContent 叶子同约定:约定不可变)。
        return _freezeToolResult(c);
      }
      return c;
    }).toList(growable: false);
  }

  /// [provider.ToolResult] 的深冻视图:result(可变 JSON)深冻,其余字段原样。
  provider.ToolResult _freezeToolResult(provider.ToolResult r) {
    return provider.ToolResult(
      toolCallId: r.toolCallId,
      toolName: r.toolName,
      result: deepUnmodifiableValue(r.result),
      isError: r.isError,
      preliminary: r.preliminary,
      isDynamic: r.isDynamic,
      providerMetadata: r.providerMetadata,
    );
  }

  /// [provider.ToolResultOutput] 列表的深冻视图:Json/ErrorJson 变体的可变
  /// JSON 载荷深冻,ContentOutput 的 items 列表重建为不可变;Text/ErrorText/
  /// Denied 载荷为不可变 String,原样。providerOptions 按引用透传(先例)。
  List<provider.ToolResultOutput> _freezeToolResultOutputs(
    List<provider.ToolResultOutput> outputs,
  ) {
    return outputs.map<provider.ToolResultOutput>((o) {
      return switch (o) {
        provider.ToolResultJson j => provider.ToolResultJson(
            deepUnmodifiableValue(j.value),
            providerOptions: j.providerOptions,
          ),
        provider.ToolResultErrorJson j => provider.ToolResultErrorJson(
            deepUnmodifiableValue(j.value),
            providerOptions: j.providerOptions,
          ),
        provider.ToolResultContentOutput c => provider.ToolResultContentOutput(
            List<provider.ToolResultContentItem>.unmodifiable(c.items),
          ),
        // recordInputs=false:denied 的 reason/providerOptions 来自用户审批
        // 消息(输入侧),与 toolApprovalResponses 的脱敏一致,一并剥离。
        provider.ToolResultExecutionDenied _ when !_metadata.recordInputs =>
          const provider.ToolResultExecutionDenied(),
        _ => o,
      };
    }).toList(growable: false);
  }

  /// response 的投递视图:recordInputs=false 时剥离 [provider.ResponseInfo.body]
  /// (不透明的原始 provider 响应体,含工具参数等输入侧数据,无法只删工具参数),
  /// 保留 id/timestamp/modelId/headers 元数据;否则 body 深冻——它可能是可变
  /// Map/List 且与实际结果共享,集成改动不得污染生成。
  provider.ResponseInfo? _sanitizeResponse(provider.ResponseInfo? r) {
    if (r == null) return null;
    return provider.ResponseInfo(
      id: r.id,
      timestamp: r.timestamp,
      modelId: r.modelId,
      // headers(Map<String,String>)与真实结果共享,同样给不可变视图。
      headers: r.headers == null
          ? null
          : Map<String, String>.unmodifiable(r.headers!),
      body: _metadata.recordInputs ? deepUnmodifiableValue(r.body) : null,
    );
  }

  /// recordInputs=false 时,清空审批响应的 `reason` 与 `providerOptions`——它们
  /// 来自用户审批消息、作为输入喂给下一步模型;保留 approvalId 与 approved
  /// (决定本身非敏感)。recordInputs=true 时原样返回。
  List<provider.ToolApprovalResponsePart> _redactApprovalResponses(
    List<provider.ToolApprovalResponsePart> responses,
  ) {
    if (_metadata.recordInputs || responses.isEmpty) return responses;
    return responses
        .map((r) => provider.ToolApprovalResponsePart(
              approvalId: r.approvalId,
              approved: r.approved,
            ))
        .toList(growable: false);
  }
}
