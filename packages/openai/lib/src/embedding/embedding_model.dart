import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import '../internal/config.dart';
import '../internal/error.dart';
import '../internal/provider_options.dart';
import 'embedding_options.dart';

/// OpenAI Embeddings(`/embeddings`)的 [EmbeddingModel] 实现。
///
/// wire 语义逐字对照 v7 `OpenAIEmbeddingModel`(raw
/// `openai_emb__openai-embedding-model.ts`)。
final class OpenAiEmbeddingModel implements EmbeddingModel {
  /// 用给定的 [modelId] 与 [config] 构造一个 embedding 模型实例。
  OpenAiEmbeddingModel(this.modelId, {required this.config});

  /// 单次调用上限,上游硬编码(raw L25 `maxEmbeddingsPerCall = 2048`)。
  static const int _maxEmbeddingsPerCall = 2048;

  @override
  final String modelId;

  /// 共享的 provider 配置(baseUrl/headers/client)。
  final OpenAiConfig config;

  @override
  String get specificationVersion => embeddingModelSpecVersion;

  @override
  String get provider => '${config.providerName}.embedding';

  /// 契约要求 `FutureOr`,直接返回字面量即满足(调用方 `await` 后拿到
  /// 同步值)。
  @override
  FutureOr<int?> get maxEmbeddingsPerCall => _maxEmbeddingsPerCall;

  /// 上游硬编码(raw L26 `supportsParallelCalls = true`)。
  @override
  FutureOr<bool> get supportsParallelCalls => true;

  Uri get _requestUrl => Uri.parse('${config.baseUrl}/embeddings');

  @override
  Future<EmbeddingModelResult> doEmbed(
    EmbeddingModelCallOptions options,
  ) async {
    // 超量守卫在最前,早于 options 解析与请求发送(对照 raw L61-68
    // 先于 L70-76)。
    if (options.values.length > _maxEmbeddingsPerCall) {
      throw TooManyEmbeddingValuesForCallError(
        provider: provider,
        modelId: modelId,
        maxEmbeddingsPerCall: _maxEmbeddingsPerCall,
        valuesCount: options.values.length,
      );
    }

    // provider options 键按 provider 名派生(azure fallback),与 chat/
    // responses 两套 wire 对称——否则同一个 `createOpenAi(name: 'azure-x')`
    // 实例下会静默丢弃 `{'azure': {...}}` 键下的选项(见
    // `provider_options.dart` 文档)。
    final embeddingOptions = OpenAiEmbeddingProviderOptions.fromProviderOptions(
      resolveOpenAiProviderOptions(
        config.providerName,
        options.providerOptions,
      ),
    );

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
      url: _requestUrl,
      headers: combineHeaders([config.headers(), options.headers]),
      body: body,
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return jsonResponseHandler<JsonObject>(
          decode: (json) => json! as JsonObject,
        )(ctx);
      },
      failureHandler: openAiFailedResponseHandler(),
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

    return EmbeddingModelResult(
      embeddings: embeddings,
      usage: usage == null
          ? const EmbeddingUsage()
          : EmbeddingUsage(tokens: (usage['prompt_tokens'] as num?)?.toInt()),
      // 对照 raw L104:warnings 恒空数组。
      warnings: const <Warning>[],
      // body 为完整解码 JSON 对象(本响应体解码不做结构收窄,解码值即
      // 上游的 rawValue,与 chat wire 的 `body: response` 用法一致)。
      response: EmbeddingResponseInfo(
        headers: responseHeaders,
        body: response,
      ),
    );
  }
}
