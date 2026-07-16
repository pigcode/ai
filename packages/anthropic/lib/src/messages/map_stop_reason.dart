import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 把 Anthropic Messages API 的 `stop_reason` 字符串映射为契约层
/// [LanguageModelFinishReason]。
///
/// 映射表逐字对照上游 `mapAnthropicStopReason`
/// (`map-anthropic-stop-reason.ts:6-30`):
///
/// - `pause_turn` / `end_turn` / `stop_sequence` → stop
/// - `refusal` → contentFilter
/// - `tool_use` → [isJsonResponseFromTool] 为 true 时 stop,否则 toolCalls
///   (json 响应工具模式下的 tool_use 只是结构化输出的载体,不算真实工具调用)
/// - `max_tokens` / `model_context_window_exceeded` → length
/// - `compaction` / 未知 / null → other
///
/// `raw` 原样保留传入值(null 时 `raw` 亦为 null,:1360-1366)。
LanguageModelFinishReason mapAnthropicStopReason(
  String? stopReason, {
  required bool isJsonResponseFromTool,
}) {
  final unified = switch (stopReason) {
    'pause_turn' || 'end_turn' || 'stop_sequence' => FinishReasonType.stop,
    'refusal' => FinishReasonType.contentFilter,
    'tool_use' => isJsonResponseFromTool
        ? FinishReasonType.stop
        : FinishReasonType.toolCalls,
    'max_tokens' || 'model_context_window_exceeded' => FinishReasonType.length,
    _ => FinishReasonType.other,
  };
  return LanguageModelFinishReason(unified, raw: stopReason);
}
