import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 把 OpenAI Chat Completions 的 `usage` 对象转换为契约层
/// [LanguageModelUsage]。
///
/// 两级判空语义逐字对照 v7 `convertOpenAIChatUsage`
/// (`raw/convert-openai-chat-usage.ts`):整个 `usage` 为 `null` 时返回
/// 全字段 `null` 的空壳;`usage` 非 `null` 时才对内部各数值字段做 `?? 0`
/// 兜底再做减法——不能对每个字段单独做 `?? 0`,否则 `usage == null` 时会
/// 得到 `0` 而非契约要求的 `null`。
LanguageModelUsage convertOpenAiChatUsage(JsonObject? usage) {
  if (usage == null) {
    return const LanguageModelUsage(
      inputTokens: InputTokens(),
      outputTokens: OutputTokens(),
    );
  }

  final promptTokens = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
  final completionTokens = (usage['completion_tokens'] as num?)?.toInt() ?? 0;
  final promptDetails = usage['prompt_tokens_details'] as JsonObject?;
  final completionDetails = usage['completion_tokens_details'] as JsonObject?;
  final cachedTokens = (promptDetails?['cached_tokens'] as num?)?.toInt() ?? 0;
  final reasoningTokens =
      (completionDetails?['reasoning_tokens'] as num?)?.toInt() ?? 0;

  return LanguageModelUsage(
    inputTokens: InputTokens(
      total: promptTokens,
      noCache: promptTokens - cachedTokens,
      cacheRead: cachedTokens,
    ),
    outputTokens: OutputTokens(
      total: completionTokens,
      text: completionTokens - reasoningTokens,
      reasoning: reasoningTokens,
    ),
    raw: usage,
  );
}
