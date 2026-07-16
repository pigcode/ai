import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 把 OpenAI Responses API 的 `incomplete_details.reason` 映射为契约
/// [LanguageModelFinishReason]。
///
/// 逐字对照 raw `map-openai-responses-finish-reason.ts`:判定完全依赖
/// `incomplete_details.reason`(仅未完成响应才有值),不存在类似 Chat
/// wire 的顶层 `finish_reason` 字段;[hasFunctionCall] 是调用方在遍历
/// output/流事件时手动维护的旁路标志(遇到 client 侧 function_call 就
/// 置 true),用于在没有 `incomplete_details` 时区分 `stop` 还是
/// `tool-calls`。
LanguageModelFinishReason mapOpenAiResponsesFinishReason({
  required String? incompleteReason,
  required bool hasFunctionCall,
}) {
  final unified = switch (incompleteReason) {
    null =>
      hasFunctionCall ? FinishReasonType.toolCalls : FinishReasonType.stop,
    'max_output_tokens' => FinishReasonType.length,
    'content_filter' => FinishReasonType.contentFilter,
    _ => hasFunctionCall ? FinishReasonType.toolCalls : FinishReasonType.other,
  };

  return LanguageModelFinishReason(unified, raw: incompleteReason);
}
