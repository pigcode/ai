import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 从 API 响应中提取 provider 专属元数据的可插拔钩子。
///
/// 逐字对齐 raw `compatible__openai-compatible-metadata-extractor.ts`
/// 的结构类型声明:上游是纯 TS 接口(无默认实现),Dart 侧落地为函数字段
/// 值对象,与契约包中间件同风格。
///
/// 本类型**没有默认实例**:`OpenAiCompatibleChatConfig.metadataExtractor`
/// 字段可空,`null` 即表示"不提取元数据"(no-op),不额外定义一个等价的
/// 具名空实现,避免同一语义有两种表达。
final class MetadataExtractor {
  /// 用给定的两个提取函数构造一个元数据提取器。
  const MetadataExtractor({
    required this.extractMetadata,
    required this.createStreamExtractor,
  });

  /// 从完整的非流式响应体中提取 provider 元数据。
  ///
  /// [parsedBody] 是响应体解析后的 JSON 值(对照 raw `parsedBody: unknown`)。
  /// 返回的元数据应以 provider id 为键(对照 raw 注释),无可用元数据时返回
  /// `null`。
  final Future<ProviderMetadata?> Function(JsonValue parsedBody)
      extractMetadata;

  /// 创建一个新的流级提取器。
  ///
  /// **每次 `doStream` 调用都应调用本函数产出一个新实例**:返回的
  /// [StreamMetadataExtractor] 内部会随 [StreamMetadataExtractor.processChunk]
  /// 调用累积状态,跨请求复用同一实例会导致不同请求的数据相互串扰。
  final StreamMetadataExtractor Function() createStreamExtractor;
}

/// 单次流式请求生命周期内的元数据提取器(由
/// [MetadataExtractor.createStreamExtractor] 每次新建)。
final class StreamMetadataExtractor {
  /// 用给定的分块处理函数与最终构建函数构造一个流级提取器。
  const StreamMetadataExtractor({
    required this.processChunk,
    required this.buildMetadata,
  });

  /// 处理流中的单个 chunk(解析后的 JSON 值),用于累积跨 chunk 的元数据状态。
  ///
  /// 纯副作用调用,不返回值;流结束前会针对每个 chunk 调用一次。
  final void Function(JsonValue parsedChunk) processChunk;

  /// 流结束后调用一次,基于累积的状态构建最终元数据。
  ///
  /// 无可用元数据时返回 `null`。
  final ProviderMetadata? Function() buildMetadata;
}
