/// 系统消息在请求体中的映射方式。
///
/// 对照 raw `systemMessageMode?: 'system' | 'developer' | 'remove'`(见
/// `convert-to-openai-chat-messages.ts`/`convert-to-openai-responses-input.ts`
/// 的消费方);由 [getOpenAiLanguageModelCapabilities] 按 modelId 前缀判定
/// 产出(当前实现只产出 [system]/[developer] 两支,[remove] 保留给未来
/// 对不支持系统消息的模型——如 legacy `o1-mini`——的判定分支,字段本身
/// 现在就建全以承载后续 additive 扩展)。
enum SystemMessageMode { system, developer, remove }

/// 单个 OpenAI 模型的能力描述,由 modelId 前缀静态判定。
///
/// 字段结构对照 raw `OpenAILanguageModelCapabilities`(`openai-language-model-capabilities.ts`)
/// 建全;首版实现覆盖 raw 函数体已有的判定逻辑,`search-preview`/
/// `service_tier` 等更细分的白名单判定延后(设计文档 §1 非目标)。
final class OpenAiLanguageModelCapabilities {
  /// 用给定的能力字段构造一份能力描述。
  const OpenAiLanguageModelCapabilities({
    required this.isReasoningModel,
    required this.systemMessageMode,
    required this.supportsFlexProcessing,
    required this.supportsPriorityProcessing,
    required this.supportsNonReasoningParameters,
  });

  /// 是否为推理模型(o1/o3/o4-mini/gpt-5 系列,不含 gpt-5-chat)。
  ///
  /// 对照 raw 注释:采用白名单前缀判定而非黑名单,避免误伤微调模型、
  /// 第三方模型与自定义模型。
  final bool isReasoningModel;

  /// 系统消息映射方式,由 [isReasoningModel] 派生
  /// (`isReasoningModel ? developer : system`)。
  final SystemMessageMode systemMessageMode;

  /// 是否支持 `service_tier: 'flex'`(flex processing)。
  final bool supportsFlexProcessing;

  /// 是否支持 `service_tier: 'priority'`(priority processing)。
  final bool supportsPriorityProcessing;

  /// 是否在 `reasoningEffort` 为 `none` 时仍支持 temperature/topP/logProbs
  /// 等非推理采样参数(GPT-5.1 及更新的模型族)。
  final bool supportsNonReasoningParameters;
}

/// 按 [modelId] 前缀判定一个 OpenAI 模型的能力集合。
///
/// 纯函数,逐字对照 raw `getOpenAILanguageModelCapabilities` 的判定顺序与
/// 前缀规则(见 `openai-language-model-capabilities.ts`):
/// - `supportsFlexProcessing`:`o3*` 或 `o4-mini*` 或(`gpt-5*` 且非
///   `gpt-5-chat*`)。
/// - `supportsPriorityProcessing`:`gpt-4*`,或(`gpt-5*` 且非
///   `gpt-5-nano*`/`gpt-5-chat*`/`gpt-5.4-nano*`),或 `o3*`/`o4-mini*`。
/// - `isReasoningModel`:`o1*`/`o3*`/`o4-mini*`,或(`gpt-5*` 且非
///   `gpt-5-chat*`)。
/// - `supportsNonReasoningParameters`:`gpt-5.1*`/`gpt-5.2*`/`gpt-5.3*`/
///   `gpt-5.4*`/`gpt-5.5*`。
/// - `systemMessageMode`:`isReasoningModel ? developer : system`
///   (raw 函数体本身从不产出 `'remove'`,与枚举定义处的说明一致)。
OpenAiLanguageModelCapabilities getOpenAiLanguageModelCapabilities(
  String modelId,
) {
  final supportsFlexProcessing = modelId.startsWith('o3') ||
      modelId.startsWith('o4-mini') ||
      (modelId.startsWith('gpt-5') && !modelId.startsWith('gpt-5-chat'));

  final supportsPriorityProcessing = modelId.startsWith('gpt-4') ||
      (modelId.startsWith('gpt-5') &&
          !modelId.startsWith('gpt-5-nano') &&
          !modelId.startsWith('gpt-5-chat') &&
          !modelId.startsWith('gpt-5.4-nano')) ||
      modelId.startsWith('o3') ||
      modelId.startsWith('o4-mini');

  final isReasoningModel = modelId.startsWith('o1') ||
      modelId.startsWith('o3') ||
      modelId.startsWith('o4-mini') ||
      (modelId.startsWith('gpt-5') && !modelId.startsWith('gpt-5-chat'));

  final supportsNonReasoningParameters = modelId.startsWith('gpt-5.1') ||
      modelId.startsWith('gpt-5.2') ||
      modelId.startsWith('gpt-5.3') ||
      modelId.startsWith('gpt-5.4') ||
      modelId.startsWith('gpt-5.5');

  final systemMessageMode =
      isReasoningModel ? SystemMessageMode.developer : SystemMessageMode.system;

  return OpenAiLanguageModelCapabilities(
    isReasoningModel: isReasoningModel,
    systemMessageMode: systemMessageMode,
    supportsFlexProcessing: supportsFlexProcessing,
    supportsPriorityProcessing: supportsPriorityProcessing,
    supportsNonReasoningParameters: supportsNonReasoningParameters,
  );
}
