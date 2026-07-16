import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import '../internal/config.dart';
import '../internal/error.dart';
import '../internal/stream_error_probe.dart';
import 'cache_control.dart';
import 'convert_messages.dart';
import 'convert_usage.dart';
import 'map_stop_reason.dart';
import 'messages_options.dart';
import 'model_capabilities.dart';
import 'prepare_tools.dart';
import 'sanitize_json_schema.dart';

/// Anthropic Messages API(`/v1/messages`)的 [LanguageModel] 实现。
final class AnthropicMessagesLanguageModel implements LanguageModel {
  /// 用给定的 [modelId] 与 [config] 构造一个 messages 模型实例。
  AnthropicMessagesLanguageModel(this.modelId, {required this.config});

  @override
  final String modelId;

  /// 共享的 provider 配置(providerName/baseUrl/headers/client)。
  final AnthropicConfig config;

  @override
  String get specificationVersion => languageModelSpecVersion;

  @override
  String get provider => config.providerName;

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls =>
      anthropicSupportedUrls();

  Uri get _requestUrl => Uri.parse('${config.baseUrl}/messages');

  /// messages 请求体构造:`doGenerate`/`doStream` 共用。
  ///
  /// wire 语义逐字对照上游 `getArgs`(报告 03 §5/§7);[stream] 只喂
  /// toolStreaming 的默认值 `stream && (toolStreaming ?? true)`(上游
  /// :733-734,非流式恒 false),`'stream': true` body 字段仍由 doStream
  /// 自己追加。返回的 `betas` 为推导 beta 集合(prompt 侧 + tools 侧 +
  /// `anthropicOptions.anthropicBeta`),供请求头合成消费;
  /// `usesJsonResponseTool` 标记结构化输出走了 json tool 回退模式,
  /// 供响应解析特判与 finishReason 消费。
  ({
    JsonObject args,
    List<Warning> warnings,
    Set<String> betas,
    bool usesJsonResponseTool,
    bool usedCustomProviderKey,
  }) _buildArgs(LanguageModelCallOptions options, {required bool stream}) {
    final warnings = <Warning>[];
    final resolvedOptions = resolveAnthropicProviderOptions(
      config.providerName,
      options.providerOptions,
    );
    final anthropicOptions = resolvedOptions.options;
    final capabilities = getAnthropicModelCapabilities(modelId);

    // 不支持的标准参数(报告 03 §5 第 1-3 条,:227-237)。
    if (options.frequencyPenalty != null) {
      warnings.add(const UnsupportedWarning('frequencyPenalty'));
    }
    if (options.presencePenalty != null) {
      warnings.add(const UnsupportedWarning('presencePenalty'));
    }
    if (options.seed != null) {
      warnings.add(const UnsupportedWarning('seed'));
    }

    // temperature clamp 到 [0, 1](报告 03 §5 第 4 条,:239-253)。
    var temperature = options.temperature;
    if (temperature != null) {
      if (temperature > 1) {
        warnings.add(UnsupportedWarning(
          'temperature',
          details: '$temperature exceeds anthropic maximum of 1.0. '
              'clamped to 1.0',
        ));
        temperature = 1;
      } else if (temperature < 0) {
        warnings.add(UnsupportedWarning(
          'temperature',
          details: '$temperature is below anthropic minimum of 0.0. '
              'clamped to 0.0',
        ));
        temperature = 0;
      }
    }

    // 结构化输出双模式(报告 03 §6):structuredOutputMode 缺省 'auto',
    // useStructuredOutput = mode=='outputFormat' || (auto && 模型能力支持)
    // (:341-345;config 级 supportsNativeStructuredOutput 开关首版不建,
    // 上游供 bedrock/vertex 复用,pigcode 无消费者,spec §4)。schema 缺失
    // 时发 warning 并整体忽略(:255-265)。
    Map<String, Object?>? outputFormat;
    FunctionTool? jsonResponseTool;
    final responseFormat = options.responseFormat;
    if (responseFormat is ResponseFormatJson) {
      final schema = responseFormat.schema;
      if (schema == null) {
        warnings.add(const OtherWarning(
          'JSON response format requires a schema. '
          'The response format is ignored.',
        ));
      } else {
        final mode = anthropicOptions.structuredOutputMode ?? 'auto';
        final useStructuredOutput = mode == 'outputFormat' ||
            (mode == 'auto' && capabilities.supportsStructuredOutput);
        if (useStructuredOutput) {
          // 原生模式:output_config.format 携带 sanitize 后的副本
          // (:473-480;本地保留原 schema 不动)。
          outputFormat = <String, Object?>{
            'type': 'json_schema',
            'schema': sanitizeJsonSchema(schema.value),
          };
        } else {
          // 回退模式:追加 name 为 'json' 的响应工具(:347-357);
          // input_schema 照上游原样直传不清洗(origin/main :354,
          // sanitize 仅 output_config.format 路径)。
          jsonResponseTool = FunctionTool(
            name: 'json',
            description: 'Respond with a JSON object.',
            inputSchema: schema,
          );
        }
      }
    }
    final usesJsonResponseTool = jsonResponseTool != null;

    // rejectsSamplingParameters 模型裁剪采样参数(报告 03 §5 第 6 条,
    // :304-329);此分支在 clamp 之后执行,越界温度会先后产生两条 warning
    // (spec 疑点 #10 照上游)。
    var topK = options.topK;
    var topP = options.topP;
    if (capabilities.rejectsSamplingParameters) {
      if (temperature != null) {
        warnings.add(UnsupportedWarning(
          'temperature',
          details:
              'temperature is not supported by $modelId and will be ignored',
        ));
        temperature = null;
      }
      if (topK != null) {
        warnings.add(UnsupportedWarning(
          'topK',
          details: 'topK is not supported by $modelId and will be ignored',
        ));
        topK = null;
      }
      if (topP != null) {
        warnings.add(UnsupportedWarning(
          'topP',
          details: 'topP is not supported by $modelId and will be ignored',
        ));
        topP = null;
      }
    }

    // thinking / reasoning 解析(报告 03 §8.1,:401-420):先取
    // providerOptions 的 thinking/effort;顶层 reasoning 仅在自定义值
    // (非 null 且非 providerDefault)且 effort 未显式设置时才映射,且
    // thinking 仅原为 null 时填充、effort 仅映射结果非空且 thinking 非
    // disabled 时填充(providerOptions 永远优先)。
    var thinking = anthropicOptions.thinking;
    var effort = anthropicOptions.effort;
    final reasoning = options.reasoning;
    if (reasoning != null &&
        reasoning != ReasoningEffort.providerDefault &&
        effort == null) {
      final resolved =
          _resolveReasoningConfig(reasoning, capabilities, warnings: warnings);
      thinking ??= resolved.thinking;
      if (resolved.effort != null && thinking is! AnthropicThinkingDisabled) {
        effort = resolved.effort;
      }
    }

    // isThinking 仅指 enabled/adaptive(:422-424);budget 仅 enabled 分支
    // 取值(:425-428),缺省时补 1024 并告警(:603-617);display 仅
    // adaptive 分支取值(:429-432)。
    final isThinking = thinking is AnthropicThinkingEnabled ||
        thinking is AnthropicThinkingAdaptive;
    int? thinkingBudget;
    if (thinking is AnthropicThinkingEnabled) {
      thinkingBudget = thinking.budgetTokens;
      if (thinkingBudget == null) {
        warnings.add(const CompatibilityWarning(
          'thinking',
          details: 'thinking budget is required when thinking is enabled. '
              'using default budget of 1024 tokens.',
        ));
        thinkingBudget = 1024;
      }
    }

    // thinking 生效(enabled/adaptive)时清除三采样参数并各发一条 warning
    // (:619-644);disabled 不清除。
    if (isThinking) {
      if (temperature != null) {
        warnings.add(const UnsupportedWarning(
          'temperature',
          details: 'temperature is not supported when thinking is enabled',
        ));
        temperature = null;
      }
      if (topK != null) {
        warnings.add(const UnsupportedWarning(
          'topK',
          details: 'topK is not supported when thinking is enabled',
        ));
        topK = null;
      }
      if (topP != null) {
        warnings.add(const UnsupportedWarning(
          'topP',
          details: 'topP is not supported when thinking is enabled',
        ));
        topP = null;
      }
    }

    // top_p / temperature 互斥(报告 03 §7.2,:649-660):非 thinking 且
    // isAnthropicModel 且两者同时设置时丢弃 top_p;非 Anthropic 模型
    // (第三方兼容 API)允许同时发送。
    if (!isThinking &&
        isAnthropicModel(modelId) &&
        topP != null &&
        temperature != null) {
      warnings.add(const UnsupportedWarning(
        'topP',
        details: 'topP is not supported when temperature is set. '
            'topP is ignored.',
      ));
      topP = null;
    }

    // 跨 prompt/tools 共享的 cache breakpoint 计数器。上游先转 prompt 再
    // prepareTools(:389/:738);pigcode 因 warnings 单通道(validator 告警
    // 由 convert 入口统一合并,见决策摘要)把 prepareTools 前移,工具级
    // breakpoint 先于 prompt 计数——仅在超过 4 个 breakpoint 的溢出场景
    // 影响"哪个被忽略"的归属,wire 形态不变。
    final cacheControlValidator = CacheControlValidator();

    // tools 段(Task 12/13):toolStreaming 默认 `stream && (?? true)`
    // (上游 :733-734,非流式恒 false),工具级 eagerInputStreaming 在
    // prepare_tools 内覆盖默认。
    // json tool 回退模式改写 prepareTools 调用参数(:738-747):json tool
    // 追加在用户工具之后、toolChoice 强制 required(wire `any`)、
    // disableParallelToolUse 强制 true、supportsStructuredOutput 传 false。
    final toolsResult = prepareAnthropicTools(
      tools: usesJsonResponseTool
          ? <LanguageModelTool>[...?options.tools, jsonResponseTool]
          : options.tools,
      toolChoice: usesJsonResponseTool
          ? const ToolChoiceRequired()
          : options.toolChoice,
      disableParallelToolUse:
          usesJsonResponseTool ? true : anthropicOptions.disableParallelToolUse,
      getCacheControl: (providerOptions) =>
          cacheControlValidator.getCacheControl(
        providerOptions,
        contextType: 'tool definition',
        canCache: true,
      ) as Map<String, Object?>?,
      supportsStructuredOutput:
          usesJsonResponseTool ? false : capabilities.supportsStructuredOutput,
      supportsStrictTools: capabilities.supportsStructuredOutput,
      defaultEagerInputStreaming:
          stream && (anthropicOptions.toolStreaming ?? true),
    );
    warnings.addAll(toolsResult.warnings);

    // prompt 段(Task 6-9):sendReasoning 默认 true(上游 :389-395 取
    // anthropicOptions.sendReasoning ?? true);validator 的 warnings 由
    // convert 入口合并进 result.warnings(单通道)。
    final promptResult = convertToAnthropicMessages(
      prompt: options.prompt,
      sendReasoning: anthropicOptions.sendReasoning ?? true,
      cacheControlValidator: cacheControlValidator,
    );
    warnings.addAll(promptResult.warnings);

    // 推导 beta 合成 Set:prompt 侧 + tools 侧 + providerOptions 显式追加
    // (报告 03 §9 :770-775;用户 headers 自带的 betas 在请求头合成处并入)。
    final betas = <String>{
      ...promptResult.betas,
      ...toolsResult.betas,
      ...?anthropicOptions.anthropicBeta,
    };

    // metadata 仅 userId != null 时发送(报告 03 §7.1 :496-498)。
    final userId = anthropicOptions.metadata?['userId'];

    // max_tokens:缺省用能力表值(未知模型 4096,:434/:441),enabled 的
    // thinking budget 直接相加(adaptive/disabled 无 budget 不加,:646-647);
    // isKnownModel 且超 cap 时裁剪,仅用户显式传 maxOutputTokens 才发
    // warning(details 字面量照上游 :662-675;报告 03 §16 疑点 6:超限
    // 仅来自 budget 相加时静默裁剪)。
    var maxTokens = (options.maxOutputTokens ?? capabilities.maxOutputTokens) +
        (thinkingBudget ?? 0);
    if (capabilities.isKnownModel && maxTokens > capabilities.maxOutputTokens) {
      if (options.maxOutputTokens != null) {
        warnings.add(CompatibilityWarning(
          'maxOutputTokens',
          details: '$maxTokens (maxOutputTokens + thinkingBudget) is greater '
              'than $modelId ${capabilities.maxOutputTokens} max output '
              'tokens. The max output tokens have been limited to '
              '${capabilities.maxOutputTokens}.',
        ));
      }
      maxTokens = capabilities.maxOutputTokens;
    }

    // thinking 请求字段:sendThinking = isThinking || disabled(origin/main
    // :425-428 增量,disabled 必须转发 `{'type':'disabled'}` 否则默认开启
    // thinking 的模型会继续消耗 max_tokens 预算);enabled 才带
    // budget_tokens、adaptive 才带 display(:429-436)。
    final thinkingArg = switch (thinking) {
      AnthropicThinkingEnabled() => <String, Object?>{
          'type': 'enabled',
          'budget_tokens': thinkingBudget,
        },
      AnthropicThinkingAdaptive(:final display) => <String, Object?>{
          'type': 'adaptive',
          if (display != null) 'display': display,
        },
      AnthropicThinkingDisabled() => const <String, Object?>{
          'type': 'disabled',
        },
      null => null,
    };

    // output_config:effort / task_budget / format(原生结构化输出)任一
    // 存在才发(:459-484);task_budget 与 effort、format 并列(D6),
    // type/total 恒发、remaining 仅非空才写键(:468-476)。
    final taskBudget = anthropicOptions.taskBudget;
    final outputConfig = <String, Object?>{
      if (effort != null) 'effort': effort,
      if (taskBudget != null)
        'task_budget': <String, Object?>{
          'type': 'tokens',
          'total': taskBudget.total,
          if (taskBudget.remaining != null) 'remaining': taskBudget.remaining,
        },
      if (outputFormat != null) 'format': outputFormat,
    };

    // mcp_servers(:504-519):snake 化仅 authorization_token /
    // tool_configuration(内 allowed_tools)三处;非空数组才发;显式
    // null 与缺席统一为不写键(微偏离归档,报告 10 §9.5b)。
    final mcpServers = anthropicOptions.mcpServers;
    final mcpServersArg = (mcpServers == null || mcpServers.isEmpty)
        ? null
        : <Object?>[
            for (final server in mcpServers)
              <String, Object?>{
                'type': 'url',
                'name': server.name,
                'url': server.url,
                if (server.authorizationToken != null)
                  'authorization_token': server.authorizationToken,
                if (server.toolConfiguration case final config?)
                  'tool_configuration': <String, Object?>{
                    if (config.allowedTools != null)
                      'allowed_tools': config.allowedTools,
                    if (config.enabled != null) 'enabled': config.enabled,
                  },
              },
          ];

    // container 双形态(:521-543):skills 非空 → 对象形态(custom skill
    // 的 skill_id 经 resolveProviderReference 按 'anthropic' 键解析,缺键
    // 抛 NoSuchProviderReferenceError);否则纯 id 字符串;id 与 skills
    // 均缺席时 containerArg 为 null → removeWhere 剔键(上游 undefined
    // 序列化丢键语义的显式化,spec §5);对象形态 id/version 缺席不写键。
    final container = anthropicOptions.container;
    final containerSkills = container?.skills;
    Object? containerArg;
    if (container != null) {
      if (containerSkills != null && containerSkills.isNotEmpty) {
        containerArg = <String, Object?>{
          if (container.id != null) 'id': container.id,
          'skills': <Object?>[
            for (final skill in containerSkills)
              switch (skill) {
                AnthropicAnthropicSkill(:final skillId, :final version) =>
                  <String, Object?>{
                    'type': 'anthropic',
                    'skill_id': skillId,
                    if (version != null) 'version': version,
                  },
                AnthropicCustomSkill(
                  :final providerReference,
                  :final version,
                ) =>
                  <String, Object?>{
                    'type': 'custom',
                    'skill_id': resolveProviderReference(
                      reference: providerReference,
                      provider: 'anthropic',
                    ),
                    if (version != null) 'version': version,
                  },
              },
          ],
        };
      } else {
        containerArg = container.id;
      }
    }

    // context_management(:549-603):camel→snake 四处(clear_at_least /
    // clear_tool_inputs / exclude_tools / pause_after_compaction);可选键
    // 缺席不写;空 edits 照发(与 mcpServers/fallbacks 的非空检查不同,
    // 报告 10 §9.5a)。未知 edit 型已在 validator 层拒错(上游 default
    // warning 分支为不可达防御代码,不复刻),switch 穷举无 default。
    final contextManagement = anthropicOptions.contextManagement;
    final contextManagementArg = contextManagement == null
        ? null
        : <String, Object?>{
            'edits': <Object?>[
              for (final edit in contextManagement.edits)
                switch (edit) {
                  AnthropicClearToolUses20250919Edit(
                    :final trigger,
                    :final keep,
                    :final clearAtLeast,
                    :final clearToolInputs,
                    :final excludeTools,
                  ) =>
                    <String, Object?>{
                      'type': 'clear_tool_uses_20250919',
                      if (trigger != null) 'trigger': trigger,
                      if (keep != null) 'keep': keep,
                      if (clearAtLeast != null) 'clear_at_least': clearAtLeast,
                      if (clearToolInputs != null)
                        'clear_tool_inputs': clearToolInputs,
                      if (excludeTools != null) 'exclude_tools': excludeTools,
                    },
                  AnthropicClearThinking20251015Edit(:final keep) =>
                    <String, Object?>{
                      'type': 'clear_thinking_20251015',
                      if (keep != null) 'keep': keep,
                    },
                  AnthropicCompact20260112Edit(
                    :final trigger,
                    :final pauseAfterCompaction,
                    :final instructions,
                  ) =>
                    <String, Object?>{
                      'type': 'compact_20260112',
                      if (trigger != null) 'trigger': trigger,
                      if (pauseAfterCompaction != null)
                        'pause_after_compaction': pauseAfterCompaction,
                      if (instructions != null) 'instructions': instructions,
                    },
                },
            ],
          };

    // fallbacks 顶层原样透传,非空数组才发(:493-496)。
    final fallbacks = anthropicOptions.fallbacks;
    final hasFallbacks = fallbacks != null && fallbacks.isNotEmpty;

    // beta 选项族条件 beta ①(:721-731):taskBudget 存在 → task-budgets;
    // 顶层或 fallback speed 为 'fast' → fast-mode('standard' 不加 beta);
    // fallbacks 非空 → server-side-fallback。
    if (taskBudget != null) {
      betas.add('task-budgets-2026-03-13');
    }
    if (anthropicOptions.speed == 'fast' ||
        (fallbacks?.any((fallback) => fallback['speed'] == 'fast') ?? false)) {
      betas.add('fast-mode-2026-02-01');
    }
    if (hasFallbacks) {
      betas.add('server-side-fallback-2026-06-01');
    }

    // beta 选项族条件 beta ②(:681-718):mcpServers 非空 → mcp-client;
    // contextManagement 存在(含空 edits)→ context-management,edits 含
    // compact_20260112 再叠 compact;container.skills 非空 → skills/files
    // 两项 beta,
    // 且 tools 不含 20250825/20260120 版 code_execution(20250522 不在
    // 白名单,:707-711 逐字)时发 skills warning(:713-716)。
    if (mcpServers != null && mcpServers.isNotEmpty) {
      betas.add('mcp-client-2025-04-04');
    }
    if (contextManagement != null) {
      betas.add('context-management-2025-06-27');
      if (contextManagement.edits
          .any((edit) => edit is AnthropicCompact20260112Edit)) {
        betas.add('compact-2026-01-12');
      }
    }
    if (containerSkills != null && containerSkills.isNotEmpty) {
      betas
        ..add('skills-2025-10-02')
        ..add('files-api-2025-04-14');
      final hasCodeExecutionTool = options.tools?.any((tool) =>
              tool is ProviderTool &&
              (tool.id == 'anthropic.code_execution_20250825' ||
                  tool.id == 'anthropic.code_execution_20260120')) ??
          false;
      if (!hasCodeExecutionTool) {
        warnings.add(const OtherWarning(
          'code execution tool is required when using skills',
        ));
      }
    }

    // 字段表照报告 03 §7.1;null 值统一剔除(同 openai `_buildArgs` 模式)。
    final args = <String, Object?>{
      'model': modelId,
      // max_tokens 恒发(加成/裁剪见上)。
      'max_tokens': maxTokens,
      'thinking': thinkingArg,
      'output_config': outputConfig.isEmpty ? null : outputConfig,
      'temperature': temperature,
      'top_k': topK,
      'top_p': topP,
      'stop_sequences': options.stopSequences,
      // speed 顶层键:非空即发('fast'/'standard' 均发,:487-489)。
      'speed': anthropicOptions.speed,
      'inference_geo': anthropicOptions.inferenceGeo,
      'fallbacks': hasFallbacks ? fallbacks : null,
      'mcp_servers': mcpServersArg,
      'container': containerArg,
      'context_management': contextManagementArg,
      'cache_control': anthropicOptions.cacheControl,
      'metadata': userId != null ? <String, Object?>{'user_id': userId} : null,
      'system': promptResult.system,
      'messages': promptResult.messages,
      'tools': toolsResult.tools,
      'tool_choice': toolsResult.toolChoice,
    }..removeWhere((_, value) => value == null);

    return (
      args: args,
      warnings: warnings,
      betas: betas,
      usesJsonResponseTool: usesJsonResponseTool,
      usedCustomProviderKey: resolvedOptions.usedCustomProviderKey,
    );
  }

