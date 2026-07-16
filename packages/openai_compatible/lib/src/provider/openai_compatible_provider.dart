import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;

import '../chat/chat_language_model.dart';
import '../embedding/embedding_config.dart';
import '../embedding/embedding_model.dart';
import '../internal/error_structure.dart';
import '../utils/metadata_extractor.dart';

/// 本包版本号,固定拼接进 User-Agent 后缀。
///
/// 纯 Dart 没有读取自身 `pubspec.yaml` 的轻量手段(无 `dart:mirrors`/
/// `package_info` 等价物),故硬编码;需与
/// `packages/openai_compatible/pubspec.yaml` 的 `version` 字段保持一致
/// (`pigcode_ai_openai` 等姊妹包亦是同样的手写 `0.0.1` 约定)。
const _packageVersion = '0.0.1';

/// 创建一个 OpenAI 兼容 provider 实例。
///
/// [name] 是 provider 标识(如 `'mycustom'`),同时用作 providerOptions 的
/// 解析 key 与 `provider` 字符串(`'<name>.chat'`)的前缀。[baseUrl] 必填,
/// 经 [withoutTrailingSlash] 去除唯一一个尾部斜杠;无环境变量回退。
/// [apiKey] **可选**——与 `pigcode_ai_openai` 的 `loadApiKey` 强制校验不同,
/// 本包面向任意第三方兼容服务(可能免鉴权),`null` 时不加 `Authorization`
/// 头。[headers] 为调用方自定义头,合并顺序上覆盖前面的 apiKey 头(经
/// `combineHeaders` 语义,对齐 raw ~146-149 的展开顺序);其中
/// `User-Agent` 例外——固定后缀恒**追加**在调用方提供值之后而非覆盖
/// (见 [_withUserAgentSuffix])。[queryParams] 非空时整体替换请求 URL 的
/// query 部分(逐字对齐 raw ~154-165,见 url 闭包内注释)。其余具名参数
/// 均为 [OpenAiCompatibleChatConfig] 的同名扩展点,原样透传、不做二次
/// 处理(默认值语义由 config/模型层唯一定义,工厂不重复声明以免两处
/// 不一致)。
///
/// 【主动偏离 raw】embedding 三项的工厂接线:上游 `createOpenAICompatible`
/// (raw `compatible__openai-compatible-provider.ts` L187-190)构造
/// embedding 模型时只展开公共 config,**不透传** `errorStructure`/
/// `maxEmbeddingsPerCall`/`supportsParallelCalls` 三项——即便
/// `OpenAICompatibleEmbeddingConfig` 类型本身声明了这三个可选字段,官方
/// 工厂就是不接线它们,只有绕过工厂直接 new 模型类才能用上。pigcode 工厂
/// 主动透传全部三项,理由:
/// 1. `errorStructure` 是本包存在的核心理由(第三方错误体形状不一致),
///    chat wire 的工厂早已透传同名参数;embedding 若不透传,用户必须绕过
///    工厂直接 new 模型类才能自定义错误解析,与"本包为可插拔而生"的
///    定位矛盾。工厂不新增第二个形参,[errorStructure] 同一个入参值同时
///    透传进 chat 与 embedding 两份 config(两模态共用同一错误结构,
///    v7 两 config 的同名字段本就同源)。
/// 2. [embeddingMaxEmbeddingsPerCall]/[embeddingSupportsParallelCalls] 是
///    真实需求:第三方兼容端点的批量 embedding 上限并非普遍是 2048(常见
///    16/32/64),不可配置会导致 `embedMany` 分片在这些端点上产生本可
///    避免的 `TooManyEmbeddingValuesForCallError`。
///
/// 两个新参数的默认值处理刻意不对称:[embeddingMaxEmbeddingsPerCall] 用
/// `int?` 不设默认值,`null` 时由模型 getter 的 `?? 2048` 兜底回落默认
/// (工厂层不重复声明默认值,避免与 config/模型层的 2048 不同步);
/// [embeddingSupportsParallelCalls] 是非 nullable `bool`,没有"未设置"的
/// 第三态可透传,工厂必须给出一个具体默认值传给 config 构造器,故在此
/// 重复声明 `= true`(与 config 字段默认值保持一致)。
OpenAiCompatibleProvider createOpenAiCompatible({
  required String name,
  required String baseUrl,
  String? apiKey,
  Map<String, String>? headers,
  Map<String, String>? queryParams,
  http.Client? client,
  bool includeUsage = false,
  bool supportsStructuredOutputs = false,
  ProviderErrorStructure? errorStructure,
  MetadataExtractor? metadataExtractor,
  Map<String, List<RegExp>> Function()? supportedUrls,
  JsonObject Function(JsonObject args)? transformRequestBody,
  LanguageModelUsage Function(JsonObject usage)? convertUsage,
  int? embeddingMaxEmbeddingsPerCall,
  bool embeddingSupportsParallelCalls = true,
}) {
  // `baseUrl` 是必填非空 String,`withoutTrailingSlash` 对非 null 输入
  // 保证返回非 null,故 `!` 永不触发。
  final resolvedBaseUrl = withoutTrailingSlash(baseUrl)!;

  // apiKey 头先放入,用户 headers 后合并覆盖(用户可覆盖 Authorization),
  // 对齐 raw ~146-149 与 pigcode_ai_openai `createOpenAi` 的既定顺序。
  final baseHeaders = combineHeaders([
    {if (apiKey != null) 'Authorization': 'Bearer $apiKey'},
    headers,
  ]);

  Map<String, String> getHeaders() => _withUserAgentSuffix(
        baseHeaders,
        'pigcode_ai_openai_compatible/$_packageVersion',
      );

  Uri url(String path) {
    final parsed = Uri.parse('$resolvedBaseUrl$path');
    if (queryParams == null || queryParams.isEmpty) {
      return parsed;
    }
    // 逐字对齐 raw `url.search = new URLSearchParams(...).toString()`:
    // 整体替换 query,而非与 baseUrl 自带的 query 合并——若 baseUrl 带
    // 查询串且 queryParams 非空,原查询串会被完全覆盖丢失(v7 原生行为,
    // 非本实现引入的偏差,此处不做"合并"这种看似更友好但偏离上游的改动)。
    // 空 map 走上方早退分支:JS 侧空对象是 truthy 但 v7 调用方约定不传空
    // 对象,Dart 侧显式判空以避免 `Uri.replace(queryParameters: {})` 把
    // baseUrl 自带 query 清空这一多余副作用。
    return parsed.replace(queryParameters: queryParams);
  }

  final config = OpenAiCompatibleChatConfig(
    providerName: name,
    url: url,
    headers: getHeaders,
    client: client,
    includeUsage: includeUsage,
    supportsStructuredOutputs: supportsStructuredOutputs,
    errorStructure: errorStructure,
    metadataExtractor: metadataExtractor,
    supportedUrls: supportedUrls,
    transformRequestBody: transformRequestBody,
    convertUsage: convertUsage,
  );

  // 与 chat config 共用同一套 url/getHeaders/client/errorStructure 值,
  // 仅字段集不同(embedding 专属的能力两项见工厂文档注释的偏离声明)。
  final embeddingConfig = OpenAiCompatibleEmbeddingConfig(
    providerName: name,
    url: url,
    headers: getHeaders,
    client: client,
    errorStructure: errorStructure,
    maxEmbeddingsPerCall: embeddingMaxEmbeddingsPerCall,
    supportsParallelCalls: embeddingSupportsParallelCalls,
  );

  return OpenAiCompatibleProvider._(
    config: config,
    embeddingConfig: embeddingConfig,
  );
}

