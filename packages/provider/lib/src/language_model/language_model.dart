import 'dart:async';

import 'call_options.dart';
import 'results.dart';

/// 语言模型规范版本(去后缀后落到包级内部常量,供 wire/调试;不进类型名)。
const languageModelSpecVersion = 'v4';

/// 语言模型契约:单次生成 / 流式生成两个动作。
///
/// 这是整个契约层的脊柱。核心与各 provider 包都面向该接口编程:provider
/// 实现协议/传输适配,核心实现工具循环与中间件。契约层只定型,不承载任何
/// HTTP / SSE / JSON 传输实现。
abstract interface class LanguageModel {
  /// 语言模型规范版本。
  String get specificationVersion;

  /// provider 名(如 'openai')。
  String get provider;

  /// 模型 id(如 'gpt-4o')。
  String get modelId;

  /// 键为媒体类型模式(如 'image/*'),值为匹配 URL 的正则列表;命中的 URL
  /// 由 provider 原生透传、不下载。可能需要异步计算,故返回 [FutureOr]。
  FutureOr<Map<String, List<RegExp>>> get supportedUrls;

  /// 单次(非流式)生成。返回有序内容项 + 终止原因 + 用量 + 告警。
  Future<LanguageModelGenerateResult> doGenerate(
      LanguageModelCallOptions options);

  /// 流式生成。返回一条 [LanguageModelStreamPart] 事件流(error-as-event)。
  Future<LanguageModelStreamResult> doStream(LanguageModelCallOptions options);
}