  /// 组装 `providerMetadata`(报告 03 §13,:1376-1433):`'anthropic'` key
  /// 恒挂;providerOptions 走了自定义 key(usedCustomProviderKey)且派生
  /// key ≠ 'anthropic' 时,同一 metadata 同挂自定义 key(:1428-1430,上游
  /// 为同一引用,pigcode 同引用共享)。
  ProviderMetadata _buildProviderMetadata(
    JsonObject response, {
    required bool usedCustomProviderKey,
  }) {
    final metadata = _buildAnthropicMessageMetadata(response);
    final customKey = config.providerName.split('.').first;
    return {
      'anthropic': metadata,
      if (usedCustomProviderKey && customKey != 'anthropic')
        customKey: metadata,
    };
  }

  /// 顶层 [ReasoningEffort] → thinking/effort 映射(上游
  /// `resolveAnthropicReasoningConfig`,:2698-2744):
  ///
  /// - `none` → `{thinking: disabled}`(:2715-2717;origin/main 增量后
  ///   disabled 也会转发到 wire)。
  /// - adaptive 模型 → `{thinking: adaptive, effort}`,effortMap:
  ///   minimal→low / low→low / medium→medium / high→high /
  ///   xhigh→(supportsXhighEffort ? xhigh : max);映射到不同名时发
  ///   [CompatibilityWarning](provider-utils :49-55)。
  /// - 经典模型 → `{thinking: enabled, budgetTokens}`,budget =
  ///   `clamp(round(cap × pct), 1024, cap)`,pct:minimal 0.02 / low 0.1 /
  ///   medium 0.3 / high 0.6 / xhigh 0.9(provider-utils :60-66, :104-107)。
  ({AnthropicThinking thinking, String? effort}) _resolveReasoningConfig(
    ReasoningEffort reasoning,
    AnthropicModelCapabilities capabilities, {
    required List<Warning> warnings,
  }) {
    if (reasoning == ReasoningEffort.none) {
      return (thinking: const AnthropicThinkingDisabled(), effort: null);
    }
    if (capabilities.supportsAdaptiveThinking) {
      final mapped = switch (reasoning) {
        ReasoningEffort.minimal => 'low',
        ReasoningEffort.low => 'low',
        ReasoningEffort.medium => 'medium',
        ReasoningEffort.high => 'high',
        ReasoningEffort.xhigh =>
          capabilities.supportsXhighEffort ? 'xhigh' : 'max',
        ReasoningEffort.none ||
        ReasoningEffort.providerDefault =>
          throw StateError('unreachable reasoning effort: $reasoning'),
      };
      if (mapped != reasoning.wireValue) {
        warnings.add(CompatibilityWarning(
          'reasoning',
          details: "reasoning effort '${reasoning.wireValue}' is mapped to "
              "'$mapped' for $modelId",
        ));
      }
      return (thinking: const AnthropicThinkingAdaptive(), effort: mapped);
    }
    final pct = switch (reasoning) {
      ReasoningEffort.minimal => 0.02,
      ReasoningEffort.low => 0.1,
      ReasoningEffort.medium => 0.3,
      ReasoningEffort.high => 0.6,
      ReasoningEffort.xhigh => 0.9,
      ReasoningEffort.none ||
      ReasoningEffort.providerDefault =>
        throw StateError('unreachable reasoning effort: $reasoning'),
    };
    final cap = capabilities.maxOutputTokens;
    final budget = (cap * pct).round().clamp(1024, cap).toInt();
    return (
      thinking: AnthropicThinkingEnabled(budgetTokens: budget),
      effort: null,
    );
  }

