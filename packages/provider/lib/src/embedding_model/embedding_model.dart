import 'dart:async';

import 'package:equatable/equatable.dart';

import '../shared/cancellation.dart';
import '../shared/shared.dart';

/// embedding 模型规范版本。
const embeddingModelSpecVersion = 'v4';

/// 单条 embedding 向量:一组浮点数(词/文本的向量表示)。
///
/// 对齐 v7 `EmbeddingModelV4Embedding = Array<number>`。v4 契约已收窄到纯
/// 文本 embedding(接口注释原文 "specific to text embeddings"),故本契约
/// 无泛型,`values` 直接是 `List<String>`。
typedef Embedding = List<double>;

/// embedding 模型契约:单个动作 `doEmbed`。
///
/// 这是整个 embedding 增量的脊柱,与 [LanguageModel](见 `language_model.dart`)
/// 同构但独立——两者不共享父接口,对齐 v7 侧 `EmbeddingModelV4` 与
/// `LanguageModelV4` 是两个平行 spec 类型的事实。
abstract interface class EmbeddingModel {
  /// embedding 模型规范版本。
  String get specificationVersion;

  /// provider 名(如 `'openai.embedding'` 风格,与 [LanguageModel.provider]
  /// 的裸 provider 名区分,避免同一 provider 下语言模型与 embedding 模型
  /// 混淆日志来源)。
  String get provider;

  /// provider 侧模型 id(如 `'text-embedding-3-small'`)。
  String get modelId;

  /// 单次 `doEmbed` 调用最多可生成的 embedding 数量。
  ///
  /// `null` 表示无上限——对齐 v7
  /// `PromiseLike<number|undefined> | number | undefined`
  /// 的 `Infinity`/`undefined` 两种"无限"表达,在 Dart 侧合一为
  /// 单一的 `null`(没有 `Infinity` 语义,不需要区分)。可能需要异步计算
  /// (如首次调用时探测 provider 能力),故用 [FutureOr]。
  FutureOr<int?> get maxEmbeddingsPerCall;

  /// 该模型是否可以并发处理多个 embedding 调用。
  ///
  /// 供 `embedMany` 决定分批后是"组间并行"还是"组间串行"。
  FutureOr<bool> get supportsParallelCalls;

  /// 为给定输入文本生成一组 embedding。
  ///
  /// 命名沿用 `do` 前缀(对齐 v7 `doEmbed` 注释:防止用户误把这个底层方法
  /// 当作面向用户的入口直接调用——面向用户的入口是 `pigcode_ai` 的
  /// `embed`/`embedMany`)。
  Future<EmbeddingModelResult> doEmbed(EmbeddingModelCallOptions options);
}

/// [EmbeddingModel.doEmbed] 的调用参数(不可变值对象)。
///
/// 照 `LanguageModelCallOptions`(见 `call_options.dart`)模式:equatable 值类,
/// 除 [cancellation](身份对象)外全部字段入值相等。
final class EmbeddingModelCallOptions with EquatableMixin {
  const EmbeddingModelCallOptions({
    required this.values,
    this.headers,
    this.providerOptions,
    this.cancellation,
  });

  /// 待生成 embedding 的文本值列表。
  final List<String> values;

  /// 覆盖/追加的请求头。
  final Map<String, String>? headers;

  /// provider 私有选项(外层键为 provider 名)。
  final ProviderOptions? providerOptions;

  /// 只读取消信号。身份对象,不入值相等(对齐 v7 `abortSignal`)。
  final CancellationSignal? cancellation;

  /// 值相等仅按值字段;[cancellation] 是身份对象,故意排除在外
  /// (与 `LanguageModelCallOptions.props` 同一先例)。
  @override
  List<Object?> get props => <Object?>[values, headers, providerOptions];
}

/// embedding 调用的 token 用量。
///
/// v7 侧为 `usage?: { tokens: number }`(整体可选)。Dart 侧合一为容器非空、
/// 字段可空的风格(`EmbeddingUsage { int? tokens }`),与
/// `LanguageModelUsage` 的"容器非空、字段可空"风格一致,便于
/// [EmbeddingModelResult.usage] 提供非空默认值。
final class EmbeddingUsage with EquatableMixin {
  const EmbeddingUsage({this.tokens});

  /// 输入 token 数。embedding 只有输入侧 token,无输出侧。
  final int? tokens;

  @override
  List<Object?> get props => <Object?>[tokens];
}

/// embedding 调用的响应侧轻量元数据,仅供调试。
///
/// 刻意不复用 `results.dart` 里 `LanguageModel` 的 `ResponseInfo`
/// (id/timestamp/modelId/headers/body 五字段):v7 embedding 侧的 response
/// 只有 `headers`/`body` 两个字段,复用会引入 embedding wire 里根本不存在
/// 的字段,误导实现者去填充它们。
final class EmbeddingResponseInfo with EquatableMixin {
  const EmbeddingResponseInfo({this.headers, this.body});

  /// 响应头(如可得)。
  final Map<String, String>? headers;

  /// 原始响应体(类型不透明,诊断用)。
  final Object? body;

  @override
  List<Object?> get props => <Object?>[headers, body];
}

/// [EmbeddingModel.doEmbed] 的结果。
final class EmbeddingModelResult with EquatableMixin {
  const EmbeddingModelResult({
    required this.embeddings,
    this.usage = const EmbeddingUsage(),
    required this.warnings,
    this.providerMetadata,
    this.response,
  });

  /// 生成的 embedding 列表,与输入 `values` 保序对应。
  final List<Embedding> embeddings;

  /// 本次调用的 token 用量;默认空用量(`tokens: null`)。
  final EmbeddingUsage usage;

  /// 调用告警(如降级/不支持的 provider 选项)。
  final List<Warning> warnings;

  /// provider 私有元数据。
  final ProviderMetadata? providerMetadata;

  /// 响应侧元数据。
  final EmbeddingResponseInfo? response;

  @override
  List<Object?> get props => <Object?>[
        embeddings,
        usage,
        warnings,
        providerMetadata,
        response,
      ];
}
