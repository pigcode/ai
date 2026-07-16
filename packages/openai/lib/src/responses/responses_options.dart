import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:equatable/equatable.dart';

import '../internal/capabilities.dart';

/// `openai` provider options 的 JSON Schema(仅用于结构校验,不导出)。
///
/// 字段清单对照上游 `openaiLanguageModelResponsesOptionsSchema`(zod)逐字
/// 取舍;`allowedTools`/`contextManagement`/`passThroughUnsupportedFiles`
/// 三个字段首版既不消费也不透传,故不建模、不出现在本 schema 中(未知
/// 键不做 `additionalProperties: false` 限制,允许调用方随意携带,避免
/// 因为提前建模不完整而拒绝合法请求)。
final _validator = JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'conversation': <String, Object?>{'type': 'string'},
      'include': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
      'instructions': <String, Object?>{'type': 'string'},
      'logprobs': <String, Object?>{
        'oneOf': <Object?>[
          <String, Object?>{'type': 'boolean'},
          <String, Object?>{'type': 'integer', 'minimum': 1, 'maximum': 20},
        ],
      },
      'maxToolCalls': <String, Object?>{'type': 'integer'},
      'metadata': <String, Object?>{'type': 'object'},
      'parallelToolCalls': <String, Object?>{'type': 'boolean'},
      'previousResponseId': <String, Object?>{'type': 'string'},
      'promptCacheKey': <String, Object?>{'type': 'string'},
      'promptCacheRetention': <String, Object?>{
        'enum': <Object?>['in_memory', '24h'],
      },
      'reasoningEffort': <String, Object?>{'type': 'string'},
      'reasoningSummary': <String, Object?>{'type': 'string'},
      'safetyIdentifier': <String, Object?>{'type': 'string'},
      'serviceTier': <String, Object?>{
        'enum': <Object?>['auto', 'flex', 'priority', 'default'],
      },
      'store': <String, Object?>{'type': 'boolean'},
      'strictJsonSchema': <String, Object?>{'type': 'boolean'},
      'textVerbosity': <String, Object?>{
        'enum': <Object?>['low', 'medium', 'high'],
      },
      'truncation': <String, Object?>{
        'enum': <Object?>['auto', 'disabled'],
      },
      'user': <String, Object?>{'type': 'string'},
      'systemMessageMode': <String, Object?>{
        'enum': <Object?>['system', 'developer', 'remove'],
      },
      'forceReasoning': <String, Object?>{'type': 'boolean'},
    },
  }),
);

/// `openai` responses provider options(不可变值类)。
///
/// 字段清单对照上游 `openai-responses-language-model-options.ts`
/// (`openaiLanguageModelResponsesOptionsSchema`)逐字取舍;首版实现
/// 「被 Task 14 请求构造实际消费」的字段全部建模,`allowedTools`/
/// `contextManagement`/`passThroughUnsupportedFiles` 延后(见设计
/// 文档 §1 非目标)。
final class OpenAiResponsesProviderOptions with EquatableMixin {
  /// 用给定字段构造一份 responses provider options(全部可空)。
  const OpenAiResponsesProviderOptions({
    this.conversation,
    this.include,
    this.instructions,
    this.logprobs,
    this.maxToolCalls,
    this.metadata,
    this.parallelToolCalls,
    this.previousResponseId,
    this.promptCacheKey,
    this.promptCacheRetention,
    this.reasoningEffort,
    this.reasoningSummary,
    this.safetyIdentifier,
    this.serviceTier,
    this.store,
    this.strictJsonSchema,
    this.textVerbosity,
    this.truncation,
    this.user,
    this.systemMessageMode,
    this.forceReasoning,
  });

  /// 续接的 conversation id,与 [previousResponseId] 互斥(请求构造层校验)。
  final String? conversation;

  /// 额外 include 字段(wire 枚举值原样字符串,如
  /// `'reasoning.encrypted_content'`)。
  final List<String>? include;

  /// 顶层指令,续接 [previousResponseId] 时可覆盖系统/开发者消息。
  final String? instructions;

  /// `true`/`false` 或 1~20 的整数(top_logprobs 数量)。
  final Object? logprobs;

  /// 跨所有内置工具的调用次数上限。
  final int? maxToolCalls;

