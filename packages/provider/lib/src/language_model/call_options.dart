import 'package:equatable/equatable.dart';

import '../shared/cancellation.dart';
import 'message.dart';
import 'reasoning.dart';
import 'response_format.dart';
import '../shared/shared.dart';
import 'tool.dart';

/// `copyWith` 的"未传参"哨兵:与 `null` 区分开。
///
/// 调用方不传某个可空参数时,值为 [_unset](保留旧值);
/// 显式传 `null` 时,表示把该字段清空为 `null`。
const Object _unset = Object();

/// 语言模型的一次调用参数(不可变值对象)。
///
/// 中间件 `transformParams` 会重建参数,故 [copyWith] 必须逐字段透传,
/// 绝不隐式丢字段。除 [cancellation](身份对象)外,均入值相等。
final class LanguageModelCallOptions with EquatableMixin {
  const LanguageModelCallOptions({
    required this.prompt,
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.topK,
    this.presencePenalty,
    this.frequencyPenalty,
    this.seed,
    this.stopSequences,
    this.responseFormat,
    this.tools,
    this.toolChoice,
    this.reasoning,
    this.includeRawChunks,
    this.cancellation,
    this.headers,
    this.providerOptions,
  });

  /// 有序的对话消息序列。
  final LanguageModelPrompt prompt;

  // 标准采样组(全部可空,缺省交由 provider 决定)。
  final int? maxOutputTokens;
  final double? temperature;
  final double? topP;
  final double? topK;
  final double? presencePenalty;
  final double? frequencyPenalty;
  final int? seed;
  final List<String>? stopSequences;

  /// 期望的响应格式(文本或 JSON)。
  final ResponseFormat? responseFormat;

  /// 本次调用可用的工具集合。
  final List<LanguageModelTool>? tools;

  /// 工具选择策略。
  final ToolChoice? toolChoice;

  /// 一等 reasoning 力度。
  final ReasoningEffort? reasoning;

  /// 是否在流中透传原始分块(`RawPart`)。
  final bool? includeRawChunks;

  /// 只读取消信号。身份对象,不入值相等。
  final CancellationSignal? cancellation;

  /// 覆盖/追加的请求头。
  final Headers? headers;

  /// provider 私有选项(外层键为 provider 名)。
  final ProviderOptions? providerOptions;

  /// 逐字段透传的拷贝。
  ///
  /// 未传的参数保留原值;显式传 `null` 可把对应可空字段清空。
  LanguageModelCallOptions copyWith({
    LanguageModelPrompt? prompt,
    Object? maxOutputTokens = _unset,
    Object? temperature = _unset,
    Object? topP = _unset,
    Object? topK = _unset,
    Object? presencePenalty = _unset,
    Object? frequencyPenalty = _unset,
    Object? seed = _unset,
    Object? stopSequences = _unset,
    Object? responseFormat = _unset,
    Object? tools = _unset,
    Object? toolChoice = _unset,
    Object? reasoning = _unset,
    Object? includeRawChunks = _unset,
    Object? cancellation = _unset,
    Object? headers = _unset,
    Object? providerOptions = _unset,
  }) {
    return LanguageModelCallOptions(
      prompt: prompt ?? this.prompt,
      maxOutputTokens: identical(maxOutputTokens, _unset)
          ? this.maxOutputTokens
          : maxOutputTokens as int?,
      temperature: identical(temperature, _unset)
          ? this.temperature
          : temperature as double?,
      topP: identical(topP, _unset) ? this.topP : topP as double?,
      topK: identical(topK, _unset) ? this.topK : topK as double?,
      presencePenalty: identical(presencePenalty, _unset)
          ? this.presencePenalty
          : presencePenalty as double?,
      frequencyPenalty: identical(frequencyPenalty, _unset)
          ? this.frequencyPenalty
          : frequencyPenalty as double?,
      seed: identical(seed, _unset) ? this.seed : seed as int?,
      stopSequences: identical(stopSequences, _unset)
          ? this.stopSequences
          : stopSequences as List<String>?,
      responseFormat: identical(responseFormat, _unset)
          ? this.responseFormat
          : responseFormat as ResponseFormat?,
      tools: identical(tools, _unset)
          ? this.tools
          : tools as List<LanguageModelTool>?,
      toolChoice: identical(toolChoice, _unset)
          ? this.toolChoice
          : toolChoice as ToolChoice?,
      reasoning: identical(reasoning, _unset)
          ? this.reasoning
          : reasoning as ReasoningEffort?,
      includeRawChunks: identical(includeRawChunks, _unset)
          ? this.includeRawChunks
          : includeRawChunks as bool?,
      cancellation: identical(cancellation, _unset)
          ? this.cancellation
          : cancellation as CancellationSignal?,
      headers: identical(headers, _unset) ? this.headers : headers as Headers?,
      providerOptions: identical(providerOptions, _unset)
          ? this.providerOptions
          : providerOptions as ProviderOptions?,
    );
  }

  /// 值相等仅按值字段;[cancellation] 是身份对象,故意排除在外。
  @override
  List<Object?> get props => <Object?>[
        prompt,
        maxOutputTokens,
        temperature,
        topP,
        topK,
        presencePenalty,
        frequencyPenalty,
        seed,
        stopSequences,
        responseFormat,
        tools,
        toolChoice,
        reasoning,
        includeRawChunks,
        headers,
        providerOptions,
      ];
}
