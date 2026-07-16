import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:equatable/equatable.dart';

/// chat 响应/chunk 中提取出的响应侧元数据(`id`/`created`/`model`)。
final class OpenAiChatResponseMetadata with EquatableMixin {
  /// 构造一份响应元数据;三字段均可缺省。
  const OpenAiChatResponseMetadata({this.id, this.timestamp, this.modelId});

  /// 响应 id,wire 字段 `id`。
  final String? id;

  /// 响应时间戳,由 wire 字段 `created`(Unix 秒)换算而来。
  final DateTime? timestamp;

  /// 实际使用的模型 id,wire 字段 `model`。
  final String? modelId;

  @override
  List<Object?> get props => [id, timestamp, modelId];
}

/// 从 chat 响应体或 chunk 的顶层字段提取响应元数据。
///
/// [value] 为响应/chunk 的顶层 JSON 对象,取 `id`/`model`/`created` 三键。
/// `created` 判空按 Global Constraints 统一 `!= null`(主动偏离 v7 chat 的
/// 真值判断 `created ?`——`created == 0` 在本实现中**会**产出
/// `timestamp: DateTime.fromMillisecondsSinceEpoch(0)`,而非 v7 的
/// `undefined`;这是 spec 已确认的偏离,理由是采纳 compatible 包的保守
/// 策略,避免 `0` 这个合法但边界的时间戳被误判为"无时间戳")。
OpenAiChatResponseMetadata getOpenAiChatResponseMetadata(JsonObject value) {
  final created = value['created'] as num?;
  return OpenAiChatResponseMetadata(
    id: value['id'] as String?,
    modelId: value['model'] as String?,
    timestamp: created != null
        ? DateTime.fromMillisecondsSinceEpoch(created.toInt() * 1000)
        : null,
  );
}