  /// 合成最终请求头(报告 01 §6):config/options headers 合并后,取其中
  /// `anthropic-beta` 自带值解析(小写、去重)并与推导 [betas] 合并,
  /// 非空时以合成值覆盖重发;空集不发该头。
  Map<String, String> _requestHeaders(
    LanguageModelCallOptions options,
    Set<String> betas,
  ) {
    final headers = combineHeaders([config.headers(), options.headers]);
    final userBetas = <String>{};
    // header 名大小写不敏感匹配(HTTP 语义;combineHeaders 保留原始大小写)。
    headers.removeWhere((name, value) {
      if (name.toLowerCase() == anthropicBetaHeaderName) {
        userBetas.addAll(anthropicBetasFromHeaderValue(value));
        return true;
      }
      return false;
    });
    return {
      ...headers,
      ...anthropicBetaHeader({...betas, ...userBetas}),
    };
  }

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) async {
    final built = _buildArgs(options, stream: false);
    // dynamic 标记(报告 09 §3.1,D7):web 20260209 工具在场且无同名
    // code_execution 工具时,解码出的 code_execution 系 ToolCall 标记为
    // 动态,绕过下游的工具白名单校验。doStream 侧同一 helper(Task 9)。
    final markCodeExecutionDynamic = _hasWebTool20260209WithoutCodeExecution(
      built.args['tools'] as List<JsonObject>?,
    );

    // 响应头在 successHandler 闭包内旁路捕获(同 openai 先例):
    // `postJsonToApi` 保证 successHandler 在返回前已执行完毕,无竞态。
    Map<String, String>? responseHeaders;
    final response = await postJsonToApi<JsonObject>(
      url: _requestUrl,
      headers: _requestHeaders(options, built.betas),
      body: built.args,
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return jsonResponseHandler<JsonObject>(
          decode: (json) => json! as JsonObject,
        )(ctx);
      },
      failureHandler: anthropicFailedResponseHandler(),
      client: config.client,
      cancellation: options.cancellation,
    );

    // 响应 content 块解析(报告 03 §10.2 + 报告 09 §3):text(+citations)/
    // thinking / redacted_thinking / tool_use(json 回退特判)/
    // server_tool_use(白名单,§3.2)/ 五族结果块(web_search_tool_result /
    // web_fetch_tool_result / code_execution_tool_result /
    // bash_code_execution_tool_result / text_editor_code_execution_tool_result
    // / tool_search_tool_result / advisor_tool_result)+ mcp 两块(配对表)
    // / compaction(文本+metadata)/ fallback(显式跳过)(报告 10 §3.1)。
    // 仍在范围外的块类型静默跳过(default 分支)。json 回退模式下
    // (usesJsonResponseTool)text 块整体忽略(:924-944),name 为 'json'
    // 的 tool_use 转 text(input 重新 jsonEncode,:985-992)且置响应侧
    // 标记 isJsonResponseFromTool。
    final content = <LanguageModelContent>[];
    var isJsonResponseFromTool = false;
    // citationDocuments 需在循环内可变追加(web_fetch 成功结果按出现序补入,
    // 报告 07 §4.2 :233),故用可变局部变量持有 `_extractCitationDocuments`
    // 的初始结果。
    var citationDocuments = _extractCitationDocuments(options.prompt);
    // tool_use_id → 白名单 server_tool_use wire 名(报告 09 §3.1 :922)。
    // 本响应内登记全部白名单调用,供 tool_search_tool_result 的定名
    // fallback 查询(§3.5,Task 8)。
    final serverToolCalls = <String, String>{};
    // 本响应内 mcp_tool_use 配对表(:921):mcp_tool_result 的 toolName 与
    // providerMetadata 从同响应配对调用直索引取得(:1118-1129)。
    final mcpToolCalls = <String, ToolCall>{};
    for (final raw in response['content']! as List<Object?>) {
      final block = raw! as JsonObject;
      switch (block['type']) {
        case 'text':
          if (built.usesJsonResponseTool) {
            continue;
          }
          content.add(TextContent(block['text']! as String));
          // citations 逐条映射为 source,紧随所属 text 块之后追加
          // (报告 03 §10.3 :70-127)。
          final citations = block['citations'];
          if (citations is List<Object?>) {
            for (final citation in citations) {
              final source = _createCitationSource(
                citation! as JsonObject,
                citationDocuments,
              );
              if (source != null) {
                content.add(source);
              }
            }
          }
        case 'thinking':
          content.add(ReasoningContent(
            block['thinking']! as String,
            providerMetadata: {
              'anthropic': {'signature': block['signature']! as String},
            },
          ));
        case 'redacted_thinking':
          content.add(ReasoningContent(
            '',
            providerMetadata: {
              'anthropic': {'redactedData': block['data']! as String},
            },
          ));
        case 'tool_use':
          if (built.usesJsonResponseTool && block['name'] == 'json') {
            isJsonResponseFromTool = true;
            content.add(TextContent(jsonEncode(block['input'])));
          } else {
            // caller 仅 wire 存在时携带(tool_id → toolId,:993-1014)。
            final caller = block['caller'];
            content.add(ToolCall(
              toolCallId: block['id']! as String,
              toolName: block['name']! as String,
              input: jsonEncode(block['input']),
              providerMetadata: caller is JsonObject
                  ? {
                      'anthropic': {
                        'caller': <String, Object?>{
                          'type': caller['type'],
                          if (caller['tool_id'] != null)
                            'toolId': caller['tool_id'],
                        },
                      },
                    }
                  : null,
            ));
          }
        case 'server_tool_use':
          // 白名单扩容(报告 09 §3.2):web 两名(批次 1)+ code_execution 族
          // (含两子工具)/tool_search 两名/advisor(本批)。未知 name 静默
          // 丢弃(无兜底 else,:1096-1098)。caller 照上游忽略(:207)。
          final serverToolName = block['name'] as String?;
          if (serverToolName == null ||
              !_serverToolUseNames.contains(serverToolName)) {
            continue;
          }
          final serverToolCallId = block['id']! as String;
          serverToolCalls[serverToolCallId] = serverToolName;
          if (serverToolName == 'bash_code_execution' ||
              serverToolName == 'text_editor_code_execution') {
            // 子工具名归一 'code_execution' + type 键注入在最前
            // (:1025-1046)。dynamic 条件在此分支恒真(providerToolName 恒为
            // 'code_execution',报告 09 §9.5/spec 疑点 11,照抄)。
            content.add(ToolCall(
              toolCallId: serverToolCallId,
              toolName: 'code_execution',
              input: jsonEncode(<String, Object?>{
                'type': serverToolName,
                ...?(block['input'] as JsonObject?),
              }),
              providerExecuted: true,
              isDynamic: markCodeExecutionDynamic ? true : null,
            ));
          } else if (serverToolName == 'tool_search_tool_regex' ||
              serverToolName == 'tool_search_tool_bm25') {
            // tool_search 两名:input 原样序列化,无 dynamic(:1076-1087)。
            content.add(ToolCall(
              toolCallId: serverToolCallId,
              toolName: serverToolName,
              input: jsonEncode(block['input']),
              providerExecuted: true,
            ));
          } else if (serverToolName == 'advisor') {
            // advisor:input 原样序列化(wire 恒 {},非硬置,:1088-1095)。
            content.add(ToolCall(
              toolCallId: serverToolCallId,
              toolName: 'advisor',
              input: jsonEncode(block['input']),
              providerExecuted: true,
            ));
          } else {
            // web_search / web_fetch / code_execution(20250522 无 type 或
            // programmatic-tool-call 注入,:1047-1075)。
            final rawInput = block['input'];
            final inputToSerialize = serverToolName == 'code_execution' &&
                    rawInput is JsonObject &&
                    rawInput.containsKey('code') &&
                    !rawInput.containsKey('type')
                ? <String, Object?>{
                    'type': 'programmatic-tool-call',
                    ...rawInput,
                  }
                : rawInput;
            content.add(ToolCall(
              toolCallId: serverToolCallId,
              toolName: serverToolName,
              input: jsonEncode(inputToSerialize),
              providerExecuted: true,
              isDynamic: (serverToolName == 'code_execution' &&
                      markCodeExecutionDynamic)
                  ? true
                  : null,
            ));
          }
        case 'web_search_tool_result':
          content.addAll(_parseWebSearchToolResult(block));
        case 'web_fetch_tool_result':
          // 成功分支先追加 citationDocuments 再产出 ToolResult(顺序敏感,
          // 报告 07 §4.2 :233;供后续 text 块 citation 按 document_index
          // 查到本条 fetched 文档)。
          final (result, updatedDocuments) =
              _parseWebFetchToolResult(block, citationDocuments);
          content.add(result);
          citationDocuments = updatedDocuments;
        case 'code_execution_tool_result':
          content.add(_parseCodeExecutionToolResult(block));
        case 'bash_code_execution_tool_result':
        case 'text_editor_code_execution_tool_result':
          content.add(_parseBashOrTextEditorCodeExecutionToolResult(block));
        case 'tool_search_tool_result':
          content.add(_parseToolSearchToolResult(block, serverToolCalls));
        case 'advisor_tool_result':
          content.add(_parseAdvisorToolResult(block));
        case 'mcp_tool_use':
          // MCP 工具调用(:1100-1117):toolName 直接用 MCP 工具名(不经
          // 白名单/归一),dynamic 通道;先登记配对表再 push 同一实例。
          // metadata 判别值是连字符 'mcp-tool-use'(与 wire 块名下划线不同)。
          final mcpToolCall = ToolCall(
            toolCallId: block['id']! as String,
            toolName: block['name']! as String,
            input: jsonEncode(block['input']),
            providerExecuted: true,
            isDynamic: true,
            providerMetadata: {
              'anthropic': {
                'type': 'mcp-tool-use',
                'serverName': block['server_name']! as String,
              },
            },
          );
          mcpToolCalls[mcpToolCall.toolCallId] = mcpToolCall;
          content.add(mcpToolCall);
        case 'mcp_tool_result':
          // MCP 工具结果(:1118-1129):同响应配对表直索引。上游无配对时是
          // 裸 crash 路径(undefined 直索引成员);pigcode 已拍板受控错误
          // (报告 10 §9.1 方案 b):非流式抛 FormatException,文案为跨任务
          // 契约,逐字锁定。
          final toolUseId = block['tool_use_id']! as String;
          final mcpCall = mcpToolCalls[toolUseId];
          if (mcpCall == null) {
            throw FormatException(
              'mcp_tool_result block without matching mcp_tool_use: '
              '$toolUseId',
            );
          }
          content.add(ToolResult(
            toolCallId: toolUseId,
            toolName: mcpCall.toolName,
            result: block['content'],
            isError: block['is_error']! as bool,
            isDynamic: true,
            providerMetadata: mcpCall.providerMetadata,
          ));
        case 'compaction':
          // compaction 块(:973-984):文本 + compaction metadata;非流式
          // schema 的 content 必填 string,可信直取(报告 10 §9.5g)。
          content.add(TextContent(
            block['content']! as String,
            providerMetadata: const {
              'anthropic': {'type': 'compaction'},
            },
          ));
        case 'fallback':
          // 服务端 fallback 标记块(:1353-1358):AI SDK 无模型跳转内容
          // 原语,跳过不产出;跳转仍可经 usage.iterations 观察。
          continue;
        default:
          continue;
      }
    }

    return LanguageModelGenerateResult(
      content: content,
      finishReason: mapAnthropicStopReason(
        response['stop_reason'] as String?,
        isJsonResponseFromTool: isJsonResponseFromTool,
      ),
      usage: convertAnthropicUsage(response['usage']! as JsonObject),
      providerMetadata: _buildProviderMetadata(
        response,
        usedCustomProviderKey: built.usedCustomProviderKey,
      ),
      warnings: built.warnings,
      request: RequestInfo(body: built.args),
      response: ResponseInfo(
        id: response['id'] as String?,
        modelId: response['model'] as String?,
        headers: responseHeaders,
        body: response,
      ),
    );
  }

  @override
  Future<LanguageModelStreamResult> doStream(
    LanguageModelCallOptions options,
  ) async {
    final built = _buildArgs(options, stream: true);
    // `stream` 字段仅流式请求发送(报告 04 §1 :767,非流式不发)。
    final streamArgs = <String, Object?>{...built.args, 'stream': true};

    // 响应头在 successHandler 闭包内旁路捕获(同 doGenerate/openai 先例)。
    Map<String, String>? responseHeaders;
    final events = await postJsonStreamToApi<JsonValue>(
      url: _requestUrl,
      headers: _requestHeaders(options, built.betas),
      body: streamArgs,
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return eventSourceResponseHandler<JsonValue>(
          decode: (json) => json,
        )(ctx);
      },
      failureHandler: anthropicFailedResponseHandler(),
      client: config.client,
      cancellation: options.cancellation,
    );

    // 首 chunk 预读(报告 04 §8.1 :2529-2562):Anthropic 在 overloaded 时
    // 也会返回 200 + `error` 事件;首个实义事件是 `error` 帧则在 Future 层
    // 抛 ApiCallError(529/500 + 显式 isRetryable),ping 在探测窗口内跳过。
    final checkedEvents = await throwIfStreamErrorBeforeOutput(
      events,
      url: _requestUrl,
      requestBody: streamArgs,
      getError: (value) => value is JsonObject && value['type'] == 'error'
          ? value['error']
          : null,
      // message_start 即产出 part,error 不在首个非 ping 事件位置就属流
      // 中段(走流内 ErrorPart);非 Map 帧交由下游按"意外形状"报错。
      isOutputChunk: (value) =>
          value is! JsonObject ||
          (value['type'] != 'ping' && value['type'] != 'error'),
    );

    return LanguageModelStreamResult(
      stream: _toStreamParts(
        checkedEvents,
        warnings: built.warnings,
        usesJsonResponseTool: built.usesJsonResponseTool,
        usedCustomProviderKey: built.usedCustomProviderKey,
        includeRawChunks: options.includeRawChunks ?? false,
        // citation 文档收集与 doGenerate 共用(报告 04 §6 :1456-1459;
        // web_fetch 流中追加路径不在首版)。
        citationDocuments: _extractCitationDocuments(options.prompt),
        // dynamic 标记(报告 09 §3.1,D7),与 doGenerate 侧同一 helper。
        markCodeExecutionDynamic: _hasWebTool20260209WithoutCodeExecution(
          built.args['tools'] as List<JsonObject>?,
        ),
      ),
      request: RequestInfo(body: streamArgs),
      response: ResponseInfo(headers: responseHeaders),
    );
  }

  /// SSE 事件流 → 契约 stream part 流的拼装状态机(报告 04 §3/§5 + 报告 09
  /// §4)。
  ///
  /// 顶层按 data JSON 的 `type` 判别 8 种事件(报告 04 §2)。`server_tool_use`
  /// 白名单(web 两名 + code_execution 族 + tool_search 两名 + advisor,报告
  /// 09 §4.1)与对应的五族结果块(`web_search_tool_result` /
  /// `web_fetch_tool_result` / `code_execution_tool_result` /
  /// `bash_code_execution_tool_result` / `text_editor_code_execution_tool_result`
  /// / `tool_search_tool_result` / `advisor_tool_result`)均已接入。三族新块
  /// 亦已接入(报告 10 §3.3):`mcp_tool_use`/`mcp_tool_result`(start 即
  /// 全部)、`compaction`(+`compaction_delta`,并入 text 事件流)、
  /// `fallback`(前置拦截跳过)。仍在范围外:`message_start.content` 程序化
  /// 预填充(随后续独立增量补齐);其余未知块/未知 delta 仍走"解析失败 →
  /// 流内 ErrorPart"路径(报告 04 §8.3 同构)。error-as-terminal:yield
  /// [ErrorPart] 后立即 return(pigcode 契约既定,偏离上游"不 close")。
  Stream<LanguageModelStreamPart> _toStreamParts(
    Stream<ParseResult<JsonValue>> events, {
    required List<Warning> warnings,
    required bool usesJsonResponseTool,
    required bool usedCustomProviderKey,
    required bool includeRawChunks,
    required List<_CitationDocument> citationDocuments,
    required bool markCodeExecutionDynamic,
  }) async* {
    yield StreamStart(warnings);

    // 状态机初值照报告 04 §3 表。
    var finishReason = const LanguageModelFinishReason(FinishReasonType.other);
    final usage = <String, Object?>{
      'input_tokens': 0,
      'output_tokens': 0,
      'cache_creation_input_tokens': 0,
      'cache_read_input_tokens': 0,
      'iterations': null,
    };
    JsonObject? rawUsage;
    // 以下四项 metadata 状态存的是已映射(camelCase)形态,message_stop
    // 组装时原样落键(报告 04 §3/§5.11)。
    Object? stopSequence;
    JsonObject? stopDetails;
    JsonObject? container;
    JsonObject? contextManagement;
    final contentBlocks = <int, _ContentBlockState>{};
    // tool_use_id → 白名单 server_tool_use wire 名(报告 09 §4.1,与
    // doGenerate 的 serverToolCalls 同构),供 Task 10 的
    // tool_search_tool_result 定名 fallback 查询使用。
    final serverToolCalls = <String, String>{};
    // 本响应(整个 SSE 流)内 mcp_tool_use 配对表(:1514):同一响应内
    // 跨块可见、跨请求不可见;mcp_tool_result 从此表直索引 toolName 与
    // providerMetadata(:2071-2083)。
    final mcpToolCalls = <String, ToolCall>{};
    // 单一标量,记录"当前打开块"的原始 wire 类型:content_block_start 赋值、
    // content_block_stop 置 null(:1522-1538,2176);目前仅 signature_delta
    // 分支用它判断 `== 'thinking'`(:2213;疑点 #2 不在 spec 偏离表,照上游
    // 单一标量而非按 index)。
    String? blockType;
    // json 响应工具(name 为 'json')的 tool_use start 出现后置 true
    // (:1520),finishReason 映射据此把 tool_use 折算为 stop。
    var isJsonResponseFromTool = false;

    try {
      await for (final event in events) {
        if (includeRawChunks) {
          // includeRawChunks 开启时逐帧前置透传原始负载(:1552-1554,照
          // openai `chat_language_model.dart:513-519`):ParseSuccess/
          // ParseFailure 均发,置于错误短路判定之前。
          yield RawPart(
            event is ParseSuccess<JsonValue>
                ? event.rawValue
                : (event as ParseFailure<JsonValue>).rawValue,
          );
        }

        if (event is ParseFailure<JsonValue>) {
          // 帧级解析失败:ErrorPart 即终态,立即终止流(openai 先例)。
          yield ErrorPart(event.error);
          return;
        }

        final value = (event as ParseSuccess<JsonValue>).value;
        if (value is! JsonObject) {
          yield ErrorPart(FormatException('Unexpected chunk shape: $value'));
          return;
        }

        switch (value['type']) {
          case 'ping':
            // ping 直接忽略(:1564-1566)。
            continue;

          case 'message_start':
            final message = value['message']! as JsonObject;
            final messageUsage = message['usage']! as JsonObject;
            // input_tokens 必填;cache 两项 ?? 0(:2313-2317)。
            usage['input_tokens'] =
                (messageUsage['input_tokens']! as num).toInt();
            usage['cache_creation_input_tokens'] =
                (messageUsage['cache_creation_input_tokens'] as num?)
                        ?.toInt() ??
                    0;
            usage['cache_read_input_tokens'] =
                (messageUsage['cache_read_input_tokens'] as num?)?.toInt() ?? 0;
            // looseObject 语义:未知 usage 字段全量浅拷贝保留(:2319-2321)。
            rawUsage = <String, Object?>{...messageUsage};
            // container 非 null 才记录;skills 在 message_start 恒为 null
            // (:2323-2329)。
            final startContainer = message['container'];
            if (startContainer is JsonObject) {
              container = <String, Object?>{
                'expiresAt': startContainer['expires_at'],
                'id': startContainer['id'],
                'skills': null,
              };
            }
            // stop_reason 非 null 时提前设置 finishReason(:2331-2339)。
            final startStopReason = message['stop_reason'] as String?;
            if (startStopReason != null) {
              finishReason = mapAnthropicStopReason(
                startStopReason,
                isJsonResponseFromTool: isJsonResponseFromTool,
              );
            }
            yield ResponseMetadata(
              id: message['id'] as String?,
              modelId: message['model'] as String?,
            );

          case 'content_block_start':
            final index = (value['index']! as num).toInt();
            final contentBlock = value['content_block']! as JsonObject;
            // 服务端 fallback 标记块前置拦截(:1572-1583):在 blockType 赋值
            // 之前短路——不设 blockType、不注册块状态、不产出事件;其后续
            // content_block_stop 因块未注册仅复位 blockType,同样无事件。
            // (AI SDK 无模型跳转内容原语,跳转仍可经 usage.iterations 观察。)
            if (contentBlock['type'] == 'fallback') {
              continue;
            }
            // blockType 随每个 start 赋原始类型(fallback 已前置拦截)。
            blockType = contentBlock['type'] as String?;
            switch (contentBlock['type']) {
              case 'text':
                // json 回退模式下普通 text 块整块忽略:不注册不产出,后续
                // text_delta/stop 均静默丢弃(:1585-1587)。
                if (usesJsonResponseTool) {
                  break;
                }
                // text 块 id = String(块索引)(报告 04 §3 :133)。
                contentBlocks[index] = _ContentBlockState.text;
                yield TextStart('$index');
              case 'thinking':
                contentBlocks[index] = _ContentBlockState.reasoning;
                yield ReasoningStart('$index');
              case 'redacted_thinking':
                // redacted 数据只进 metadata,推理文本恒为空(:1606-1617)。
                contentBlocks[index] = _ContentBlockState.reasoning;
                yield ReasoningStart('$index', providerMetadata: {
                  'anthropic': {
                    'redactedData': contentBlock['data']! as String
                  },
                });
              case 'tool_use':
                // json 响应工具:置标志并把该块注册为 text 块(id 用
                // String(index)),工具输入以文本流形式输出(:1635-1646)。
                if (usesJsonResponseTool && contentBlock['name'] == 'json') {
                  isJsonResponseFromTool = true;
                  contentBlocks[index] = _ContentBlockState.text;
                  yield TextStart('$index');
                  break;
                }
                // tool 块 part id 用工具 id 而非块索引(报告 04 §3 :133、
                // :1676-1680);initialInput = input 非空对象时 JSON 序列化,
                // 否则空串(:1661-1665)。caller 提取/firstDelta 首字符改写/
                // providerExecuted/dynamic 随 provider tools PR 补齐。
                final toolCallId = contentBlock['id']! as String;
                final toolName = contentBlock['name']! as String;
                final input = contentBlock['input'];
                contentBlocks[index] = _ToolCallBlockState(
                  toolCallId: toolCallId,
                  toolName: toolName,
                  input: input is JsonObject && input.isNotEmpty
                      ? jsonEncode(input)
                      : '',
                );
                yield ToolInputStart(id: toolCallId, toolName: toolName);
              case 'server_tool_use':
                // 白名单扩容(报告 09 §4.1):web 两名(批次 1)+
                // code_execution 族(含两子工具)/tool_search 两名/advisor
                // (本批)。未知 name 不注册不 yield(:1807-1809)。caller 照
                // 上游忽略(§5.1 :270)。
                final blockName = contentBlock['name'] as String?;
                if (blockName == null ||
                    !_serverToolUseNames.contains(blockName)) {
                  break;
                }
                final serverToolCallId = contentBlock['id']! as String;
                serverToolCalls[serverToolCallId] = blockName;
                if (blockName == 'tool_search_tool_regex' ||
                    blockName == 'tool_search_tool_bm25') {
                  // tool_search 两名:input 全靠 delta 累积起步空串,无
                  // providerToolInputType(:1762-1786)。
                  contentBlocks[index] = _ToolCallBlockState(
                    toolCallId: serverToolCallId,
                    toolName: blockName,
                    input: '',
                    providerExecuted: true,
                  );
                  yield ToolInputStart(
                    id: serverToolCallId,
                    toolName: blockName,
                    providerExecuted: true,
                  );
                } else if (blockName == 'advisor') {
                  // advisor:预置 input '{}'(模型不发 input deltas,
                  // :1787-1807)。
                  contentBlocks[index] = _ToolCallBlockState(
                    toolCallId: serverToolCallId,
                    toolName: 'advisor',
                    input: '{}',
                    providerExecuted: true,
                  );
                  yield ToolInputStart(
                    id: serverToolCallId,
                    toolName: 'advisor',
                    providerExecuted: true,
                  );
                } else {
                  // 五名单里剩余三名(web_fetch/web_search/code_execution)
                  // + 两个子工具名(text_editor_code_execution/
                  // bash_code_execution)统一处理(报告 09 §4.1a)。
                  final String providerToolName;
                  final String? providerToolInputType;
                  if (blockName == 'text_editor_code_execution' ||
                      blockName == 'bash_code_execution') {
                    providerToolName = 'code_execution';
                    providerToolInputType = blockName;
                  } else if (blockName == 'code_execution') {
                    providerToolName = 'code_execution';
                    providerToolInputType = 'programmatic-tool-call';
                  } else {
                    providerToolName = blockName;
                    providerToolInputType = null;
                  }
                  final serverInput = contentBlock['input'];
                  final finalInput =
                      serverInput is JsonObject && serverInput.isNotEmpty
                          ? jsonEncode(serverInput)
                          : '';
                  final isDynamicTool = markCodeExecutionDynamic &&
                      providerToolName == 'code_execution';
                  contentBlocks[index] = _ToolCallBlockState(
                    toolCallId: serverToolCallId,
                    toolName: providerToolName,
                    input: finalInput,
                    providerExecuted: true,
                    providerToolInputType: providerToolInputType,
                  );
                  yield ToolInputStart(
                    id: serverToolCallId,
                    toolName: providerToolName,
                    providerExecuted: true,
                    isDynamic: isDynamicTool ? true : null,
                  );
                }
              case 'web_search_tool_result':
                // 映射与 doGenerate 共用(_parseWebSearchToolResult,报告 07
                // §4.3);载荷在 start 事件一次到齐(§5.4),不注册块状态,
                // 故对应 content_block_stop 不再产出任何 part(:311)。
                // ToolResult/SourceContent 同时实现 LanguageModelContent 与
                // LanguageModelStreamPart,共用 helper 返回值需按后者 yield。
                for (final part in _parseWebSearchToolResult(contentBlock)) {
                  yield part as LanguageModelStreamPart;
                }
              case 'web_fetch_tool_result':
                // 成功先 push citationDocuments 再产出 ToolResult(顺序敏感,
                // §5.4 :1814-1817 + §5.5 :315),供后续 text 块 citation
                // 命中(_parseWebFetchToolResult 与 doGenerate 共用)。
                final (result, updatedDocuments) = _parseWebFetchToolResult(
                  contentBlock,
                  citationDocuments,
                );
                citationDocuments = updatedDocuments;
                yield result;
              case 'code_execution_tool_result':
                yield _parseCodeExecutionToolResult(contentBlock);
              case 'bash_code_execution_tool_result':
              case 'text_editor_code_execution_tool_result':
                yield _parseBashOrTextEditorCodeExecutionToolResult(
                  contentBlock,
                );
              case 'tool_search_tool_result':
                yield _parseToolSearchToolResult(
                  contentBlock,
                  serverToolCalls,
                );
              case 'advisor_tool_result':
                yield _parseAdvisorToolResult(contentBlock);
              case 'compaction':
                // compaction 并入普通 text 事件流(:1624-1636):注册
                // _TextBlockState,metadata 只挂 TextStart;start 事件自身的
                // content 字段忽略不读(流式 schema nullish,文本全靠
                // compaction_delta 到达);stop 走既有 text 分支自然产
                // TextEnd(报告 10 §9.3,核心缓冲保留 start 的 metadata)。
                contentBlocks[index] = _ContentBlockState.text;
                yield TextStart('$index', providerMetadata: const {
                  'anthropic': {'type': 'compaction'},
                });
              case 'mcp_tool_use':
                // start 即全部(:2052-2069):input 在 content_block_start
                // 一次到齐,直接产出完整契约 ToolCall;不注册块状态、不走
                // _ToolCallBlockState/ToolInput* 三段式(报告 10 §9.5d,与
                // server_tool_use 不同);同时登记配对表。
                final mcpToolCall = ToolCall(
                  toolCallId: contentBlock['id']! as String,
                  toolName: contentBlock['name']! as String,
                  input: jsonEncode(contentBlock['input']),
                  providerExecuted: true,
                  isDynamic: true,
                  providerMetadata: {
                    'anthropic': {
                      'type': 'mcp-tool-use',
                      'serverName': contentBlock['server_name']! as String,
                    },
                  },
                );
                mcpToolCalls[mcpToolCall.toolCallId] = mcpToolCall;
                yield mcpToolCall;
              case 'mcp_tool_result':
                // start 即全部(:2071-2083):配对表直索引,不注册块状态,
                // stop 无事件。上游无配对为裸 crash 路径;pigcode 已拍板受控
                // 错误(报告 10 §9.1 方案 b):ErrorPart 终态(error-as-
                // terminal,与既有未知块路径同构,文案为跨任务契约)。
                final toolUseId = contentBlock['tool_use_id']! as String;
                final mcpCall = mcpToolCalls[toolUseId];
                if (mcpCall == null) {
                  yield ErrorPart(FormatException(
                    'mcp_tool_result block without matching mcp_tool_use: '
                    '$toolUseId',
                  ));
                  return;
                }
                yield ToolResult(
                  toolCallId: toolUseId,
                  toolName: mcpCall.toolName,
                  result: contentBlock['content'],
                  isError: contentBlock['is_error']! as bool,
                  isDynamic: true,
                  providerMetadata: mcpCall.providerMetadata,
                );
              default:
                // 仍在范围外的块类型:同上游 schema 解析失败路径(报告 04
                // §8.3)。
                yield ErrorPart(FormatException(
                  'Unsupported content block type: '
                  '${contentBlock['type']}',
                ));
                return;
            }

          case 'content_block_delta':
            final index = (value['index']! as num).toInt();
            final delta = value['delta']! as JsonObject;
            switch (delta['type']) {
              case 'text_delta':
                // json 回退模式下普通 text 块的增量忽略(:2188-2190)。
                if (usesJsonResponseTool) {
                  break;
                }
                yield TextDelta('$index', delta['text']! as String);
              case 'thinking_delta':
                yield ReasoningDelta('$index', delta['thinking']! as String);
              case 'signature_delta':
                // 仅当前块为 thinking 时生效,否则丢弃;签名不进 delta 文本,
                // 只进 metadata(:2211-2227)。
                if (blockType == 'thinking') {
                  yield ReasoningDelta('$index', '', providerMetadata: {
                    'anthropic': {'signature': delta['signature']! as String},
                  });
                }
              case 'input_json_delta':
                // 空串 delta 跳过(:2245-2249)。
                final partial = delta['partial_json']! as String;
                final block = contentBlocks[index];
                if (partial.isEmpty) {
                  break;
                }
                if (isJsonResponseFromTool) {
                  // json 回退模式:块须已注册为 text(否则丢弃,上游注释
                  // "exclude reasoning"),以 TextDelta 输出且不累积 input
                  // (:2251-2260)。
                  if (block is _TextBlockState) {
                    yield TextDelta('$index', partial);
                  }
                } else if (block is _ToolCallBlockState) {
                  // 块非 tool-call 注册则丢弃(:2266)。
                  //
                  // 首个非空 delta 且该块有 providerToolInputType → 首字符
                  // `{` 替换为 `{"type": "<inputType>",`(冒号后一个空格,
                  // 与 doGenerate 侧 jsonEncode 无空格是两种字节形态,报告
                  // 09 §9.3;无守卫照抄——delta.substring(1) 假定首字符是
                  // `{`,D5①)。
                  //
                  // 「首个非空 delta」判定用 `block.input.isEmpty`(追加
                  // 当前 delta 之前判断):此字段非 null 的三种场景(两个子
                  // 工具、直接 code_execution)注册时 input 恒起步空串
                  // (:1719-1721 注释:code_execution 系工具通过 delta 提供
                  // input,不经 content_block_start 的 input 字段),故与
                  // 上游显式 `firstDelta` 字段语义等价;providerToolInputType
                  // 为 null 的场景(web/tool_search/advisor)本就不会进入
                  // 这段注入逻辑,`isEmpty` 判断结果如何都不影响输出。
                  var effectivePartial = partial;
                  if (block.input.isEmpty &&
                      block.providerToolInputType != null) {
                    effectivePartial = '{"type": '
                        '"${block.providerToolInputType}",'
                        '${partial.substring(1)}';
                  }
                  yield ToolInputDelta(block.toolCallId, effectivePartial);
                  block.input += effectivePartial;
                }
              case 'citations_delta':
                // citation → source part,查不到文档则丢弃不 yield
                // (:2288-2301)。
                final source = _createCitationSource(
                  delta['citation']! as JsonObject,
                  citationDocuments,
                );
                if (source != null) {
                  yield source;
                }
              case 'compaction_delta':
                // compaction 增量 → 普通 TextDelta(:2233-2243):载荷字段
                // 是 content(非 text_delta 的 text);null/缺席时静默无事件
                // (报告 10 §9.5g);照上游不检查块注册状态(与
                // input_json_delta 的守卫刻意不同)。
                final compactionContent = delta['content'];
                if (compactionContent is String) {
                  yield TextDelta('$index', compactionContent);
                }
              default:
                // 仍在范围外的 delta 类型:同解析失败路径(报告 04 §8.3)。
                yield ErrorPart(FormatException(
                  'Unsupported delta type: ${delta['type']}',
                ));
                return;
            }

          case 'content_block_stop':
            final index = (value['index']! as num).toInt();
            switch (contentBlocks[index]) {
              case _TextBlockState():
                yield TextEnd('$index');
              case _ReasoningBlockState():
                yield ReasoningEnd('$index');
              case final _ToolCallBlockState block:
                // ToolInputEnd 后紧跟完整 ToolCall;finalInput 空串换 '{}'
                // (:2126-2127、:2147-2168、:2275-2282)。普通块 providerExecuted
                // 恒为 null(不改既有断言),server_tool_use 块为 true。
                yield ToolInputEnd(block.toolCallId);
                // code_execution 族(含两子工具,toolName 已归一)在 stop
                // 时兜底注入 programmatic-tool-call type:累积 input 若能
                // 解析出 {code, 无 type} 则补注(报告 09 §4.3
                // :2128-2149)。子工具块的 input 已在首 delta 注入过自身
                // type,此处 parsed 含 type 键、条件不成立,不会二次注入;
                // 该分支覆盖 input 经 content_block_start 整体到达(无
                // delta,firstDelta 语义上不成立)的场景。本类无自定义
                // provider 名映射层(D3),`block.toolName` 本身即归一后的
                // provider 名,故直接比较 `block.toolName` 而不需要额外
                // 的 providerToolName 字段。
                var finalInput = block.input.isEmpty ? '{}' : block.input;
                if (block.toolName == 'code_execution') {
                  try {
                    final parsed = jsonDecode(finalInput);
                    if (parsed is JsonObject &&
                        parsed.containsKey('code') &&
                        !parsed.containsKey('type')) {
                      finalInput = jsonEncode(<String, Object?>{
                        'type': 'programmatic-tool-call',
                        ...parsed,
                      });
                    }
                  } on FormatException {
                    // 解析失败:保留原 finalInput,忽略(:2146-2148)。
                  }
                }
                yield ToolCall(
                  toolCallId: block.toolCallId,
                  toolName: block.toolName,
                  input: finalInput,
                  providerExecuted: block.providerExecuted ? true : null,
                  isDynamic: (markCodeExecutionDynamic &&
                          block.toolName == 'code_execution')
                      ? true
                      : null,
                );
              case null:
                break;
            }
            contentBlocks.remove(index);
            // 无论块是否注册,blockType 置 null(:2176)。
            blockType = null;

          case 'message_delta':
            // 状态更新全表照报告 04 §5.10;不产出任何 part(:2529 前无
            // enqueue)。
            final delta = value['delta']! as JsonObject;
            final deltaUsage = value['usage']! as JsonObject;
            // input_tokens 仅非 null 且与当前不同才覆盖(:2405-2410)。
            final deltaInput = (deltaUsage['input_tokens'] as num?)?.toInt();
            if (deltaInput != null && deltaInput != usage['input_tokens']) {
              usage['input_tokens'] = deltaInput;
            }
            // output_tokens 无条件取值(:2411)。
            usage['output_tokens'] =
                (deltaUsage['output_tokens']! as num).toInt();
            // cache 两项非 null 才覆盖(:2413-2420)。
            final deltaCacheRead =
                (deltaUsage['cache_read_input_tokens'] as num?)?.toInt();
            if (deltaCacheRead != null) {
              usage['cache_read_input_tokens'] = deltaCacheRead;
            }
            final deltaCacheWrite =
                (deltaUsage['cache_creation_input_tokens'] as num?)?.toInt();
            if (deltaCacheWrite != null) {
              usage['cache_creation_input_tokens'] = deltaCacheWrite;
            }
            // iterations 非 null 才覆盖(:2421-2423)。
            if (deltaUsage['iterations'] != null) {
              usage['iterations'] = deltaUsage['iterations'];
            }
            // 【spec 裁决 #3,偏离上游】stop_reason 非 null 才重建
            // finishReason(上游无条件重建会把已设值覆盖回 other,
            // :2425-2431)。
            final stopReason = delta['stop_reason'] as String?;
            if (stopReason != null) {
              finishReason = mapAnthropicStopReason(
                stopReason,
                isJsonResponseFromTool: isJsonResponseFromTool,
              );
            }
            // stop_sequence 无条件 `?? null`(:2433)。
            stopSequence = delta['stop_sequence'];
            // stop_details:null → 清空;否则 camelCase 映射,空字段不落键
            // (:2434,2781-2797)。
            final deltaStopDetails = delta['stop_details'];
            stopDetails = deltaStopDetails is JsonObject
                ? <String, Object?>{
                    'type': deltaStopDetails['type'],
                    if (deltaStopDetails['category'] != null)
                      'category': deltaStopDetails['category'],
                    if (deltaStopDetails['explanation'] != null)
                      'explanation': deltaStopDetails['explanation'],
                    if (deltaStopDetails['recommended_model'] != null)
                      'recommendedModel': deltaStopDetails['recommended_model'],
                  }
                : null;
            // 【spec 裁决 #4,偏离上游】container 非 null 才覆盖(上游 null
            // 会把 message_start 设的值置回 null,:2435-2447);skills 映射
            // skill_id → skillId。
            final deltaContainer = delta['container'];
            if (deltaContainer is JsonObject) {
              container = <String, Object?>{
                'expiresAt': deltaContainer['expires_at'],
                'id': deltaContainer['id'],
                'skills': deltaContainer['skills'] is List<Object?>
                    ? [
                        for (final raw
                            in deltaContainer['skills']! as List<Object?>)
                          _convertContainerSkill(raw! as JsonObject),
                      ]
                    : null,
              };
            }
            // context_management 存在才映射 appliedEdits(:2449-2453,
            // 2746-2779)。
            final deltaContextManagement = value['context_management'];
            if (deltaContextManagement is JsonObject) {
              contextManagement = <String, Object?>{
                'appliedEdits': [
                  for (final raw in deltaContextManagement['applied_edits']!
                      as List<Object?>)
                    _convertAppliedEdit(raw! as JsonObject),
                ],
              };
            }
            // rawUsage 浅合并,message_delta 字段覆盖同名(:2455-2458)。
            rawUsage = <String, Object?>{...?rawUsage, ...deltaUsage};

          case 'message_stop':
            // metadata 组装式照报告 04 §5.11;iterations 用累积 usage 的值
            // 映射 camelCase(cache 两键 truthy 判断复用 doGenerate 侧助手)。
            final iterations = usage['iterations'];
            final metadata = <String, Object?>{
              'usage': rawUsage,
              'stopSequence': stopSequence,
              if (stopDetails != null) 'stopDetails': stopDetails,
              'iterations': iterations is List<Object?>
                  ? [
                      for (final raw in iterations)
                        _convertUsageIteration(raw! as JsonObject),
                    ]
                  : null,
              'container': container,
              'contextManagement': contextManagement,
            };
            // 双 key 同挂:'anthropic' 恒挂;providerOptions 走了自定义 key
            // 且派生 key ≠ 'anthropic' 时同引用共享(:2495-2504,同
            // doGenerate 侧 _buildProviderMetadata 语义)。
            final customKey = config.providerName.split('.').first;
            yield FinishPart(
              usage: convertAnthropicUsage(usage, rawUsage: rawUsage),
              finishReason: finishReason,
              providerMetadata: {
                'anthropic': metadata,
                if (usedCustomProviderKey && customKey != 'anthropic')
                  customKey: metadata,
              },
            );

          case 'error':
            // 流中段(message_start 之后)的 error 事件 → 流内 ErrorPart,
            // 承载 wire `error` 对象(:2515-2518);error-as-terminal:立即
            // 终止流(pigcode 契约既定,偏离上游"不 close")。首个实义事件
            // 位置的 error 帧已在 doStream 的预读阶段升格为 ApiCallError,
            // 不会走到这里。
            yield ErrorPart(value['error']);
            return;

          default:
            // 未知事件 type:同上游 discriminatedUnion 解析失败路径
            // (报告 04 §8.3)。
            yield ErrorPart(
              FormatException('Unsupported chunk type: ${value['type']}'),
            );
            return;
        }
      }
    } catch (error) {
      // 连接级 Stream error(如 SSE 中途断连):`eventSourceResponseHandler`
      // 按设计把这类失败作为 Dart `Stream.error` 转发(由 provider 层负责
      // 转 ErrorPart,openai 先例)。与帧级错误(ParseFailure/error 事件)
      // 同一终态处理:ErrorPart 后立即终止流,不再补发 TextEnd/FinishPart。
      yield ErrorPart(error);
      return;
    }
  }
}

