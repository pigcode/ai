import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:equatable/equatable.dart';

/// `thinking` provider 选项的判别联合(上游 options.ts:91-112)。
///
/// 三分支:[AnthropicThinkingEnabled] / [AnthropicThinkingAdaptive] /
/// [AnthropicThinkingDisabled];wire 侧 `thinking` 请求字段的组装(含
/// disabled 转发)在 Task 17 的模型层完成,不在本类中处理。
sealed class AnthropicThinking {
  /// 常量基构造器,供子类 `const` 构造。
  const AnthropicThinking();
}

/// `{ type: 'enabled', budgetTokens? }`:显式开启 thinking。
final class AnthropicThinkingEnabled extends AnthropicThinking
    with EquatableMixin {
  /// 构造 enabled 分支;[budgetTokens] 可缺省(使用处缺省时补 1024 并告警)。
  const AnthropicThinkingEnabled({this.budgetTokens});

  /// thinking 预算 token 数,wire 字段 `budget_tokens`。
  final int? budgetTokens;

  @override
  List<Object?> get props => [budgetTokens];
}

/// `{ type: 'adaptive', display? }`:自适应 thinking(Sonnet 4.6 / Opus 4.6
/// 及更新的 adaptive 模型)。
final class AnthropicThinkingAdaptive extends AnthropicThinking
    with EquatableMixin {
  /// 构造 adaptive 分支;[display] 可缺省。
  const AnthropicThinkingAdaptive({this.display});

  /// thinking 展示形态:`'omitted'` 或 `'summarized'`。
  final String? display;

  @override
  List<Object?> get props => [display];
}

/// `{ type: 'disabled' }`:显式关闭 thinking。
final class AnthropicThinkingDisabled extends AnthropicThinking
    with EquatableMixin {
  /// 构造 disabled 分支(无字段)。
  const AnthropicThinkingDisabled();

  @override
  List<Object?> get props => const [];
}

/// `mcpServers[]` 元素:本次请求要接入的 MCP server(:148-166)。
///
/// wire `type` 恒为 `'url'`(schema 唯一字面量,不设参);snake 化与缺席键
/// 的 wire 组装在模型层完成,本类只存数据(与 [AnthropicThinking] 分工
/// 一致)。
final class AnthropicMcpServer with EquatableMixin {
  /// 构造一个 MCP server 配置;[authorizationToken] 与 [toolConfiguration]
  /// 可缺省。
  const AnthropicMcpServer({
    required this.name,
    required this.url,
    this.authorizationToken,
    this.toolConfiguration,
  });

  /// server 名称。
  final String name;

  /// server URL。
  final String url;

  /// 授权 token,wire 字段 `authorization_token`。
  final String? authorizationToken;

  /// 工具配置,wire 字段 `tool_configuration`。
  final AnthropicMcpToolConfiguration? toolConfiguration;

  @override
  List<Object?> get props => [name, url, authorizationToken, toolConfiguration];
}

/// `mcpServers[].toolConfiguration`:MCP server 的工具配置(:158-163)。
final class AnthropicMcpToolConfiguration with EquatableMixin {
  /// 构造工具配置;两字段均可缺省。
  const AnthropicMcpToolConfiguration({this.enabled, this.allowedTools});

  /// 是否启用该 server 的工具。
  final bool? enabled;

  /// 允许使用的工具名列表,wire 字段 `allowed_tools`。
  final List<String>? allowedTools;

  @override
  List<Object?> get props => [enabled, allowedTools];
}

/// `container` provider 选项:programmatic tool calling 的容器续用
/// (纯 id)或 agent skills(id + skills)(:168-193)。
///
/// wire 双形态(字符串/对象)与空边界(id 与 skills 均缺席不发键)的
/// 组装在模型层完成。
final class AnthropicContainer with EquatableMixin {
  /// 构造容器配置;两字段均可缺省。
  const AnthropicContainer({this.id, this.skills});

