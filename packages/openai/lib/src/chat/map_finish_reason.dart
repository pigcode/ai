import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 把 OpenAI Chat Completions 的 `finish_reason` 字符串映射为契约层
/// [LanguageModelFinishReason]。
///
/// 映射表逐字对照 v7 `mapOpenAIFinishReason`(`raw/map-openai-finish-reason.ts`);
/// `raw` 字段原样保留传入值(不做额外转换,`null` 时 `raw` 亦为 `null`)。
LanguageModelFinishReason mapOpenAiChatFinishReason(String? finishReason) {
  final unified = switch (finishReason) {
    'stop' => FinishReasonType.stop,
    'length' => FinishReasonType.length,
    'content_filter' => FinishReasonType.contentFilter,
    'function_call' || 'tool_calls' => FinishReasonType.toolCalls,
    _ => FinishReasonType.other,
  };
  return LanguageModelFinishReason(unified, raw: finishReason);
}