/// 流式拼装状态机里已注册的 content block 状态(报告 04 §3 的
/// `contentBlocks` 表):text/reasoning 只需标记类型,tool-call 额外携带
/// `{toolCallId, toolName, input}` 累积状态(:1676-1680)。
sealed class _ContentBlockState {
  const _ContentBlockState();

  /// text 块标记(无附加状态)。
  static const text = _TextBlockState();

  /// reasoning 块标记(thinking/redacted_thinking 共用,无附加状态)。
  static const reasoning = _ReasoningBlockState();
}

/// text 块注册状态。
final class _TextBlockState extends _ContentBlockState {
  const _TextBlockState();
}

/// reasoning 块注册状态。
final class _ReasoningBlockState extends _ContentBlockState {
  const _ReasoningBlockState();
}

/// tool_use 块注册状态:input_json_delta 逐段累积进 [input]。
final class _ToolCallBlockState extends _ContentBlockState {
  _ToolCallBlockState({
    required this.toolCallId,
    required this.toolName,
    required this.input,
    this.providerExecuted = false,
    this.providerToolInputType,
  });

  /// 工具调用 id(part id 用它而非块索引,报告 04 §3 :133)。
  final String toolCallId;

  /// 工具名。
  final String toolName;

  /// stringified JSON 输入累积缓冲。
  String input;

