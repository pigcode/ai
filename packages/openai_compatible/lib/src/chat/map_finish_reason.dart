import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 把 OpenAI 兼容 Chat Completions 的 `finish_reason` 字符串映射为契约层
/// [LanguageModelFinishReason]。
///
/// 映射表逐字对照 raw `compatible__map-openai-compatible-finish-reason.ts`
/// 的 `mapOpenAICompatibleFinishReason`(与 `pigcode_ai_openai` 的
/// `mapOpenAiChatFinishReason` 使用同一张映射表,无行为差异);`raw` 字段
/// 原样保留传入值(不做额外转换,`null` 时 `raw` 亦为 `null`)。
LanguageModelFinishReason mapOpenAiCompatibleFinishReason(String? reason) {
  final unified = switch (reason) {
    'stop' => FinishReasonType.stop,
    'length' => FinishReasonType.length,
    'content_filter' => FinishReasonType.contentFilter,
    'function_call' || 'tool_calls' => FinishReasonType.toolCalls,
    _ => FinishReasonType.other,
  };
  return LanguageModelFinishReason(unified, raw: reason);
}
