import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:equatable/equatable.dart';

import '../internal/capabilities.dart';

/// `providerOptions['openai']` 的结构化值类(chat wire 专用)。
///
/// 字段清单对齐 v7 `openaiLanguageModelChatOptions` zod schema(逐字段名沿用
/// camelCase provider-options 命名,wire 层 snake_case 转换在
/// `chat_language_model.dart` 的 `_buildArgs` 中完成,不在本类中处理)。
final class OpenAiChatProviderOptions with EquatableMixin {
  /// 构造一份 provider 选项值对象;所有字段均可缺省(对应"未显式设置")。
  const OpenAiChatProviderOptions({
    this.logitBias,
    this.logprobs,
    this.parallelToolCalls,
    this.user,
    this.reasoningEffort,
    this.maxCompletionTokens,
    this.store,
    this.metadata,
    this.prediction,
    this.serviceTier,
    this.strictJsonSchema,
    this.textVerbosity,
    this.promptCacheKey,
    this.promptCacheRetention,
    this.safetyIdentifier,
    this.systemMessageMode,
    this.forceReasoning,
  });

  /// token id → 偏置值(-100..100),wire 字段 `logit_bias`。
  final Map<String, num>? logitBias;

  /// `true`(仅开关)或 `int`(top-n),wire 层拆成 `logprobs`/`top_logprobs`
  /// 两个字段。
  final Object? logprobs;

  /// 是否允许并行工具调用,wire 字段 `parallel_tool_calls`。
  final bool? parallelToolCalls;

  /// 终端用户标识,wire 字段 `user`。
  final String? user;

  /// 推理力度,wire 字段 `reasoning_effort`。
  final String? reasoningEffort;

  /// 推理模型的补全 token 上限,wire 字段 `max_completion_tokens`。
  final int? maxCompletionTokens;

  /// 是否持久化响应,wire 字段 `store`。
  final bool? store;

  /// 请求元数据,wire 字段 `metadata`。
  final Map<String, String>? metadata;

  /// 预测模式参数,wire 字段 `prediction`。
  final Map<String, Object?>? prediction;

  /// 服务分级,wire 字段 `service_tier`。
  final String? serviceTier;

  /// 是否启用严格 JSON Schema 校验,默认 `true`(在 `_buildArgs` 中兜底,不
  /// 在本类里预置默认值)。
  final bool? strictJsonSchema;

  /// 响应详略程度,wire 字段 `verbosity`。
  final String? textVerbosity;

  /// prompt 缓存键,wire 字段 `prompt_cache_key`。
  final String? promptCacheKey;

  /// prompt 缓存保留策略,wire 字段 `prompt_cache_retention`。
  final String? promptCacheRetention;

  /// 安全标识符,wire 字段 `safety_identifier`。
  final String? safetyIdentifier;

  /// 覆盖系统消息映射模式(不设置时由能力表 + 是否推理模型推断)。
  final SystemMessageMode? systemMessageMode;

  /// 强制把该模型当作推理模型处理(用于第三方/隐藏推理模型)。
  final bool? forceReasoning;

  /// 从契约 [ProviderOptions] 中解析并校验出一份 `openai` 键对应的选项。
  ///
  /// [options] 为 `null` 或不含 `'openai'` 键时,返回全字段默认(`null`)的
  /// 实例。存在 `'openai'` 键时,先用 JSON Schema 做结构校验(字段类型/
  /// 枚举取值范围),失败时抛出契约 `TypeValidationError`(原样冒泡,不在
  /// 此处二次包装)。
  factory OpenAiChatProviderOptions.fromProviderOptions(
    ProviderOptions? options,
  ) {
    final raw = options?['openai'];
    if (raw == null) {
      return const OpenAiChatProviderOptions();
    }

    final validationResult = _validator.validate(raw);
    if (validationResult is ValidationFailure) {
      throw validationResult.error;
    }
    final value = (validationResult as ValidationSuccess).value! as JsonObject;

    return OpenAiChatProviderOptions(
      logitBias: (value['logitBias'] as JsonObject?)
          ?.map((key, v) => MapEntry(key, v! as num)),
      logprobs: value['logprobs'],
      parallelToolCalls: value['parallelToolCalls'] as bool?,
      user: value['user'] as String?,
      reasoningEffort: value['reasoningEffort'] as String?,
      maxCompletionTokens: value['maxCompletionTokens'] as int?,
      store: value['store'] as bool?,
      metadata: (value['metadata'] as JsonObject?)
          ?.map((key, v) => MapEntry(key, v! as String)),
      prediction: value['prediction'] as JsonObject?,
      serviceTier: value['serviceTier'] as String?,
      strictJsonSchema: value['strictJsonSchema'] as bool?,
      textVerbosity: value['textVerbosity'] as String?,
      promptCacheKey: value['promptCacheKey'] as String?,
      promptCacheRetention: value['promptCacheRetention'] as String?,
      safetyIdentifier: value['safetyIdentifier'] as String?,
      systemMessageMode: switch (value['systemMessageMode'] as String?) {
        'system' => SystemMessageMode.system,
        'developer' => SystemMessageMode.developer,
        'remove' => SystemMessageMode.remove,
        null => null,
        final unexpected => throw TypeValidationError(
            value: unexpected,
            message: 'Unexpected systemMessageMode: $unexpected',
          ),
      },
      forceReasoning: value['forceReasoning'] as bool?,
    );
  }

  @override
  List<Object?> get props => [
        logitBias,
        logprobs,
        parallelToolCalls,
        user,
        reasoningEffort,
        maxCompletionTokens,
        store,
        metadata,
        prediction,
        serviceTier,
        strictJsonSchema,
        textVerbosity,
        promptCacheKey,
        promptCacheRetention,
        safetyIdentifier,
        systemMessageMode,
        forceReasoning,
      ];
}

final JsonSchemaValidator _validator = JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'logitBias': <String, Object?>{
        'type': 'object',
        'additionalProperties': <String, Object?>{'type': 'number'},
      },
      'logprobs': <String, Object?>{
        'oneOf': <Object?>[
          <String, Object?>{'type': 'boolean'},
          <String, Object?>{'type': 'integer'},
        ],
      },
      'parallelToolCalls': <String, Object?>{'type': 'boolean'},
      'user': <String, Object?>{'type': 'string'},
      'reasoningEffort': <String, Object?>{
        'enum': <Object?>['none', 'minimal', 'low', 'medium', 'high', 'xhigh'],
      },
      'maxCompletionTokens': <String, Object?>{'type': 'integer'},
      'store': <String, Object?>{'type': 'boolean'},
      'metadata': <String, Object?>{
        'type': 'object',
        'additionalProperties': <String, Object?>{'type': 'string'},
      },
      'prediction': <String, Object?>{'type': 'object'},
      'serviceTier': <String, Object?>{
        'enum': <Object?>['auto', 'flex', 'priority', 'default'],
      },
      'strictJsonSchema': <String, Object?>{'type': 'boolean'},
      'textVerbosity': <String, Object?>{
        'enum': <Object?>['low', 'medium', 'high'],
      },
      'promptCacheKey': <String, Object?>{'type': 'string'},
      'promptCacheRetention': <String, Object?>{
        'enum': <Object?>['in_memory', '24h'],
      },
      'safetyIdentifier': <String, Object?>{'type': 'string'},
      'systemMessageMode': <String, Object?>{
        'enum': <Object?>['system', 'developer', 'remove'],
      },
      'forceReasoning': <String, Object?>{'type': 'boolean'},
    },
    'additionalProperties': true,
  }),
);