  /// 是否为 provider 侧执行的工具(server_tool_use 块,报告 07 §5.1)。
  /// 普通 tool_use 块恒为 false。
  final bool providerExecuted;

  /// 首个非空 `input_json_delta` 需要注入的虚构/子工具 type 值(报告 09
  /// §4.1/§4.2);web_search/web_fetch/tool_search/advisor 恒 null,两个
  /// 子工具恒为自身 wire 名,`code_execution` 恒为
  /// `'programmatic-tool-call'`。是否为「首个非空 delta」不用独立字段
  /// 跟踪——本类无自定义 provider 名映射层(D3),`toolName` 本身即归一后
  /// provider 名;`input` 初始恒为空串(此字段非 null 的三种场景下均如
  /// 此),故 `input.isEmpty` 与上游 `firstDelta` 语义等价,详见
  /// `input_json_delta` 分支实现处的展开论证。
  final String? providerToolInputType;
}

/// wire 响应 → `providerMetadata` 下 `'anthropic'` key 的 metadata 对象
/// (上游 `AnthropicMessageMetadata`,报告 03 §13 :1376-1421):
///
/// - `usage`:wire usage 对象**原样**(snake_case,含 cache_* 键)。
/// - `stopSequence`:`stop_sequence ?? null`(键恒在)。
/// - `stopDetails`:仅 wire `stop_details` 非 null 时才有键;各可选字段仅
///   非 null 时携带,`recommended_model` → `recommendedModel`(:2781-2798)。
/// - `iterations`:`usage.iterations` 映射为 camelCase(:1384-1405);
///   `model` 仅非 null 携带,cache 两键照上游 truthy 判断——**0 也省略**
///   (§16 疑点 3,spec 未裁 → 照上游逐字);无则显式 null。
/// - `container`:有则 `expires_at`→`expiresAt`、`skill_id`→`skillId`,
///   `skills` 缺失/null 保留为 null 键;无则 null(:1406-1417)。
/// - `contextManagement`:有则 `applied_edits`→`appliedEdits`,三种 edit
///   各自 camelCase;无则 null(:1418-1421, :2746-2779)。
JsonObject _buildAnthropicMessageMetadata(JsonObject response) {
  final usage = response['usage']! as JsonObject;
  final stopDetails = response['stop_details'];
  final iterations = usage['iterations'];
  final container = response['container'];
  final contextManagement = response['context_management'];
  return <String, Object?>{
    'usage': usage,
    'stopSequence': response['stop_sequence'],
    if (stopDetails is JsonObject)
      'stopDetails': <String, Object?>{
        'type': stopDetails['type'],
        if (stopDetails['category'] != null)
          'category': stopDetails['category'],
        if (stopDetails['explanation'] != null)
          'explanation': stopDetails['explanation'],
        if (stopDetails['recommended_model'] != null)
          'recommendedModel': stopDetails['recommended_model'],
      },
    'iterations': iterations is List<Object?>
        ? [
            for (final raw in iterations)
              _convertUsageIteration(raw! as JsonObject),
          ]
        : null,
    'container': container is JsonObject
        ? <String, Object?>{
            'expiresAt': container['expires_at'],
            'id': container['id'],
            'skills': container['skills'] is List<Object?>
                ? [
                    for (final raw in container['skills']! as List<Object?>)
                      _convertContainerSkill(raw! as JsonObject),
                  ]
                : null,
          }
        : null,
    'contextManagement': contextManagement is JsonObject
        ? <String, Object?>{
            'appliedEdits': [
              for (final raw
                  in contextManagement['applied_edits']! as List<Object?>)
                _convertAppliedEdit(raw! as JsonObject),
            ],
          }
        : null,
  };
}

