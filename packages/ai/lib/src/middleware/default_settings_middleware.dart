import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import 'default_settings_merge.dart';

/// 为语言模型调用参数补默认值的中间件。
///
/// 对齐上游当前 `defaultSettingsMiddleware`:调用参数优先于 [settings],
/// headers 与 providerOptions 会合并，providerOptions 内的嵌套 JSON object
/// 递归合并，数组直接由调用参数替换。
provider.LanguageModelMiddleware defaultSettingsMiddleware({
  required DefaultLanguageModelSettings settings,
}) {
  return provider.LanguageModelMiddleware(
    transformParams: ({
      required bool stream,
      required provider.LanguageModelCallOptions params,
      required provider.LanguageModel model,
    }) async {
      return provider.LanguageModelCallOptions(
        prompt: params.prompt,
        maxOutputTokens: params.maxOutputTokens ?? settings.maxOutputTokens,
        temperature: params.temperature ?? settings.temperature,
        topP: params.topP ?? settings.topP,
        topK: params.topK ?? settings.topK,
        presencePenalty: params.presencePenalty ?? settings.presencePenalty,
        frequencyPenalty: params.frequencyPenalty ?? settings.frequencyPenalty,
        seed: params.seed ?? settings.seed,
        stopSequences: params.stopSequences ?? settings.stopSequences,
        responseFormat: params.responseFormat ?? settings.responseFormat,
        tools: params.tools ?? settings.tools,
        toolChoice: params.toolChoice ?? settings.toolChoice,
        reasoning: params.reasoning ?? settings.reasoning,
        includeRawChunks: params.includeRawChunks ?? settings.includeRawChunks,
        cancellation: params.cancellation,
        headers: mergeHeaders(settings.headers, params.headers),
        providerOptions: mergeProviderOptionsDeep(
          settings.providerOptions,
          params.providerOptions,
        ),
      );
    },
  );
}

/// [defaultSettingsMiddleware] 可补入的语言模型默认设置。
///
/// 刻意不包含 prompt 与 cancellation:prompt 必须来自每次调用,cancellation
/// 是调用生命周期对象,不应由默认设置跨调用复用。
final class DefaultLanguageModelSettings {
  const DefaultLanguageModelSettings({
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
    this.headers,
    this.providerOptions,
  });

  final int? maxOutputTokens;
  final double? temperature;
  final double? topP;
  final double? topK;
  final double? presencePenalty;
  final double? frequencyPenalty;
  final int? seed;
  final List<String>? stopSequences;
  final provider.ResponseFormat? responseFormat;
  final List<provider.LanguageModelTool>? tools;
  final provider.ToolChoice? toolChoice;
  final provider.ReasoningEffort? reasoning;
  final bool? includeRawChunks;
  final provider.Headers? headers;
  final provider.ProviderOptions? providerOptions;
}