  /// 既有容器 id(跨请求续用同一容器)。
  final String? id;

  /// 要加载的 skill 列表,见 [AnthropicContainerSkill]。
  final List<AnthropicContainerSkill>? skills;

  @override
  List<Object?> get props => [id, skills];
}

/// `container.skills[]` 的判别联合(:170-185)。
///
/// 两分支:[AnthropicAnthropicSkill](官方 skill)/
/// [AnthropicCustomSkill](自定义 skill)。
sealed class AnthropicContainerSkill {
  /// 常量基构造器,供子类 `const` 构造。
  const AnthropicContainerSkill();
}

/// `{ type: 'anthropic', skillId, version? }`:官方 skill 引用。
final class AnthropicAnthropicSkill extends AnthropicContainerSkill
    with EquatableMixin {
  /// 构造官方 skill 引用;[version] 可缺省。
  const AnthropicAnthropicSkill({required this.skillId, this.version});

  /// skill 标识,wire 字段 `skill_id`。
  final String skillId;

  /// skill 版本;缺席时 wire 不发 `version` 键。
  final String? version;

  @override
  List<Object?> get props => [skillId, version];
}

/// `{ type: 'custom', providerReference, version? }`:自定义 skill 引用;
/// wire `skill_id` 由模型层经 provider reference 按 `'anthropic'` 键解析。
final class AnthropicCustomSkill extends AnthropicContainerSkill
    with EquatableMixin {
  /// 构造自定义 skill 引用;[version] 可缺省。
  const AnthropicCustomSkill({required this.providerReference, this.version});

  /// provider 名 → skill id 的引用表。
  final ProviderReference providerReference;

  /// skill 版本;缺席时 wire 不发 `version` 键。
  final String? version;

  @override
  List<Object?> get props => [providerReference, version];
}

/// `taskBudget` provider 选项:agentic 任务的 token 预算提示(:211-224;
/// 仅建议性,不产生硬 token 限制)。
///
/// wire `type` 恒为 `'tokens'`(schema 唯一字面量,不设参)。
final class AnthropicTaskBudget with EquatableMixin {
  /// 构造任务预算;[remaining] 可缺省。
  const AnthropicTaskBudget({required this.total, this.remaining});

  /// 总预算 token 数(schema 约束 `>= 20000`)。
  final int total;

  /// 剩余预算 token 数(schema 约束 `>= 0`);缺席时 wire 不发
  /// `remaining` 键。
  final int? remaining;

  @override
  List<Object?> get props => [total, remaining];
}

/// `contextManagement` provider 选项:上下文编辑策略列表(:276-335)。
final class AnthropicContextManagement with EquatableMixin {
  /// 构造上下文管理配置;[edits] 必填(可为空列表——空列表 wire 仍照发,
  /// 报告 10 §9.5a)。
  const AnthropicContextManagement({required this.edits});

  /// 编辑策略列表,见 [AnthropicContextEdit]。
  final List<AnthropicContextEdit> edits;

  @override
  List<Object?> get props => [edits];
}

/// `contextManagement.edits[]` 的判别联合(:279-334):三 edit 型。
///
/// 嵌套 trigger/keep/clearAtLeast 叶子保留 raw [JsonObject](validator 层
/// 已校验形状,不再造深层值类);camel→snake 的 wire 组装在模型层完成。
sealed class AnthropicContextEdit {
  /// 常量基构造器,供子类 `const` 构造。
  const AnthropicContextEdit();
}