/// usage iteration → camelCase(:1384-1405):cache 两键 truthy 判断,
/// 0 省略(与 model 的 `!= null` 判断不一致,照上游逐字)。
JsonObject _convertUsageIteration(JsonObject iteration) {
  final cacheCreation = iteration['cache_creation_input_tokens'];
  final cacheRead = iteration['cache_read_input_tokens'];
  return <String, Object?>{
    'type': iteration['type'],
    if (iteration['model'] != null) 'model': iteration['model'],
    'inputTokens': iteration['input_tokens'],
    'outputTokens': iteration['output_tokens'],
    if (cacheCreation is num && cacheCreation != 0)
      'cacheCreationInputTokens': cacheCreation,
    if (cacheRead is num && cacheRead != 0) 'cacheReadInputTokens': cacheRead,
  };
}

/// container skill → camelCase(:1406-1417):`skill_id` → `skillId`。
JsonObject _convertContainerSkill(JsonObject skill) {
  return <String, Object?>{
    'type': skill['type'],
    'skillId': skill['skill_id'],
    'version': skill['version'],
  };
}

/// context management applied edit → camelCase(:2746-2779):
/// clear_tool_uses / clear_thinking 各带清理计数,compact 仅 type。
JsonObject _convertAppliedEdit(JsonObject edit) {
  return switch (edit['type']) {
    'clear_tool_uses_20250919' => <String, Object?>{
        'type': edit['type'],
        'clearedToolUses': edit['cleared_tool_uses'],
        'clearedInputTokens': edit['cleared_input_tokens'],
      },
    'clear_thinking_20251015' => <String, Object?>{
        'type': edit['type'],
        'clearedThinkingTurns': edit['cleared_thinking_turns'],
        'clearedInputTokens': edit['cleared_input_tokens'],
      },
    _ => <String, Object?>{'type': edit['type']},
  };
}

