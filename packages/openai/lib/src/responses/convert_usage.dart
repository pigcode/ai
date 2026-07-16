import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 把 OpenAI Responses API 的原始 `usage` 对象转换为契约
/// [LanguageModelUsage]。
///
/// 两级判空,逐字对照 raw `convert-openai-responses-usage.ts`:
/// - [usage] 为 `null` → 返回全 `undefined`(Dart `null`)的壳,`raw` 也
///   为 `null`。
/// - 非空时:`input_tokens`/`output_tokens` 必存在(响应体校验层保证);
///   `cached_tokens`/`reasoning_tokens` 各自 `?? 0` 折算后做减法得到
///   `noCache`/`text`;`cacheWrite` 恒为 `null`(wire 无对应字段,与 chat
///   wire 同构);`raw` 原样保留整个 usage 对象(含未映射的
///   `orchestration_*` 编排 token 字段,不强行加新具名字段,对齐 raw
///   报告 §4.2 的既定策略)。
LanguageModelUsage convertOpenAiResponsesUsage(JsonObject? usage) {
  if (usage == null) {
    return const LanguageModelUsage(
      inputTokens: InputTokens(),
      outputTokens: OutputTokens(),
    );
  }

  final inputTokens = usage['input_tokens'] as int?;
  final outputTokens = usage['output_tokens'] as int?;
  final inputDetails = usage['input_tokens_details'] as JsonObject?;
  final outputDetails = usage['output_tokens_details'] as JsonObject?;
  final cachedTokens = (inputDetails?['cached_tokens'] as int?) ?? 0;
  final reasoningTokens = (outputDetails?['reasoning_tokens'] as int?) ?? 0;

  return LanguageModelUsage(
    inputTokens: InputTokens(
      total: inputTokens,
      noCache: inputTokens == null ? null : inputTokens - cachedTokens,
      cacheRead: cachedTokens,
    ),
    outputTokens: OutputTokens(
      total: outputTokens,
      text: outputTokens == null ? null : outputTokens - reasoningTokens,
      reasoning: reasoningTokens,
    ),
    raw: usage,
  );
}
