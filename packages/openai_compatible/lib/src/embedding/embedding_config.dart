import 'package:http/http.dart' as http;

import '../internal/error_structure.dart';

/// `OpenAiCompatibleEmbeddingModel` 的运行时配置。
///
/// 独立小型 config,**不复用** `OpenAiCompatibleChatConfig`:后者的
/// `includeUsage`/`supportsStructuredOutputs`/`metadataExtractor`/
/// `supportedUrls`/`transformRequestBody`/`convertUsage` 六项均是 chat
/// 专属,embedding wire 无对应语义——照抄 raw 的分离决策(raw
/// `compatible_emb__openai-compatible-embedding-model.ts` 的
/// `OpenAICompatibleEmbeddingConfig` 就是与 chat config 互相独立的类型)。
final class OpenAiCompatibleEmbeddingConfig {
  /// 用给定字段构造一份配置。
  const OpenAiCompatibleEmbeddingConfig({
    required this.providerName,
    required this.url,
    required this.headers,
    this.client,
    this.errorStructure,
    this.maxEmbeddingsPerCall = 2048,
    this.supportsParallelCalls = true,
  });

  /// provider 标识(纯 name,不含 `.embedding` 后缀;模型的 `provider`
  /// getter 在此基础上拼接)。同时也是 providerOptions 的解析 key(单一
  /// 路径,与 chat wire 同一裁决)。
  final String providerName;

  /// 由请求路径(如 `'/embeddings'`)构造完整请求 URL 的闭包;queryParams
  /// 的拼接已在工厂构造该闭包时完成,本文件不关心。
  final Uri Function(String path) url;

  /// 每次请求求值一次的 header 构造函数。
  final Map<String, String> Function() headers;

  /// 可选注入的 HTTP client。
  final http.Client? client;

  /// 错误体结构(校验器 + 消息提取器 + 可选可重试判定);`null` 时用
  /// [defaultOpenAiCompatibleErrorStructure]。
  final ProviderErrorStructure? errorStructure;

  /// 单次 `doEmbed` 调用的 embedding 数量上限。
  ///
  /// 采用**字段默认值** `= 2048` 而非 raw TS 的 optional 字段 + getter
  /// `?? 2048` 兜底模式:Dart 的具名参数默认值已能表达"未传即 2048",这是
  /// 惯用法层面的等价改写,不是行为偏离。类型保持 `int?` 是为了保留
  /// "显式传 `null` 表达无覆盖"这条路径——模型 getter 侧仍有 `?? 2048`
  /// 兜底,与"未传参数用默认值"殊途同归。
  final int? maxEmbeddingsPerCall;

  /// 该模型是否可以并发处理多个 embedding 调用(raw 默认 `true`,此处
  /// 经字段默认值锚定,非空 `bool` 无需 getter 二次兜底)。
  final bool supportsParallelCalls;
}
