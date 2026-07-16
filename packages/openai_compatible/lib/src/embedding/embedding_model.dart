import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import '../internal/error_structure.dart';
import 'embedding_config.dart';
import 'embedding_options.dart';

/// OpenAI 兼容 Embeddings(`/embeddings`)的 [EmbeddingModel] 实现。
///
/// wire 语义逐字对照 v7 `OpenAICompatibleEmbeddingModel`(raw
/// `compatible_emb__openai-compatible-embedding-model.ts`);行为围绕
/// [OpenAiCompatibleEmbeddingConfig] 的可插拔扩展点(错误体结构、能力
/// 上限)展开。
final class OpenAiCompatibleEmbeddingModel implements EmbeddingModel {
  /// 用给定的 [modelId] 与 [config] 构造一个 embedding 模型实例。
  OpenAiCompatibleEmbeddingModel(this.modelId, {required this.config});

  @override
  final String modelId;

  /// 本模型实例的运行时配置。
  final OpenAiCompatibleEmbeddingConfig config;

  @override
  String get specificationVersion => embeddingModelSpecVersion;

  @override
  String get provider => '${config.providerName}.embedding';

  /// 单次调用上限的同步解析值:`config.maxEmbeddingsPerCall ?? 2048`。
  ///
  /// 即便 config 字段默认值已是 2048,仍保留 `??` 兜底以覆盖调用方显式传
  /// `null` 的路径(对齐 raw getter `this.config.maxEmbeddingsPerCall ??
  /// 2048`——"未传参数用具名默认值"与"显式传 null 退回默认"是同一结果、
  /// 不同触发路径,两条都要覆盖)。
  int get _resolvedMaxEmbeddingsPerCall => config.maxEmbeddingsPerCall ?? 2048;

  @override
  FutureOr<int?> get maxEmbeddingsPerCall => _resolvedMaxEmbeddingsPerCall;

  /// 直接返回 config 字段:非空 `bool`,默认值 `true` 已在 config 构造时
  /// 锚定,无需二次 `??`(raw `this.config.supportsParallelCalls ?? true`
  /// 的兜底在 Dart 侧由字段默认值承担)。
  @override
  FutureOr<bool> get supportsParallelCalls => config.supportsParallelCalls;

  /// [OpenAiCompatibleEmbeddingConfig.errorStructure] 缺省时的错误体结构;
  /// 按需求值(照 `chat_language_model.dart` 同名 getter 模式)。
  ProviderErrorStructure get _errorStructure =>
      config.errorStructure ?? defaultOpenAiCompatibleErrorStructure;

  @override
  Future<EmbeddingModelResult> doEmbed(
    EmbeddingModelCallOptions options,
  ) async {
    // 先解析 providerOptions,**再**做超量守卫(对照 raw L100-134 解析在
    // 前、L136-143 守卫在后——与 pigcode_ai_openai 包"守卫在最前"的顺序
    // 相反)。边角行为差异:providerOptions 非法且同时超量时,本包先抛
    // TypeValidationError 而非 TooManyEmbeddingValuesForCallError。
    final embeddingOptions =
        OpenAiCompatibleEmbeddingProviderOptions.fromProviderOptions(
      options.providerOptions,
      providerOptionsName: config.providerName,
    );

    // 局部变量取同步解析值(已过 ?? 2048 兜底,恒非 null),守卫与错误
    // 报告共用同一份值。
    final maxEmbeddingsPerCall = _resolvedMaxEmbeddingsPerCall;
    if (options.values.length > maxEmbeddingsPerCall) {
      throw TooManyEmbeddingValuesForCallError(
        provider: provider,
        modelId: modelId,
        maxEmbeddingsPerCall: maxEmbeddingsPerCall,
        valuesCount: options.values.length,
      );
    }

    // `removeWhere` 剔除 null 键(与 chat wire 同款):dimensions/user
    // 缺省时对应键完全不出现在请求体里,而非发送 null 值。
    final body = <String, Object?>{
      'model': modelId,
      'input': options.values,
      'encoding_format': 'float',
      'dimensions': embeddingOptions.dimensions,
      'user': embeddingOptions.user,
    }..removeWhere((_, value) => value == null);

    // `jsonResponseHandler` 只产出解码后的业务值,响应头需要在 `decode`
    // 之外单独从 `ResponseContext` 捕获——用局部可变变量在
    // `successHandler` 闭包内旁路写入(与 `chat_language_model.dart`
    // doGenerate 同款模式),`postJsonToApi` 保证 `successHandler` 在
    // 返回前已完整执行完毕,不存在竞态。
    Map<String, String>? responseHeaders;
    final response = await postJsonToApi<JsonObject>(
      url: config.url('/embeddings'),
      headers: combineHeaders([config.headers(), options.headers]),
      body: body,
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return jsonResponseHandler<JsonObject>(
          decode: (json) => json! as JsonObject,
        )(ctx);
      },
      failureHandler: openAiCompatibleFailedResponseHandler(_errorStructure),
      client: config.client,
      cancellation: options.cancellation,
    );

    // 响应体宽松解码(契约层无 zod 等价物,手动解码 + 显式空校验):
    // 逐项取 `embedding` 数组转 `List<double>`,不读取/不校验 `index`
    // 字段(上游 schema 亦不含 index,响应顺序即输入顺序)。
    final data = response['data']! as List<Object?>;
    final embeddings = data
        .map(
          (item) => ((item! as JsonObject)['embedding']! as List<Object?>)
              .map((component) => (component! as num).toDouble())
              .toList(),
        )
        .toList();

    // usage 缺席时 tokens 为 null(v7 `undefined` → Dart 侧空用量对象)。
    final usage = response['usage'] as JsonObject?;

    // providerMetadata:响应体顶层同名字段**整体透传**(对照 raw L178
    // `providerMetadata: response.providerMetadata`)——不嵌套包一层
    // provider 名、不与 providerOptions 交叉;逐项收窄为
    // `Map<String, JsonObject>`(对齐上游 schema
    // `record(string, record(string, any))` 的两层结构约束)。
    final rawProviderMetadata = response['providerMetadata'] as JsonObject?;
    final providerMetadata = rawProviderMetadata == null
        ? null
        : <String, JsonObject>{
            for (final entry in rawProviderMetadata.entries)
              entry.key: entry.value! as JsonObject,
          };

    return EmbeddingModelResult(
      embeddings: embeddings,
      usage: usage == null
          ? const EmbeddingUsage()
          : EmbeddingUsage(tokens: (usage['prompt_tokens'] as num?)?.toInt()),
      // 对照 raw:pigcode 单 key 裁决下无 deprecated-key warning 可产生
      // (raw 的 warnings 只来自 deprecated key 检测),恒空数组。
      warnings: const <Warning>[],
      providerMetadata: providerMetadata,
      // body 为完整解码 JSON 对象(本响应体解码不做结构收窄,解码值即
      // 上游的 rawValue,与 chat wire 的 `body: response` 用法一致)。
      response: EmbeddingResponseInfo(
        headers: responseHeaders,
        body: response,
      ),
    );
  }
}