/// `{ type: 'clear_tool_uses_20250919', ... }`:清理工具调用历史。
final class AnthropicClearToolUses20250919Edit extends AnthropicContextEdit
    with EquatableMixin {
  /// 构造 clear_tool_uses 编辑;全部字段可缺省。
  const AnthropicClearToolUses20250919Edit({
    this.trigger,
    this.keep,
    this.clearAtLeast,
    this.clearToolInputs,
    this.excludeTools,
  });

  /// 触发条件:`{type: 'input_tokens'|'tool_uses', value}`。
  final JsonObject? trigger;

  /// 保留量:`{type: 'tool_uses', value}`。
  final JsonObject? keep;

  /// 至少清理量,wire 字段 `clear_at_least`:`{type: 'input_tokens',
  /// value}`。
  final JsonObject? clearAtLeast;

  /// 是否连工具输入一并清理,wire 字段 `clear_tool_inputs`。
  final bool? clearToolInputs;

  /// 免清理的工具名列表,wire 字段 `exclude_tools`。
  final List<String>? excludeTools;

  @override
  List<Object?> get props =>
      [trigger, keep, clearAtLeast, clearToolInputs, excludeTools];
}

/// `{ type: 'clear_thinking_20251015', keep? }`:清理 thinking 历史。
final class AnthropicClearThinking20251015Edit extends AnthropicContextEdit
    with EquatableMixin {
  /// 构造 clear_thinking 编辑;[keep] 可缺省。
  const AnthropicClearThinking20251015Edit({this.keep});

  /// 保留策略:字符串 `'all'` 或 `{type: 'thinking_turns', value}` 对象
  /// (上游 union,:192-200)。
  final Object? keep;

  @override
  List<Object?> get props => [keep];
}

/// `{ type: 'compact_20260112', ... }`:上下文压缩。
final class AnthropicCompact20260112Edit extends AnthropicContextEdit
    with EquatableMixin {
  /// 构造 compact 编辑;全部字段可缺省。
  const AnthropicCompact20260112Edit({
    this.trigger,
    this.pauseAfterCompaction,
    this.instructions,
  });

  /// 触发条件:`{type: 'input_tokens', value}`。
  final JsonObject? trigger;

  /// 压缩后是否暂停,wire 字段 `pause_after_compaction`。
  final bool? pauseAfterCompaction;

  /// 压缩指令。
  final String? instructions;

  @override
  List<Object?> get props => [trigger, pauseAfterCompaction, instructions];
}

/// `providerOptions['anthropic']` 的结构化值类(Messages wire 专用)。
///
/// 字段清单对齐上游 `anthropicLanguageModelOptions` zod schema
/// (anthropic-language-model-options.ts:68-336)全量字段(beta 选项族
/// mcpServers/container/taskBudget/speed/fallbacks/contextManagement 已
/// 补齐,:148-335)。所有字段均无 schema 级默认值,默认行为在使用处
/// (如 `sendReasoning ?? true`、`structuredOutputMode ?? 'auto'`)。
final class AnthropicMessagesProviderOptions with EquatableMixin {
  /// 构造一份 provider 选项值对象;所有字段均可缺省(对应"未显式设置")。
  const AnthropicMessagesProviderOptions({
    this.sendReasoning,
    this.structuredOutputMode,
    this.thinking,
    this.disableParallelToolUse,
    this.cacheControl,
    this.metadata,
    this.toolStreaming,
    this.effort,
    this.inferenceGeo,
    this.anthropicBeta,
    this.mcpServers,
    this.container,
    this.taskBudget,
    this.speed,
    this.fallbacks,
    this.contextManagement,
  });

  /// 是否把 reasoning 内容发回给模型;使用处默认 `?? true`
  /// (language-model.ts:391)。
  final bool? sendReasoning;

  /// 结构化输出模式:`'outputFormat' | 'jsonTool' | 'auto'`;使用处默认
  /// `?? 'auto'`(:341-342)。
  final String? structuredOutputMode;

  /// thinking 三态判别联合,见 [AnthropicThinking]。
  final AnthropicThinking? thinking;

  /// 是否禁用并行工具调用,wire 字段 `disable_parallel_tool_use`。
  final bool? disableParallelToolUse;

  /// call 级 cache_control:`{ type: 'ephemeral', ttl?: '5m' | '1h' }`,
  /// 校验后原样保留(wire 侧直传)。
  final JsonObject? cacheControl;

