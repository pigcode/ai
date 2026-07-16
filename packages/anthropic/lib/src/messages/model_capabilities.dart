/// 单个 Anthropic 模型的能力描述,由 modelId 子串静态判定。
///
/// 字段结构逐字对照上游 `anthropic-language-model.ts:2578-2671` 的
/// `getModelCapabilities` 返回值;新模型上线需跟表更新(spec Q1)。
final class AnthropicModelCapabilities {
  /// 用给定的能力字段构造一份能力描述。
  const AnthropicModelCapabilities({
    required this.maxOutputTokens,
    required this.supportsStructuredOutput,
    required this.supportsAdaptiveThinking,
    required this.rejectsSamplingParameters,
    required this.supportsXhighEffort,
    required this.isKnownModel,
  });

  /// 该模型允许的最大输出 token 数(用于 max_tokens 缺省与裁剪)。
  final int maxOutputTokens;

  /// 是否支持原生结构化输出(`output_config.format`)。
  final bool supportsStructuredOutput;

  /// 是否支持 adaptive thinking(`thinking: { type: 'adaptive' }`)。
  final bool supportsAdaptiveThinking;

  /// 开启 thinking 时是否拒绝 temperature/top_p/top_k 采样参数。
  final bool rejectsSamplingParameters;

  /// 是否支持 `xhigh` 档 reasoning effort。
  final bool supportsXhighEffort;

  /// 是否命中已知模型表;false 表示走兜底档(未知/第三方模型)。
  final bool isKnownModel;
}

/// 按 [modelId] 子串判定一个 Anthropic 模型的能力集合。
///
/// 纯函数,逐字对照上游 `anthropic-language-model.ts:2578-2671`:匹配语义
/// 是 `modelId.contains(...)`(非前缀,兼容 bedrock 风格
/// `anthropic.claude-...` id),且 if/else-if 分支顺序即优先级(例如
/// `claude-sonnet-4-6` 必须先于 `claude-sonnet-4-` 命中)。新模型需跟表
/// 更新(spec Q1)。
AnthropicModelCapabilities getAnthropicModelCapabilities(String modelId) {
  if (modelId.contains('claude-opus-4-8') ||
      modelId.contains('claude-opus-4-7') ||
      modelId.contains('claude-fable-5') ||
      modelId.contains('claude-sonnet-5')) {
    return const AnthropicModelCapabilities(
      maxOutputTokens: 128000,
      supportsStructuredOutput: true,
      supportsAdaptiveThinking: true,
      rejectsSamplingParameters: true,
      supportsXhighEffort: true,
      isKnownModel: true,
    );
  } else if (modelId.contains('claude-sonnet-4-6') ||
      modelId.contains('claude-opus-4-6')) {
    return const AnthropicModelCapabilities(
      maxOutputTokens: 128000,
      supportsStructuredOutput: true,
      supportsAdaptiveThinking: true,
      rejectsSamplingParameters: false,
      supportsXhighEffort: false,
      isKnownModel: true,
    );
  } else if (modelId.contains('claude-sonnet-4-5') ||
      modelId.contains('claude-opus-4-5') ||
      modelId.contains('claude-haiku-4-5')) {
    return const AnthropicModelCapabilities(
      maxOutputTokens: 64000,
      supportsStructuredOutput: true,
      supportsAdaptiveThinking: false,
      rejectsSamplingParameters: false,
      supportsXhighEffort: false,
      isKnownModel: true,
    );
  } else if (modelId.contains('claude-opus-4-1')) {
    return const AnthropicModelCapabilities(
      maxOutputTokens: 32000,
      supportsStructuredOutput: true,
      supportsAdaptiveThinking: false,
      rejectsSamplingParameters: false,
      supportsXhighEffort: false,
      isKnownModel: true,
    );
  } else if (modelId.contains('claude-sonnet-4-')) {
    return const AnthropicModelCapabilities(
      maxOutputTokens: 64000,
      supportsStructuredOutput: false,
      supportsAdaptiveThinking: false,
      rejectsSamplingParameters: false,
      supportsXhighEffort: false,
      isKnownModel: true,
    );
  } else if (modelId.contains('claude-opus-4-')) {
    return const AnthropicModelCapabilities(
      maxOutputTokens: 32000,
      supportsStructuredOutput: false,
      supportsAdaptiveThinking: false,
      rejectsSamplingParameters: false,
      supportsXhighEffort: false,
      isKnownModel: true,
    );
  } else if (modelId.contains('claude-3-haiku')) {
    return const AnthropicModelCapabilities(
      maxOutputTokens: 4096,
      supportsStructuredOutput: false,
      supportsAdaptiveThinking: false,
      rejectsSamplingParameters: false,
      supportsXhighEffort: false,
      isKnownModel: true,
    );
  } else {
    return const AnthropicModelCapabilities(
      maxOutputTokens: 4096,
      supportsStructuredOutput: false,
      supportsAdaptiveThinking: false,
      rejectsSamplingParameters: false,
      supportsXhighEffort: false,
      isKnownModel: false,
    );
  }
}

/// 判定 [modelId] 是否为 Anthropic 模型(报告 03 §4,上游 :331)。
///
/// `isKnownModel || modelId.startsWith('claude-')`——未知但以 `claude-`
/// 开头的新模型也算;第三方兼容模型(如 Minimax)不算,供 doGenerate 的
/// top_p/temperature 互斥判定消费。
bool isAnthropicModel(String modelId) =>
    getAnthropicModelCapabilities(modelId).isKnownModel ||
    modelId.startsWith('claude-');
