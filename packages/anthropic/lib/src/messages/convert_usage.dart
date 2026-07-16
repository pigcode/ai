import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 把 Anthropic Messages API 的 `usage` 对象转换为契约层
/// [LanguageModelUsage]。
///
/// 逻辑逐字对照上游 `convertAnthropicUsage`
/// (`convert-anthropic-usage.ts:44-109`):
///
/// - cache 两项 `?? 0` 兜底(:51-52);
/// - `iterations` 含 `fallback_message` 时直接用顶层 input/output
///   (顶层已反映 fallback 答案,:64-93);
/// - 否则过滤出 `message`/`compaction` 的 executor 迭代求和作为
///   input/output(`advisor_message` 计费口径不同,被排除);executor
///   迭代为空则回退顶层值;
/// - `inputTokens.total = input + cacheWrite + cacheRead`,cache 两项
///   恒取顶层;`outputTokens.text`/`reasoning` 恒为 null(:95-108);
/// - `raw` 取 [rawUsage],缺省时为 [usage] 本身(doGenerate 不传
///   rawUsage,language-model.ts:1367)。
LanguageModelUsage convertAnthropicUsage(
  JsonObject usage, {
  JsonObject? rawUsage,
}) {
  final cacheWriteTokens =
      (usage['cache_creation_input_tokens'] as num?)?.toInt() ?? 0;
  final cacheReadTokens =
      (usage['cache_read_input_tokens'] as num?)?.toInt() ?? 0;

  var inputTokens = (usage['input_tokens'] as num?)?.toInt() ?? 0;
  var outputTokens = (usage['output_tokens'] as num?)?.toInt() ?? 0;

  final iterations =
      (usage['iterations'] as List<Object?>?)?.whereType<JsonObject>();
  if (iterations != null && iterations.isNotEmpty) {
    // fallback_message 存在时顶层值已反映 fallback 答案,直接采用顶层。
    final servedByFallback =
        iterations.any((iteration) => iteration['type'] == 'fallback_message');
    if (!servedByFallback) {
      // executor 迭代 = message / compaction;advisor_message 排除。
      final executorIterations = iterations.where((iteration) {
        final type = iteration['type'];
        return type == 'message' || type == 'compaction';
      });
      if (executorIterations.isNotEmpty) {
        var summedInput = 0;
        var summedOutput = 0;
        for (final iteration in executorIterations) {
          summedInput += (iteration['input_tokens'] as num?)?.toInt() ?? 0;
          summedOutput += (iteration['output_tokens'] as num?)?.toInt() ?? 0;
        }
        inputTokens = summedInput;
        outputTokens = summedOutput;
      }
    }
  }

  return LanguageModelUsage(
    inputTokens: InputTokens(
      total: inputTokens + cacheWriteTokens + cacheReadTokens,
      noCache: inputTokens,
      cacheRead: cacheReadTokens,
      cacheWrite: cacheWriteTokens,
    ),
    outputTokens: OutputTokens(total: outputTokens),
    raw: rawUsage ?? usage,
  );
}