  /// 请求元数据:`{ userId?: String }`(wire 侧映射为 `metadata.user_id`)。
  final JsonObject? metadata;

  /// 是否启用工具输入流式(仅流式路径生效;消费接线见 prepare_tools 的
  /// `defaultEagerInputStreaming`)。
  final bool? toolStreaming;

  /// 推理力度:`'low'|'medium'|'high'|'xhigh'|'max'`。代码不主动填默认
  /// (上游注释 `@default 'high'` 但从不主动填充,报告 03 §16 疑点 4)。
  final String? effort;

  /// 推理地域:`'us' | 'global'`(无 beta 依赖)。
  final String? inferenceGeo;

  /// 追加的 `anthropic-beta` 头取值,供请求期 beta 合成消费。
  final List<String>? anthropicBeta;

  /// 请求要接入的 MCP server 列表,见 [AnthropicMcpServer];wire 字段
  /// `mcp_servers`(非空才发)。
  final List<AnthropicMcpServer>? mcpServers;

  /// 容器配置(programmatic tool calling / agent skills),见
  /// [AnthropicContainer]。
  final AnthropicContainer? container;

  /// 任务 token 预算,见 [AnthropicTaskBudget];wire 侧进
  /// `output_config.task_budget`。
  final AnthropicTaskBudget? taskBudget;

  /// 推理速度:`'fast' | 'standard'`(仅 `'fast'` 触发 fast-mode beta)。
  final String? speed;

  /// 服务端 fallback 链:raw wire 形态原样保留(schema 键本就是
  /// snake_case,上游注释 passed through to the API as-is,:242-268;
  /// 照 [cacheControl] 的 raw JsonObject 透传先例)。
  final List<JsonObject>? fallbacks;

  /// 上下文管理配置,见 [AnthropicContextManagement];wire 字段
  /// `context_management`(存在即发,含空 edits)。
  final AnthropicContextManagement? contextManagement;

  /// 从契约 [ProviderOptions] 的 canonical `'anthropic'` 键解析一份选项。
  ///
  /// [options] 为 `null` 或不含 `'anthropic'` 键时,返回全字段默认(`null`)
  /// 的实例。存在时先用 JSON Schema 做结构校验(字段类型/枚举取值范围),
  /// 失败时抛出契约 [TypeValidationError](原样冒泡,不二次包装)。
  factory AnthropicMessagesProviderOptions.fromProviderOptions(
    ProviderOptions? options,
  ) {
    final raw = options?['anthropic'];
    if (raw == null) {
      return const AnthropicMessagesProviderOptions();
    }
    return AnthropicMessagesProviderOptions._parse(raw);
  }

  /// 校验 [raw] 并逐字段读取(内部共用:canonical 与自定义 key 同一 schema)。
  factory AnthropicMessagesProviderOptions._parse(Object raw) {
    final validationResult = _validator.validate(raw);
    if (validationResult is ValidationFailure) {
      throw validationResult.error;
    }
    final value = (validationResult as ValidationSuccess).value! as JsonObject;

    return AnthropicMessagesProviderOptions(
      sendReasoning: value['sendReasoning'] as bool?,
      structuredOutputMode: value['structuredOutputMode'] as String?,
      thinking: _parseThinking(value['thinking'] as JsonObject?),
      disableParallelToolUse: value['disableParallelToolUse'] as bool?,
      cacheControl: value['cacheControl'] as JsonObject?,
      metadata: value['metadata'] as JsonObject?,
      toolStreaming: value['toolStreaming'] as bool?,
      effort: value['effort'] as String?,
      inferenceGeo: value['inferenceGeo'] as String?,
      anthropicBeta: (value['anthropicBeta'] as List<Object?>?)?.cast<String>(),
      mcpServers: _parseMcpServers(value['mcpServers'] as List<Object?>?),
      container: _parseContainer(value['container'] as JsonObject?),
      taskBudget: _parseTaskBudget(value['taskBudget'] as JsonObject?),
      speed: value['speed'] as String?,
      fallbacks: (value['fallbacks'] as List<Object?>?)?.cast<JsonObject>(),
      contextManagement:
          _parseContextManagement(value['contextManagement'] as JsonObject?),
    );
  }

