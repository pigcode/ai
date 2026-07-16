import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:equatable/equatable.dart';

import '../logger/log_warnings.dart';

/// `rerank` 的单条排名结果:包含原始下标、相关性分数和原始文档。
final class RerankRanking<T extends Object> with EquatableMixin {
  const RerankRanking({
    required this.originalIndex,
    required this.score,
    required this.document,
  });

  /// 原始 documents 列表中的下标。
  final int originalIndex;

  /// provider 返回的相关性分数。
  final double score;

  /// 原始文档值。
  final T document;

  @override
  List<Object?> get props => <Object?>[originalIndex, score, document];
}

/// `rerank` 的结果:原始文档、排序项、告警、provider 元数据与响应信息。
final class RerankResult<T extends Object> {
  const RerankResult({
    required this.originalDocuments,
    required this.ranking,
    required this.warnings,
    this.providerMetadata,
    required this.response,
  });

  /// 调用方传入的原始文档。
  final List<T> originalDocuments;

  /// 排名结果。
  final List<RerankRanking<T>> ranking;

  /// provider 侧告警。
  final List<provider.Warning> warnings;

  /// provider 私有元数据。
  final provider.ProviderMetadata? providerMetadata;

  /// 响应侧元数据。
  final provider.ResponseInfo response;

  /// 按 ranking 顺序排列后的文档列表。
  List<T> get rerankedDocuments =>
      ranking.map((item) => item.document).toList(growable: false);
}

/// 用给定 [model] 对 [documents] 按 [query] 计算相关性排名。
Future<RerankResult<T>> rerank<T extends Object>({
  required provider.RerankingModel model,
  required List<T> documents,
  required String query,
  int? topN,
  provider.ProviderOptions? providerOptions,
  Map<String, String>? headers,
  provider.CancellationSignal? cancellation,
}) async {
  if (documents.isEmpty) {
    return RerankResult<T>(
      originalDocuments: documents,
      ranking: const [],
      warnings: const [],
      response: provider.ResponseInfo(
        timestamp: DateTime.now(),
        modelId: model.modelId,
      ),
    );
  }

  final providerDocuments = _toProviderDocuments(documents);
  final modelResponse = await model.doRerank(
    provider.RerankingModelCallOptions(
      documents: providerDocuments,
      query: query,
      topN: topN,
      headers: headers,
      providerOptions: providerOptions,
      cancellation: cancellation,
    ),
  );
  logWarnings(
    warnings: modelResponse.warnings,
    provider: model.provider,
    model: model.modelId,
  );

  final ranking = modelResponse.ranking.map((item) {
    final index = item.index;
    if (index < 0 || index >= documents.length) {
      throw StateError(
        'Reranking model "${model.modelId}" (provider "${model.provider}") '
        'returned ranking index $index for ${documents.length} documents.',
      );
    }
    return RerankRanking<T>(
      originalIndex: index,
      score: item.relevanceScore,
      document: documents[index],
    );
  }).toList(growable: false);

  return RerankResult<T>(
    originalDocuments: documents,
    ranking: ranking,
    warnings: modelResponse.warnings,
    providerMetadata: modelResponse.providerMetadata,
    response: _responseWithDefaults(modelResponse.response, model.modelId),
  );
}

provider.RerankingDocuments _toProviderDocuments<T extends Object>(
  List<T> documents,
) {
  if (documents.every((document) => document is String)) {
    return provider.RerankingDocumentsText(
      documents.cast<String>(),
    );
  }
  if (documents.every((document) => document is provider.JsonObject)) {
    return provider.RerankingDocumentsObject(
      documents.cast<provider.JsonObject>(),
    );
  }
  throw const provider.InvalidArgumentError(
    argument: 'documents',
    message: 'documents must be all strings or all JSON objects.',
  );
}

provider.ResponseInfo _responseWithDefaults(
  provider.ResponseInfo? response,
  String modelId,
) {
  return provider.ResponseInfo(
    id: response?.id,
    timestamp: response?.timestamp ?? DateTime.now(),
    modelId: response?.modelId ?? modelId,
    headers: response?.headers,
    body: response?.body,
  );
}
