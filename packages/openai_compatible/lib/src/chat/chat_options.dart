import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:equatable/equatable.dart';

/// 本包 `providerOptions[providerOptionsName]` 中已知(结构化)字段名集合。
///
/// 供 [OpenAiCompatibleChatProviderOptions.fromProviderOptions] 的 JSON
/// Schema 校验与 [extractPassthroughProviderOptions] 的透传过滤共用同一份
/// 定义,避免两处独立维护导致字段集合漂移。
const Set<String> _knownChatProviderOptionKeys = <String>{
  'user',
  'reasoningEffort',
  'textVerbosity',
  'strictJsonSchema',
};

/// `providerOptions[providerOptionsName]` 的结构化值类(chat wire 专用)。
///
/// 字段清单逐字对照 raw `compatible__openai-compatible-chat-language-model-
/// options.ts` 的 `openaiCompatibleLanguageModelChatOptions` zod schema:
/// 四个已知字段全部可空,且 [reasoningEffort]/[textVerbosity] 是**裸字符串**
/// (不像 openai 包 `OpenAiChatProviderOptions` 那样限定 enum 取值)——本包
/// 面向任意"自称兼容 OpenAI"的第三方厂商,各家取值可能不同,不做本地枚举
/// 强校验,交由服务端校验/拒绝。
final class OpenAiCompatibleChatProviderOptions with EquatableMixin {
  /// 构造一份 provider 选项值对象;所有字段均可缺省(对应"未显式设置")。
  const OpenAiCompatibleChatProviderOptions({
    this.user,
    this.reasoningEffort,
    this.textVerbosity,
    this.strictJsonSchema,
  });

  /// 终端用户标识,wire 字段 `user`。
  final String? user;

  /// 推理力度(裸字符串,取值由具体 provider 定义),wire 字段
  /// `reasoning_effort`。未设置时由 provider 侧默认(raw 注释:默认
  /// `'medium'`,不在本类中预置)。
  final String? reasoningEffort;

  /// 响应详略程度(裸字符串),wire 字段 `verbosity`。未设置时由 provider 侧
  /// 默认(raw 注释:默认 `'medium'`,不在本类中预置)。
  final String? textVerbosity;

  /// 是否使用严格 JSON Schema 校验(仅在 provider 支持结构化输出且提供了
  /// schema 时生效)。raw 注释标注默认 `true`,该默认值的落地在请求体构造
  /// 处理,不在本类中预置。
  final bool? strictJsonSchema;

  /// 从契约 [ProviderOptions] 中解析并校验出一份 [providerOptionsName] 键
  /// 对应的选项。
  ///
  /// [options] 为 `null` 或不含 [providerOptionsName] 键时,返回全字段默认
  /// (`null`)的实例。存在该键时,先用 JSON Schema 做结构校验,失败时抛出
  /// 契约 `TypeValidationError`(原样冒泡,不在此处二次包装)。
  ///
  /// [providerOptionsName] **必填**且无默认值:与 openai 包
  /// `OpenAiChatProviderOptions.fromProviderOptions` 恒读 `'openai'` 键不同,
  /// 本包的 provider 名由 `createOpenAiCompatible(name: …)` 在运行期指定,
  /// 没有可硬编码的固定键,因此调用方必须显式传入。
  static OpenAiCompatibleChatProviderOptions fromProviderOptions(
    ProviderOptions? options, {
    required String providerOptionsName,
  }) {
    final raw = options?[providerOptionsName];
    if (raw == null) {
      return const OpenAiCompatibleChatProviderOptions();
    }

    final validationResult = _validator.validate(raw);
    if (validationResult is ValidationFailure) {
      throw validationResult.error;
    }
    final value = (validationResult as ValidationSuccess).value! as JsonObject;

    return OpenAiCompatibleChatProviderOptions(
      user: value['user'] as String?,
      reasoningEffort: value['reasoningEffort'] as String?,
      textVerbosity: value['textVerbosity'] as String?,
      strictJsonSchema: value['strictJsonSchema'] as bool?,
    );
  }

  @override
  List<Object?> get props => [
        user,
        reasoningEffort,
        textVerbosity,
        strictJsonSchema,
      ];
}

final JsonSchemaValidator _validator = JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'user': <String, Object?>{'type': 'string'},
      'reasoningEffort': <String, Object?>{'type': 'string'},
      'textVerbosity': <String, Object?>{'type': 'string'},
      'strictJsonSchema': <String, Object?>{'type': 'boolean'},
    },
    'additionalProperties': true,
  }),
);

/// 提取 `providerOptions[providerOptionsName]` 中不属于已知 schema 字段的键,
/// 原样返回(用于透传进请求体,兼容第三方厂商的私有参数)。
///
/// 对齐 raw `getArgs`(`compatible__openai-compatible-chat-language-model.ts`
/// 约 296-307 行)的 `Object.fromEntries` 过滤逻辑,单一 key 版本(不做多路径
/// camelCase 合并)。[options] 为 `null` 或 [providerOptionsName] 对应的键
/// 缺失/为 `null` 时返回 `const {}`。
JsonObject extractPassthroughProviderOptions(
  ProviderOptions? options, {
  required String providerOptionsName,
}) {
  final raw = options?[providerOptionsName];
  if (raw == null) {
    return const <String, Object?>{};
  }

  return <String, Object?>{
    for (final entry in raw.entries)
      if (!_knownChatProviderOptionKeys.contains(entry.key))
        entry.key: entry.value,
  };
}