/// OpenAI 兼容 provider:语言模型唯一的 wire 是 Chat Completions,另有
/// Embeddings(`/embeddings`)一套 embedding wire。
///
/// 对照 `pigcode_ai_openai` `OpenAiProvider` 的私有构造 + 内部持有配置模式;
/// 语言模型只有一种 wire,[languageModel] 直接委托 [chatModel],无需按
/// wire `switch` 分派。
final class OpenAiCompatibleProvider implements Provider {
  OpenAiCompatibleProvider._({
    required OpenAiCompatibleChatConfig config,
    required OpenAiCompatibleEmbeddingConfig embeddingConfig,
  })  : _config = config,
        _embeddingConfig = embeddingConfig;

  final OpenAiCompatibleChatConfig _config;
  final OpenAiCompatibleEmbeddingConfig _embeddingConfig;

  @override
  String get specificationVersion => providerSpecVersion;

  @override
  LanguageModel languageModel(String modelId) => chatModel(modelId);

  /// 创建一个 Chat Completions(`/chat/completions`)语言模型。
  ///
  /// 本包无 responses 概念,[languageModel]/[chatModel] 行为等价
  /// (spec §1/§4)。
  LanguageModel chatModel(String modelId) =>
      OpenAiCompatibleChatLanguageModel(modelId, config: _config);

  /// 创建一个 Embeddings(`/embeddings`)embedding 模型。
  @override
  EmbeddingModel embeddingModel(String modelId) =>
      OpenAiCompatibleEmbeddingModel(modelId, config: _embeddingConfig);

  @override
  ImageModel imageModel(String modelId) {
    throw NoSuchModelError(
      modelId: modelId,
      modelType: ModelType.imageModel,
    );
  }

  @override
  TranscriptionModel transcriptionModel(String modelId) {
    throw NoSuchModelError(
      modelId: modelId,
      modelType: ModelType.transcriptionModel,
    );
  }

  @override
  SpeechModel speechModel(String modelId) {
    throw NoSuchModelError(
      modelId: modelId,
      modelType: ModelType.speechModel,
    );
  }

  @override
  VideoModel videoModel(String modelId) {
    throw NoSuchModelError(
      modelId: modelId,
      modelType: ModelType.videoModel,
    );
  }

  @override
  RerankingModel rerankingModel(String modelId) {
    throw NoSuchModelError(
      modelId: modelId,
      modelType: ModelType.rerankingModel,
    );
  }

  @override
  Files files() {
    throw const UnsupportedFunctionalityError(functionality: 'files');
  }

  @override
  Skills skills() {
    throw const UnsupportedFunctionalityError(functionality: 'skills');
  }
}

/// 把 [suffix] 追加到 [headers] 的 `User-Agent` 值末尾(空格分隔);若
/// 尚无 `User-Agent`,则新建一个只含 [suffix] 的值。
///
/// 照抄 `packages/openai/lib/src/openai_provider.dart` 的同名私有实现
/// ——`pigcode_ai_provider_utils` 未提供"追加而非覆盖"语义的 UA 工具,
/// 两个 provider 包各自维护一份是既定模式(非重复劳动,是刻意保持
/// provider 包彼此独立,不产生跨包私有依赖)。
Map<String, String> _withUserAgentSuffix(
  Map<String, String> headers,
  String suffix,
) {
  final result = Map<String, String>.of(headers);
  String? current;
  for (final name in result.keys.toList()) {
    if (name.toLowerCase() == 'user-agent') {
      current = result.remove(name);
    }
  }
  result['User-Agent'] =
      (current == null || current.isEmpty) ? suffix : '$current $suffix';
  return result;
}