  /// 随生成存储的附加元数据。
  final JsonObject? metadata;

  /// 是否允许并行工具调用,默认 `true`。
  final bool? parallelToolCalls;

  /// 续接的上一轮响应 id。
  final String? previousResponseId;

  /// 提示缓存 key。
  final String? promptCacheKey;

  /// 提示缓存保留策略:`'in_memory'` 或 `'24h'`。
  final String? promptCacheRetention;

  /// 推理力度:`'none'|'minimal'|'low'|'medium'|'high'|'xhigh'`。
  final String? reasoningEffort;

  /// 推理摘要详略:`'auto'|'detailed'`。
  final String? reasoningSummary;

  /// 安全监控标识。
  final String? safetyIdentifier;

  /// 服务层级:`'auto'|'flex'|'priority'|'default'`。
  final String? serviceTier;

  /// 是否存储本次生成,默认 `true`。
  final bool? store;

  /// 是否使用严格 JSON Schema 校验,默认 `true`。
  final bool? strictJsonSchema;

  /// 响应详略度:`'low'|'medium'|'high'`。
  final String? textVerbosity;

  /// 输出截断策略:`'auto'|'disabled'`。
  final String? truncation;

  /// 终端用户标识。
  final String? user;

  /// 覆盖系统消息模式(未指定时由能力表推导)。
  final SystemMessageMode? systemMessageMode;

  /// 强制按推理模型处理(用于自定义 baseURL 下的隐身推理模型)。
  final bool? forceReasoning;

  /// 从契约 [ProviderOptions] 的 `'openai'` 键解析出本值类。
  ///
  /// [options] 为 `null` 或缺失 `'openai'` 键时返回全字段默认(全 `null`)
  /// 的实例;命中时先经 [JsonSchemaValidator] 结构校验(失败抛
  /// [TypeValidationError],原样冒泡不重复包装),通过后逐字段读取构造。
  factory OpenAiResponsesProviderOptions.fromProviderOptions(
    ProviderOptions? options,
  ) {
    final raw = options?['openai'];
    if (raw == null) {
      return const OpenAiResponsesProviderOptions();
    }

    final validated = validateTypes(raw, _validator) as JsonObject;

    return OpenAiResponsesProviderOptions(
      conversation: validated['conversation'] as String?,
      include: (validated['include'] as List<Object?>?)?.cast<String>(),
      instructions: validated['instructions'] as String?,
      logprobs: validated['logprobs'],
      maxToolCalls: validated['maxToolCalls'] as int?,
      metadata: validated['metadata'] as JsonObject?,
      parallelToolCalls: validated['parallelToolCalls'] as bool?,
      previousResponseId: validated['previousResponseId'] as String?,
      promptCacheKey: validated['promptCacheKey'] as String?,
      promptCacheRetention: validated['promptCacheRetention'] as String?,
      reasoningEffort: validated['reasoningEffort'] as String?,
      reasoningSummary: validated['reasoningSummary'] as String?,
      safetyIdentifier: validated['safetyIdentifier'] as String?,
      serviceTier: validated['serviceTier'] as String?,
      store: validated['store'] as bool?,
      strictJsonSchema: validated['strictJsonSchema'] as bool?,
      textVerbosity: validated['textVerbosity'] as String?,
      truncation: validated['truncation'] as String?,
      user: validated['user'] as String?,
      systemMessageMode: switch (validated['systemMessageMode'] as String?) {
        'system' => SystemMessageMode.system,
        'developer' => SystemMessageMode.developer,
        'remove' => SystemMessageMode.remove,
        null => null,
        final unknown => throw UnsupportedError(
            'Unreachable: schema already restricts systemMessageMode to '
            'known enum values, got $unknown',
          ),
      },
      forceReasoning: validated['forceReasoning'] as bool?,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        conversation,
        include,
        instructions,
        logprobs,
        maxToolCalls,
        metadata,
        parallelToolCalls,
        previousResponseId,
        promptCacheKey,
        promptCacheRetention,
        reasoningEffort,
        reasoningSummary,
        safetyIdentifier,
        serviceTier,
        store,
        strictJsonSchema,
        textVerbosity,
        truncation,
        user,
        systemMessageMode,
        forceReasoning,
      ];
}