/// citation 可引用的 prompt 文档条目(报告 03 §10.3 extractCitationDocuments)。
typedef _CitationDocument = ({
  String title,
  String? filename,
  String mediaType,
});

/// 从 prompt 提取 citation 可引用的文档列表(上游 :831-872):遍历 user
/// 消息的 file part,仅 part 级 providerOptions canonical `'anthropic'` key
/// 下 `citations.enabled == true` 且 resolved 完整媒体类型为
/// `application/pdf` / `text/plain` 的;条目按出现顺序对应响应 citation 的
/// `document_index`。
///
/// 【有意偏离,codex 复审定案】上游 isCitationPart 用裸 `mediaType !==`
/// 字符串比较(origin/main :850-861),与其 convert 侧的 resolveFullMediaType
/// 探测自相矛盾(顶级-only `'application'` + PDF 字节会"发了 citations 却
/// 映射不到 document_index"),按"上游内部矛盾不照抄"先例统一为与 Task 7
/// 发送侧同一套 resolved 判定。doGenerate/doStream 共用。
List<_CitationDocument> _extractCitationDocuments(
  List<LanguageModelMessage> prompt,
) {
  final documents = <_CitationDocument>[];
  for (final message in prompt) {
    if (message is! UserMessage) {
      continue;
    }
    for (final part in message.content) {
      if (part is! FilePart) {
        continue;
      }
      final options = part.providerOptions?['anthropic'];
      final citations = options?['citations'];
      final enabled =
          citations is Map<String, Object?> && citations['enabled'] == true;
      if (!enabled) {
        continue;
      }
      // resolveFullMediaType 仅在完整媒体类型或 inline 字节/base64 数据下
      // 可解析;其余(如 text/url 数据 + 顶级-only 类型)不可能是 citation
      // 文档,直接跳过。
      final data = part.data;
      final canResolve = isFullMediaType(part.mediaType) ||
          data is FileDataBytes ||
          data is FileDataBase64;
      if (!canResolve) {
        continue;
      }
      final mediaType = resolveFullMediaType(part);
      if (mediaType != 'application/pdf' && mediaType != 'text/plain') {
        continue;
      }
      documents.add((
        title: part.filename ?? 'Untitled Document',
        filename: part.filename,
        mediaType: mediaType,
      ));
    }
  }
  return documents;
}

/// wire citation → [SourceContent](报告 03 §10.3 / 报告 04 §6
/// createCitationSource,:70-127):
///
/// - `web_search_result_location` → url source,providerMetadata 带
///   `citedText` / `encryptedIndex`(:79-93;仅流侧出现)。
/// - `page_location` / `char_location` 按 `document_index` 查 [documents],
///   越界丢弃(返回 null 不 throw);title 取 `document_title`,缺省回退
///   文档条目 title(:99-126)。
/// - 其余 citation 类型统一丢弃(:95-97)。doGenerate/doStream 共用。
SourceContent? _createCitationSource(
  JsonObject citation,
  List<_CitationDocument> documents,
) {
  final type = citation['type'];
  if (type == 'web_search_result_location') {
    return SourceContent.url(
      id: generateId(),
      url: citation['url']! as String,
      title: citation['title'] as String?,
      providerMetadata: {
        'anthropic': {
          'citedText': citation['cited_text'],
          'encryptedIndex': citation['encrypted_index'],
        },
      },
    );
  }
  if (type != 'page_location' && type != 'char_location') {
    return null;
  }
  final index = citation['document_index'];
  if (index is! int || index < 0 || index >= documents.length) {
    return null;
  }
  final document = documents[index];
  final isPageLocation = type == 'page_location';
  return SourceContent.document(
    id: generateId(),
    mediaType: document.mediaType,
    title: citation['document_title'] as String? ?? document.title,
    filename: document.filename,
    providerMetadata: {
      'anthropic': {
        'citedText': citation['cited_text'],
        if (isPageLocation) 'startPageNumber': citation['start_page_number'],
        if (isPageLocation) 'endPageNumber': citation['end_page_number'],
        if (!isPageLocation) 'startCharIndex': citation['start_char_index'],
        if (!isPageLocation) 'endCharIndex': citation['end_char_index'],
      },
    },
  );
}

/// server_tool_use 白名单(报告 09 §3.2):批次 1 的 web 两名 + 本批
/// code_execution 族(含两子工具)/tool_search 两名/advisor。doGenerate/
/// doStream 共用;不在此集合内的 `server_tool_use.name` 静默丢弃(无兜底
/// else,报告 09 §3.2 "无兜底 else,未知 name 静默丢弃 :1096-1098")。
const _serverToolUseNames = <String>{
  'web_search',
  'web_fetch',
  'code_execution',
  'bash_code_execution',
  'text_editor_code_execution',
  'tool_search_tool_regex',
  'tool_search_tool_bm25',
  'advisor',
};