  @override
  List<Object?> get props => [
        sendReasoning,
        structuredOutputMode,
        thinking,
        disableParallelToolUse,
        cacheControl,
        metadata,
        toolStreaming,
        effort,
        inferenceGeo,
        anthropicBeta,
        mcpServers,
        container,
        taskBudget,
        speed,
        fallbacks,
        contextManagement,
      ];
}

/// 将 schema 校验后的 `thinking` 对象转成判别联合。
AnthropicThinking? _parseThinking(JsonObject? value) {
  if (value == null) {
    return null;
  }
  return switch (value['type']) {
    'enabled' =>
      AnthropicThinkingEnabled(budgetTokens: value['budgetTokens'] as int?),
    'adaptive' =>
      AnthropicThinkingAdaptive(display: value['display'] as String?),
    'disabled' => const AnthropicThinkingDisabled(),
    // schema 已限定 type 枚举,此分支理论不可达;保留以满足穷举并给出
    // 契约错误而非裸 TypeError。
    final unexpected => throw TypeValidationError(
        value: unexpected,
        message: 'Unexpected thinking type: $unexpected',
      ),
  };
}

/// 将 schema 校验后的 `mcpServers` 数组转成值类列表。
List<AnthropicMcpServer>? _parseMcpServers(List<Object?>? value) {
  if (value == null) {
    return null;
  }
  return [
    for (final raw in value.cast<JsonObject>())
      AnthropicMcpServer(
        name: raw['name']! as String,
        url: raw['url']! as String,
        authorizationToken: raw['authorizationToken'] as String?,
        toolConfiguration: _parseMcpToolConfiguration(
          raw['toolConfiguration'] as JsonObject?,
        ),
      ),
  ];
}

/// 将 schema 校验后的 `toolConfiguration` 对象转成值类。
AnthropicMcpToolConfiguration? _parseMcpToolConfiguration(JsonObject? value) {
  if (value == null) {
    return null;
  }
  return AnthropicMcpToolConfiguration(
    enabled: value['enabled'] as bool?,
    allowedTools: (value['allowedTools'] as List<Object?>?)?.cast<String>(),
  );
}

/// 将 schema 校验后的 `container` 对象转成值类(skill 两型判别)。
AnthropicContainer? _parseContainer(JsonObject? value) {
  if (value == null) {
    return null;
  }
  final skills = value['skills'] as List<Object?>?;
  return AnthropicContainer(
    id: value['id'] as String?,
    skills: skills == null
        ? null
        : [
            for (final raw in skills.cast<JsonObject>())
              switch (raw['type']) {
                'anthropic' => AnthropicAnthropicSkill(
                    skillId: raw['skillId']! as String,
                    version: raw['version'] as String?,
                  ),
                'custom' => AnthropicCustomSkill(
                    providerReference: (raw['providerReference']! as JsonObject)
                        .cast<String, String>(),
                    version: raw['version'] as String?,
                  ),
                // schema oneOf 已限定 type,此分支理论不可达;保留以给出
                // 契约错误而非裸 TypeError。
                final unexpected => throw TypeValidationError(
                    value: unexpected,
                    message: 'Unexpected container skill type: $unexpected',
                  ),
              },
          ],
  );
}

/// 将 schema 校验后的 `taskBudget` 对象转成值类。
AnthropicTaskBudget? _parseTaskBudget(JsonObject? value) {
  if (value == null) {
    return null;
  }
  return AnthropicTaskBudget(
    total: (value['total']! as num).toInt(),
    remaining: (value['remaining'] as num?)?.toInt(),
  );
}

