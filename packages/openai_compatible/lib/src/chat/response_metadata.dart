import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 从 OpenAI 兼容 chat 响应体或 chunk 的顶层字段提取响应元数据。
///
/// [body] 为响应/chunk 的顶层 JSON 对象,取 `id`/`model`/`created` 三键。
/// `created` 判空按 raw `compatible__get-response-metadata.ts`
/// (`created != null ? new Date(created * 1000) : undefined`)与 Global
/// Constraints(spec §4)统一用 `!= null`——`created == 0` 会产出
/// `DateTime.fromMillisecondsSinceEpoch(0)` 而非 `null`,这是对上游语义
/// 的直接照抄,非本包主动偏离。
ResponseInfo getOpenAiCompatibleResponseMetadata(JsonObject body) {
  final created = body['created'] as num?;
  return ResponseInfo(
    id: body['id'] as String?,
    modelId: body['model'] as String?,
    timestamp: created != null
        ? DateTime.fromMillisecondsSinceEpoch(created.toInt() * 1000)
        : null,
  );
}
