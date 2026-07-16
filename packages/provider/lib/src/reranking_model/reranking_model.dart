import 'package:equatable/equatable.dart';

import '../json_value/json.dart';
import '../language_model/results.dart';
import '../shared/cancellation.dart';
import '../shared/shared.dart';

/// reranking 模型规范版本。
const rerankingModelSpecVersion = 'v4';

/// reranking 模型契约:单个动作 `doRerank`。
abstract interface class RerankingModel {
  /// reranking 模型规范版本。
  String get specificationVersion;

  /// provider 名,如 `'cohere.rerank'`。
  String get provider;

  /// provider 侧模型 id。
  String get modelId;

  /// 对给定 [RerankingModelCallOptions.query] 和 documents 计算相关性排名。
  Future<RerankingModelResult> doRerank(RerankingModelCallOptions options);
}

/// reranking 文档集合。
sealed class RerankingDocuments with EquatableMixin {
  const RerankingDocuments();
}

/// 纯文本 reranking 文档。
final class RerankingDocumentsText extends RerankingDocuments {
  const RerankingDocumentsText(this.values);

  /// 待排序的文本列表。
  final List<String> values;

  @override
  List<Object?> get props => <Object?>[values];
}

/// JSON 对象 reranking 文档。
final class RerankingDocumentsObject extends RerankingDocuments {
  const RerankingDocumentsObject(this.values);

  /// 待排序的 JSON 对象列表。
  final List<JsonObject> values;

  @override
  List<Object?> get props => <Object?>[values];
}

/// [RerankingModel.doRerank] 的调用参数。
final class RerankingModelCallOptions with EquatableMixin {
  const RerankingModelCallOptions({
    required this.documents,
    required this.query,
    this.topN,
    this.headers,
    this.providerOptions,
    this.cancellation,
  });

  /// 待排序文档。
  final RerankingDocuments documents;

  /// 查询文本。
  final String query;

  /// 最多返回的排名条数。为 `null` 时由 provider 默认行为决定。
  final int? topN;

  /// 覆盖/追加的请求头。
  final Headers? headers;

  /// provider 私有选项(外层键为 provider 名)。
  final ProviderOptions? providerOptions;

  /// 只读取消信号。身份对象,不入值相等。
  final CancellationSignal? cancellation;

  @override
  List<Object?> get props => <Object?>[
        documents,
        query,
        topN,
        headers,
        providerOptions,
      ];
}

/// 单条 reranking 排名。
final class RerankingModelRanking with EquatableMixin {
  const RerankingModelRanking({
    required this.index,
    required this.relevanceScore,
  });

  /// 原始 documents 列表中的下标。
  final int index;

  /// provider 返回的相关性分数。
  final double relevanceScore;

  @override
  List<Object?> get props => <Object?>[index, relevanceScore];
}

/// [RerankingModel.doRerank] 的结果。
final class RerankingModelResult with EquatableMixin {
  const RerankingModelResult({
    required this.ranking,
    required this.warnings,
    this.providerMetadata,
    this.response,
  });

  /// 排名结果。
  final List<RerankingModelRanking> ranking;

  /// 调用告警。
  final List<Warning> warnings;

  /// provider 私有元数据。
  final ProviderMetadata? providerMetadata;

  /// 响应侧元数据。
  final ResponseInfo? response;

  @override
  List<Object?> get props => <Object?>[
        ranking,
        warnings,
        providerMetadata,
        response,
      ];
}