/// 将 schema 校验后的 `contextManagement` 对象转成值类(edit 三型判别)。
AnthropicContextManagement? _parseContextManagement(JsonObject? value) {
  if (value == null) {
    return null;
  }
  final edits = value['edits']! as List<Object?>;
  return AnthropicContextManagement(
    edits: [
      for (final raw in edits.cast<JsonObject>())
        switch (raw['type']) {
          'clear_tool_uses_20250919' => AnthropicClearToolUses20250919Edit(
              trigger: raw['trigger'] as JsonObject?,
              keep: raw['keep'] as JsonObject?,
              clearAtLeast: raw['clearAtLeast'] as JsonObject?,
              clearToolInputs: raw['clearToolInputs'] as bool?,
              excludeTools:
                  (raw['excludeTools'] as List<Object?>?)?.cast<String>(),
            ),
          'clear_thinking_20251015' =>
            AnthropicClearThinking20251015Edit(keep: raw['keep']),
          'compact_20260112' => AnthropicCompact20260112Edit(
              trigger: raw['trigger'] as JsonObject?,
              pauseAfterCompaction: raw['pauseAfterCompaction'] as bool?,
              instructions: raw['instructions'] as String?,
            ),
          // schema oneOf 已限定 type(未知 edit 型在 validate 阶段拒错,
          // 对齐上游 discriminatedUnion 语义);保留以给出契约错误。
          final unexpected => throw TypeValidationError(
              value: unexpected,
              message: 'Unexpected context management edit type: $unexpected',
            ),
        },
    ],
  );
}

/// 按上游双 key 语义解析 provider options(language-model.ts:270-293)。
///
/// [providerName] 为完整 provider 串(如 `'anthropic.messages'` /
/// `'my-anthropic'`),内部派生自定义 key = 首个 `.` 之前的部分(:194-198)。
/// 先解析 canonical `'anthropic'`;派生 key 不为 `'anthropic'` 且该 key 下
/// 有值时,再按同一 schema 解析并做**字段级合并(自定义覆盖 canonical)**
/// (:289-293)。`usedCustomProviderKey` 表示自定义 key 下是否有值(:286)。
({AnthropicMessagesProviderOptions options, bool usedCustomProviderKey})
    resolveAnthropicProviderOptions(
  String providerName,
  ProviderOptions? providerOptions,
) {
  final canonical =
      AnthropicMessagesProviderOptions.fromProviderOptions(providerOptions);

  final customKey = providerName.split('.').first;
  if (customKey == 'anthropic') {
    return (options: canonical, usedCustomProviderKey: false);
  }

  final rawCustom = providerOptions?[customKey];
  if (rawCustom == null) {
    return (options: canonical, usedCustomProviderKey: false);
  }

  final custom = AnthropicMessagesProviderOptions._parse(rawCustom);
  return (
    options: AnthropicMessagesProviderOptions(
      sendReasoning: custom.sendReasoning ?? canonical.sendReasoning,
      structuredOutputMode:
          custom.structuredOutputMode ?? canonical.structuredOutputMode,
      thinking: custom.thinking ?? canonical.thinking,
      disableParallelToolUse:
          custom.disableParallelToolUse ?? canonical.disableParallelToolUse,
      cacheControl: custom.cacheControl ?? canonical.cacheControl,
      metadata: custom.metadata ?? canonical.metadata,
      toolStreaming: custom.toolStreaming ?? canonical.toolStreaming,
      effort: custom.effort ?? canonical.effort,
      inferenceGeo: custom.inferenceGeo ?? canonical.inferenceGeo,
      anthropicBeta: custom.anthropicBeta ?? canonical.anthropicBeta,
      mcpServers: custom.mcpServers ?? canonical.mcpServers,
      container: custom.container ?? canonical.container,
      taskBudget: custom.taskBudget ?? canonical.taskBudget,
      speed: custom.speed ?? canonical.speed,
      fallbacks: custom.fallbacks ?? canonical.fallbacks,
      contextManagement:
          custom.contextManagement ?? canonical.contextManagement,
    ),
    usedCustomProviderKey: true,
  );
}

