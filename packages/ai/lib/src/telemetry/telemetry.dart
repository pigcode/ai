import 'dart:async';

import '../generate_text/lifecycle_events.dart';
import '../generate_text/step_result.dart';
import 'telemetry_events.dart';

/// telemetry 事件的公共元数据,由 dispatcher 在投递时从 `TelemetrySettings` 注入,
/// 作为每个回调的第二参。让集成方能按 [functionId] 分组、并知晓 input/output
/// 是否被记录。
final class TelemetryMetadata {
  /// 创建 telemetry 元数据。[recordInputs]/[recordOutputs] 为已解析的有效值。
  const TelemetryMetadata({
    this.functionId,
    this.recordInputs = true,
    this.recordOutputs = true,
  });

  /// 分组标识,来自 `TelemetrySettings.functionId`。
  final String? functionId;

  /// 是否记录了 input(已解析:`settings.recordInputs ?? true`)。
  final bool recordInputs;

  /// 是否记录了 output(已解析:`settings.recordOutputs ?? true`)。
  final bool recordOutputs;
}

/// telemetry 集成接口。用户以 `class X with Telemetry` 混入并覆写关心的方法来
/// 订阅生成生命周期。方法均可选(有 no-op 默认实现),返回 `void` 或 `Future`。
///
/// 用 `mixin` 而非 `abstract interface class` + `implements`:Dart 的 `implements`
/// 不继承默认实现,会强制实现全部方法;`mixin` + `with` 可只覆写子集,且不占用
/// 单继承位。每个回调收 `event` + 由 dispatcher 注入的 [TelemetryMetadata]。
///
/// v1 不含 `onAbort`——pigcode 的取消是协作式的,延后到有贯穿式取消终止语义时再补。
mixin Telemetry {
  /// 生成操作开始(operation 级)。
  FutureOr<void> onStart(GenerateTextStartEvent e, TelemetryMetadata m) {}

  /// 单步(单次 LLM 调用)开始。
  FutureOr<void> onStepStart(
      GenerateTextStepStartEvent e, TelemetryMetadata m) {}

  /// 模型调用开始(仅 model 侧,工具执行前)。
  FutureOr<void> onLanguageModelCallStart(
      LanguageModelCallStartEvent e, TelemetryMetadata m) {}

  /// 模型调用结束(模型响应解析后、工具执行前)。
  FutureOr<void> onLanguageModelCallEnd(
      LanguageModelCallEndEvent e, TelemetryMetadata m) {}

  /// 工具执行开始(`execute` 前)。
  FutureOr<void> onToolExecutionStart(
      ToolExecutionStartEvent e, TelemetryMetadata m) {}

  /// 工具执行结束(成功或失败,见 [ToolExecutionEndEvent] 子类)。
  FutureOr<void> onToolExecutionEnd(
      ToolExecutionEndEvent e, TelemetryMetadata m) {}

  /// 单步结束,携带该步 [StepResult]。
  FutureOr<void> onStepEnd(StepResult step, TelemetryMetadata m) {}

  /// 生成操作结束(全部步骤 + 结构化输出解析成功后)。
  FutureOr<void> onEnd(GenerateTextEndEvent e, TelemetryMetadata m) {}

  /// 生成生命周期内发生不可恢复错误。[error] 无类型(可能是 `AiError`、`Error`
  /// 或任意抛出值)。
  FutureOr<void> onError(Object? error, TelemetryMetadata m) {}
}
