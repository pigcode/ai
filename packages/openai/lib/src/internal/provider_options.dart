/// chat 与 responses 两套 wire 共用的 provider-options 键派生 helper。
///
/// 不进 `pigcode_ai_openai.dart` barrel——纯内部实现细节,只供
/// `chat/chat_language_model.dart`/`responses/responses_language_model.dart`
/// 直接 import。
library;

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 按 provider 名派生 provider options 键(逐字对齐
/// `raw/openai-responses-language-model.ts` ~181 行:
/// `providerOptionsName = provider.includes('azure') ? 'azure' : 'openai'`)。
///
/// chat 与 responses 两套 wire 共用同一份派生逻辑,既用于本文件的
/// call 级重映射([resolveOpenAiProviderOptions]),也用于 responses
/// 侧转换器/输出侧 metadata 的 part 级/输出 key 派生(见
/// `responses/convert_input.dart`、`responses/responses_language_model.dart`),
/// 保证同一个 `createOpenAi(name: 'azure-...')` 实例下所有 provider
/// options 键的解析与输出行为对称。
String resolveOpenAiProviderOptionsName(String providerName) =>
    providerName.contains('azure') ? 'azure' : 'openai';

/// 按 provider 名派生 provider options 键并把该键下的内容重映射到
/// `'openai'` 键,供 `OpenAiChatProviderOptions.fromProviderOptions`/
/// `OpenAiResponsesProviderOptions.fromProviderOptions`(签名固定、恒读
/// `'openai'` 键)解析。
///
/// 派生键命中且非 `'openai'` 时优先读取该键;若该键缺失,原样保留
/// [options],让 `fromProviderOptions` 按其固有逻辑回退读取 `'openai'`
/// 键(与 v7 `openaiOptions == null && providerOptionsName !== 'openai'`
/// 的二次解析语义等价)。派生键即为 `'openai'`(非 azure provider)时
/// 无需重映射,直接原样返回。
ProviderOptions? resolveOpenAiProviderOptions(
  String providerName,
  ProviderOptions? options,
) {
  final derivedKey = resolveOpenAiProviderOptionsName(providerName);
  if (derivedKey == 'openai') {
    return options;
  }

  final derived = options?[derivedKey];
  if (derived == null) {
    return options;
  }

  return {...?options, 'openai': derived};
}