final JsonSchemaValidator _validator = JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'sendReasoning': <String, Object?>{'type': 'boolean'},
      'structuredOutputMode': <String, Object?>{
        'enum': <Object?>['outputFormat', 'jsonTool', 'auto'],
      },
      'thinking': <String, Object?>{
        'type': 'object',
        'oneOf': <Object?>[
          <String, Object?>{
            'properties': <String, Object?>{
              'type': <String, Object?>{
                'enum': <Object?>['enabled'],
              },
              'budgetTokens': <String, Object?>{'type': 'integer'},
            },
            'required': <Object?>['type'],
          },
          <String, Object?>{
            'properties': <String, Object?>{
              'type': <String, Object?>{
                'enum': <Object?>['adaptive'],
              },
              'display': <String, Object?>{
                'enum': <Object?>['omitted', 'summarized'],
              },
            },
            'required': <Object?>['type'],
          },
          <String, Object?>{
            'properties': <String, Object?>{
              'type': <String, Object?>{
                'enum': <Object?>['disabled'],
              },
            },
            'required': <Object?>['type'],
          },
        ],
      },
      'disableParallelToolUse': <String, Object?>{'type': 'boolean'},
      'cacheControl': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'type': <String, Object?>{
            'enum': <Object?>['ephemeral'],
          },
          'ttl': <String, Object?>{
            'enum': <Object?>['5m', '1h'],
          },
        },
        'required': <Object?>['type'],
      },
      'metadata': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'userId': <String, Object?>{'type': 'string'},
        },
      },
      'toolStreaming': <String, Object?>{'type': 'boolean'},
      'effort': <String, Object?>{
        'enum': <Object?>['low', 'medium', 'high', 'xhigh', 'max'],
      },
      'inferenceGeo': <String, Object?>{
        'enum': <Object?>['us', 'global'],
      },
      'anthropicBeta': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
      'mcpServers': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'type': <String, Object?>{
              'enum': <Object?>['url'],
            },
            'name': <String, Object?>{'type': 'string'},
            'url': <String, Object?>{'type': 'string'},
            'authorizationToken': <String, Object?>{
              'type': <Object?>['string', 'null'],
            },
            'toolConfiguration': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'enabled': <String, Object?>{'type': 'boolean'},
                'allowedTools': <String, Object?>{
                  'type': 'array',
                  'items': <String, Object?>{'type': 'string'},
                },
              },
            },
          },
          'required': <Object?>['type', 'name', 'url'],
        },
      },
      'container': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'id': <String, Object?>{'type': 'string'},
          'skills': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{
              'type': 'object',
              'oneOf': <Object?>[
                <String, Object?>{
                  'properties': <String, Object?>{
                    'type': <String, Object?>{
                      'enum': <Object?>['anthropic'],
                    },
                    'skillId': <String, Object?>{'type': 'string'},
                    'version': <String, Object?>{'type': 'string'},
                  },
                  'required': <Object?>['type', 'skillId'],
                },
                <String, Object?>{
                  'properties': <String, Object?>{
                    'type': <String, Object?>{
                      'enum': <Object?>['custom'],
                    },
                    'providerReference': <String, Object?>{
                      'type': 'object',
                      'additionalProperties': <String, Object?>{
                        'type': 'string',
                      },
                    },
                    'version': <String, Object?>{'type': 'string'},
                  },
                  'required': <Object?>['type', 'providerReference'],
                },
              ],
            },
          },
        },
      },
      'taskBudget': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'type': <String, Object?>{
            'enum': <Object?>['tokens'],
          },
          'total': <String, Object?>{'type': 'integer', 'minimum': 20000},
          'remaining': <String, Object?>{'type': 'integer', 'minimum': 0},
        },
        'required': <Object?>['type', 'total'],
      },
      'speed': <String, Object?>{
        'enum': <Object?>['fast', 'standard'],
      },
      'fallbacks': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'model': <String, Object?>{'type': 'string'},
            'max_tokens': <String, Object?>{'type': 'integer'},
            'thinking': <String, Object?>{'type': 'object'},
            'output_config': <String, Object?>{'type': 'object'},
            'speed': <String, Object?>{
              'enum': <Object?>['fast', 'standard'],
            },
          },
          'required': <Object?>['model'],
        },
      },
      'contextManagement': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'edits': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{
              'type': 'object',
              'oneOf': <Object?>[
                <String, Object?>{
                  'properties': <String, Object?>{
                    'type': <String, Object?>{
                      'enum': <Object?>['clear_tool_uses_20250919'],
                    },
                    'trigger': <String, Object?>{
                      'type': 'object',
                      'oneOf': <Object?>[
                        <String, Object?>{
                          'properties': <String, Object?>{
                            'type': <String, Object?>{
                              'enum': <Object?>['input_tokens'],
                            },
                            'value': <String, Object?>{'type': 'number'},
                          },
                          'required': <Object?>['type', 'value'],
                        },
                        <String, Object?>{
                          'properties': <String, Object?>{
                            'type': <String, Object?>{
                              'enum': <Object?>['tool_uses'],
                            },
                            'value': <String, Object?>{'type': 'number'},
                          },
                          'required': <Object?>['type', 'value'],
                        },
                      ],
                    },
                    'keep': <String, Object?>{
                      'type': 'object',
                      'properties': <String, Object?>{
                        'type': <String, Object?>{
                          'enum': <Object?>['tool_uses'],
                        },
                        'value': <String, Object?>{'type': 'number'},
                      },
                      'required': <Object?>['type', 'value'],
                    },
                    'clearAtLeast': <String, Object?>{
                      'type': 'object',
                      'properties': <String, Object?>{
                        'type': <String, Object?>{
                          'enum': <Object?>['input_tokens'],
                        },
                        'value': <String, Object?>{'type': 'number'},
                      },
                      'required': <Object?>['type', 'value'],
                    },
                    'clearToolInputs': <String, Object?>{'type': 'boolean'},
                    'excludeTools': <String, Object?>{
                      'type': 'array',
                      'items': <String, Object?>{'type': 'string'},
                    },
                  },
                  'required': <Object?>['type'],
                },
                <String, Object?>{
                  'properties': <String, Object?>{
                    'type': <String, Object?>{
                      'enum': <Object?>['clear_thinking_20251015'],
                    },
                    'keep': <String, Object?>{
                      'oneOf': <Object?>[
                        <String, Object?>{
                          'enum': <Object?>['all'],
                        },
                        <String, Object?>{
                          'type': 'object',
                          'properties': <String, Object?>{
                            'type': <String, Object?>{
                              'enum': <Object?>['thinking_turns'],
                            },
                            'value': <String, Object?>{'type': 'number'},
                          },
                          'required': <Object?>['type', 'value'],
                        },
                      ],
                    },
                  },
                  'required': <Object?>['type'],
                },
                <String, Object?>{
                  'properties': <String, Object?>{
                    'type': <String, Object?>{
                      'enum': <Object?>['compact_20260112'],
                    },
                    'trigger': <String, Object?>{
                      'type': 'object',
                      'properties': <String, Object?>{
                        'type': <String, Object?>{
                          'enum': <Object?>['input_tokens'],
                        },
                        'value': <String, Object?>{'type': 'number'},
                      },
                      'required': <Object?>['type', 'value'],
                    },
                    'pauseAfterCompaction': <String, Object?>{
                      'type': 'boolean',
                    },
                    'instructions': <String, Object?>{'type': 'string'},
                  },
                  'required': <Object?>['type'],
                },
              ],
            },
          },
        },
        'required': <Object?>['edits'],
      },
    },
    'additionalProperties': true,
  }),
);