/// dynamic 标记判定(报告 09 §3.1 :2677-2700,D7):请求侧 wire 工具列表里
/// 存在 `web_fetch_20260209`/`web_search_20260209` 类型的 provider 工具、
/// 且不存在名为 `code_execution` 的工具(不论 function 工具还是 provider
/// 工具,name 判定,同名 function 工具同样抑制)时返回 true。[tools] 传入
/// 已构造完成的 wire 工具数组(`_buildArgs` 结果的 `args['tools']`),不是
/// 契约层 `LanguageModelTool` 列表——函数工具的 wire 形态无 `type` 键、
/// provider 工具有,以此区分(:2687)。
bool _hasWebTool20260209WithoutCodeExecution(List<JsonObject>? tools) {
  if (tools == null) {
    return false;
  }
  var hasWebTool20260209 = false;
  var hasCodeExecutionTool = false;
  for (final tool in tools) {
    if (tool.containsKey('type') &&
        (tool['type'] == 'web_fetch_20260209' ||
            tool['type'] == 'web_search_20260209')) {
      hasWebTool20260209 = true;
      continue;
    }
    if (tool['name'] == 'code_execution') {
      hasCodeExecutionTool = true;
      break;
    }
  }
  return hasWebTool20260209 && !hasCodeExecutionTool;
}

/// `code_execution_tool_result` 块 → `ToolResult`(报告 09 §3.3,doGenerate
/// /doStream 共用)。content 三态:`code_execution_result`(stdout/stderr/
/// return_code/content,**return_code 保留 snake_case**——D5②)、
/// `encrypted_code_execution_result`(**encrypted_stdout 保留
/// snake_case**,20260120 专属)、`code_execution_tool_result_error`
/// (isError:true,error_code → errorCode——与前两者的 snake 保留**不对称**,
/// 报告 09 §9.2,照抄)。
ToolResult _parseCodeExecutionToolResult(JsonObject block) {
  final toolCallId = block['tool_use_id']! as String;
  final resultContent = block['content']! as JsonObject;
  switch (resultContent['type']) {
    case 'code_execution_result':
      return ToolResult(
        toolCallId: toolCallId,
        toolName: 'code_execution',
        result: {
          'type': resultContent['type'],
          'stdout': resultContent['stdout'],
          'stderr': resultContent['stderr'],
          'return_code': resultContent['return_code'],
          'content': resultContent['content'] ?? const <Object?>[],
        },
      );
    case 'encrypted_code_execution_result':
      return ToolResult(
        toolCallId: toolCallId,
        toolName: 'code_execution',
        result: {
          'type': resultContent['type'],
          'encrypted_stdout': resultContent['encrypted_stdout'],
          'stderr': resultContent['stderr'],
          'return_code': resultContent['return_code'],
          'content': resultContent['content'] ?? const <Object?>[],
        },
      );
    default:
      // code_execution_tool_result_error(:1242-1253)。
      return ToolResult(
        toolCallId: toolCallId,
        toolName: 'code_execution',
        result: {
          'type': resultContent['type'],
          'errorCode': resultContent['error_code'],
        },
        isError: true,
      );
  }
}

/// `bash_code_execution_tool_result` / `text_editor_code_execution_tool_result`
/// 块 → `ToolResult`(报告 09 §3.4,doGenerate/doStream 共用)。content
/// **原样透传**(含错误变体 `..._tool_result_error`,字段保持 wire 原状不
/// 做任何 camel 转换),toolName 归一 `code_execution`;**错误变体同样透
/// 传、不标 isError**(与 `code_execution_tool_result_error` 不一致,上游
/// 刻意如此——报告 09 §9.1,D5 verbatim 照抄)。
ToolResult _parseBashOrTextEditorCodeExecutionToolResult(JsonObject block) {
  return ToolResult(
    toolCallId: block['tool_use_id']! as String,
    toolName: 'code_execution',
    result: block['content'],
  );
}

/// `tool_search_tool_result` 块 → `ToolResult`(报告 09 §3.5,doGenerate/
/// doStream 共用)。
///
/// 定名:优先取 [serverToolCalls] 里本响应内配对的 `server_tool_use` 名;
/// 缺席(deferred 结果,跨响应到达)时,上游靠「用户给 provider 工具起了
/// 自定义别名」这一信号判别 bm25/regex(:1271-1288)——pigcode「ToolSet
/// key = wire name」不变式下该判据恒失败,**等价地恒落
/// `'tool_search_tool_regex'`**(报告 09 §9.9,bm25 的跨响应 deferred 结果
/// 因此会被冠以 regex 名,是上游同款行为,非 pigcode 独有缺陷)。成功:
/// `tool_references` 逐条 `tool_name` → `toolName` 转 camel;错误:
/// `isError:true` + `errorCode`。
ToolResult _parseToolSearchToolResult(
  JsonObject block,
  Map<String, String> serverToolCalls,
) {
  final toolCallId = block['tool_use_id']! as String;
  final providerToolName =
      serverToolCalls[toolCallId] ?? 'tool_search_tool_regex';
  final resultContent = block['content']! as JsonObject;
  if (resultContent['type'] == 'tool_search_tool_result_error') {
    return ToolResult(
      toolCallId: toolCallId,
      toolName: providerToolName,
      result: {
        'type': resultContent['type'],
        'errorCode': resultContent['error_code'],
      },
      isError: true,
    );
  }
  final references = resultContent['tool_references']! as List<Object?>;
  final items = <Map<String, Object?>>[];
  for (final raw in references) {
    final reference = raw! as JsonObject;
    items.add({
      'type': reference['type'],
      'toolName': reference['tool_name'],
    });
  }
  return ToolResult(
    toolCallId: toolCallId,
    toolName: providerToolName,
    result: items,
  );
}

/// `advisor_tool_result` 块 → `ToolResult`(报告 09 §3.6,doGenerate/
/// doStream 共用)。三态:`advisor_result`(text)、`advisor_redacted_result`
/// (`encrypted_content` → `encryptedContent`,须原样回传供服务端解密)、
/// `advisor_tool_result_error`(isError:true + errorCode)。
ToolResult _parseAdvisorToolResult(JsonObject block) {
  final toolCallId = block['tool_use_id']! as String;
  final resultContent = block['content']! as JsonObject;
  switch (resultContent['type']) {
    case 'advisor_result':
      return ToolResult(
        toolCallId: toolCallId,
        toolName: 'advisor',
        result: {
          'type': resultContent['type'],
          'text': resultContent['text'],
        },
      );
    case 'advisor_redacted_result':
      return ToolResult(
        toolCallId: toolCallId,
        toolName: 'advisor',
        result: {
          'type': resultContent['type'],
          'encryptedContent': resultContent['encrypted_content'],
        },
      );
    default:
      // advisor_tool_result_error(:1338-1349)。
      return ToolResult(
        toolCallId: toolCallId,
        toolName: 'advisor',
        result: {
          'type': resultContent['type'],
          'errorCode': resultContent['error_code'],
        },
        isError: true,
      );
  }
}

/// `web_search_tool_result` 块 → `ToolResult` + 每条结果一个
/// `SourceContent.url`(报告 07 §4.3 :1170-1212)。
///
/// 判别方式是 `content is List`(:1171),不是看 wire type:成功为数组,
/// 每条映射 snake→camel(`page_age` 缺省归一为 null);每条结果额外产出一个
/// url source,`providerMetadata.anthropic.pageAge` 同源。错误为单个对象,
/// 原样透传 `errorCode`,`isError: true`,不产出 source。web_search 不追加
/// citationDocuments(§4.3 :254)。
List<LanguageModelContent> _parseWebSearchToolResult(JsonObject block) {
  final toolCallId = block['tool_use_id']! as String;
  final resultContent = block['content'];
  if (resultContent is List<Object?>) {
    final items = <Map<String, Object?>>[];
    final sources = <SourceContent>[];
    for (final raw in resultContent) {
      final item = raw! as JsonObject;
      final pageAge = item['page_age'] as String?;
      items.add({
        'type': item['type'],
        'url': item['url'],
        'title': item['title'],
        'pageAge': pageAge,
        'encryptedContent': item['encrypted_content'],
      });
      sources.add(SourceContent.url(
        id: generateId(),
        url: item['url']! as String,
        title: item['title'] as String?,
        providerMetadata: {
          'anthropic': {'pageAge': pageAge},
        },
      ));
    }
    return [
      ToolResult(
        toolCallId: toolCallId,
        toolName: 'web_search',
        result: items,
      ),
      ...sources,
    ];
  }
  final error = resultContent! as JsonObject;
  return [
    ToolResult(
      toolCallId: toolCallId,
      toolName: 'web_search',
      result: {
        'type': error['type'],
        'errorCode': error['error_code'],
      },
      isError: true,
    ),
  ];
}

/// `web_fetch_tool_result` 块 → `ToolResult`(报告 07 §4.2 :1130-1168)。
///
/// 成功变体:先把 `{title: content.title ?? url, mediaType: source.media_type}`
/// 追加进 [citationDocuments](供后续 text 块 `page_location`/`char_location`
/// citation 按 document_index 查到本条 fetched 文档),再产出 snake→camel
/// (`retrieved_at`→`retrievedAt`、`media_type`→`mediaType`)后的 ToolResult;
/// 不产出 source part(:245)。错误变体:`isError: true`,不追加
/// citationDocuments。返回 `(ToolResult, 更新后的 citationDocuments)`。
(ToolResult, List<_CitationDocument>) _parseWebFetchToolResult(
  JsonObject block,
  List<_CitationDocument> citationDocuments,
) {
  final toolCallId = block['tool_use_id']! as String;
  final resultContent = block['content']! as JsonObject;
  if (resultContent['type'] == 'web_fetch_tool_result_error') {
    return (
      ToolResult(
        toolCallId: toolCallId,
        toolName: 'web_fetch',
        result: {
          'type': resultContent['type'],
          'errorCode': resultContent['error_code'],
        },
        isError: true,
      ),
      citationDocuments,
    );
  }
  final url = resultContent['url']! as String;
  final document = resultContent['content']! as JsonObject;
  final source = document['source']! as JsonObject;
  final title = document['title'] as String?;
  final mediaType = source['media_type']! as String;
  final updatedDocuments = [
    ...citationDocuments,
    (title: title ?? url, filename: null, mediaType: mediaType),
  ];
  final result = ToolResult(
    toolCallId: toolCallId,
    toolName: 'web_fetch',
    result: {
      'type': resultContent['type'],
      'url': url,
      'retrievedAt': resultContent['retrieved_at'],
      'content': {
        'type': document['type'],
        'title': title,
        // citations 是 optional 字段:wire 缺席时不写键(写 null 会被回传侧
        // validator 拒绝——'object' 类型不接受 null;JS undefined 缺席语义的
        // Dart 等价是键不存在,保证解析↔回传往返自洽,codex PR #61 复审)。
        if (document['citations'] != null) 'citations': document['citations'],
        'source': {
          'type': source['type'],
          'mediaType': mediaType,
          'data': source['data'],
        },
      },
    },
  );
  return (result, updatedDocuments);
}
