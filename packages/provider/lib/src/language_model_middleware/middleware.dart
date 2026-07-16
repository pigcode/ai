import 'dart:async';

import '../language_model/call_options.dart';
import '../language_model/language_model.dart';
import '../language_model/results.dart';

/// `wrapGenerate` 内部委托的非流式生成闭包：执行被包裹模型的 `doGenerate`。
typedef LanguageModelDoGenerate = Future<LanguageModelGenerateResult>
    Function();

/// `wrapStream` 内部委托的流式生成闭包：执行被包裹模型的 `doStream`。
typedef LanguageModelDoStream = Future<LanguageModelStreamResult> Function();

/// 语言模型中间件：一组可空的钩子函数字段。
///
/// 每个字段都是可选的；未设置的钩子为 `null`，由核心侧（`wrapLanguageModel`）
/// 按需调用。本类型持有函数，因此不参与值相等（不 `with EquatableMixin`）。
final class LanguageModelMiddleware {
  /// 构造中间件。所有钩子均为命名可选参数，缺省即 `null`（不改写对应行为）。
  const LanguageModelMiddleware({
    this.overrideProvider,
    this.overrideModelId,
    this.overrideSupportedUrls,
    this.transformParams,
    this.wrapGenerate,
    this.wrapStream,
  });

  /// 改写被包裹模型对外暴露的 provider 名；返回 `null` 表示不改写。
  final String? Function(LanguageModel model)? overrideProvider;

  /// 改写被包裹模型对外暴露的 modelId；返回 `null` 表示不改写。
  final String? Function(LanguageModel model)? overrideModelId;

  /// 改写被包裹模型的 `supportedUrls`（键为媒体类型模式，值为匹配正则）。
  final FutureOr<Map<String, List<RegExp>>> Function(LanguageModel model)?
      overrideSupportedUrls;

  /// 在调用底层模型前重建调用参数；`stream` 标记本次是否为流式调用。
  final Future<LanguageModelCallOptions> Function({
    required bool stream,
    required LanguageModelCallOptions params,
    required LanguageModel model,
  })? transformParams;

  /// 包裹非流式生成：可在调用 `doGenerate`（或 `doStream`）前后插入逻辑。
  final Future<LanguageModelGenerateResult> Function({
    required LanguageModelDoGenerate doGenerate,
    required LanguageModelDoStream doStream,
    required LanguageModelCallOptions params,
    required LanguageModel model,
  })? wrapGenerate;

  /// 包裹流式生成：可在调用 `doStream`（或 `doGenerate`）前后插入逻辑。
  final Future<LanguageModelStreamResult> Function({
    required LanguageModelDoGenerate doGenerate,
    required LanguageModelDoStream doStream,
    required LanguageModelCallOptions params,
    required LanguageModel model,
  })? wrapStream;
}
