import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

/// `web_search_20250305`/`web_search_20260209` 共用的 args 校验 schema
/// (报告 07 §1.2 字段表;两版 factory 逐字节等同,故共用同一 validator)。
final _webSearchArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'maxUses': {'type': 'integer'},
      'allowedDomains': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'blockedDomains': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'userLocation': {
        'type': 'object',
        'properties': {
          'type': {'const': 'approximate'},
          'city': {'type': 'string'},
          'region': {'type': 'string'},
          'country': {'type': 'string'},
          'timezone': {'type': 'string'},
        },
        'required': ['type'],
      },
    },
  }),
);

/// `web_fetch_20250910`/`web_fetch_20260209` 共用的 args 校验 schema
/// (报告 07 §1.4 字段表;两版 factory 逐字节等同,故共用同一 validator)。
final _webFetchArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'maxUses': {'type': 'integer'},
      'allowedDomains': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'blockedDomains': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'citations': {
        'type': 'object',
        'properties': {
          'enabled': {'type': 'boolean'},
        },
        'required': ['enabled'],
      },
      'maxContentTokens': {'type': 'integer'},
    },
  }),
);

/// `computer_20241022`/`computer_20250124`/`computer_20251124` 共用的 args
/// 校验 schema(报告 08 §2.1-2.3 ARGS 字段表;三版 args 形态一致,故共用同一
/// validator)。上游对 computer 的 args 只做 `as number` 断言、无运行时校验
/// (报告 08 §3.2),此处按计划 D6("args 走 validator")统一加本地校验,
/// 与本文件 web 工具风格一致——记录为与报告 08 的已知偏差。
final _computerArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'displayWidthPx': {'type': 'integer'},
      'displayHeightPx': {'type': 'integer'},
      'displayNumber': {'type': 'integer'},
      'enableZoom': {'type': 'boolean'},
    },
    'required': ['displayWidthPx', 'displayHeightPx'],
  }),
);

/// `text_editor_20250728` 的 args 校验 schema(报告 08 §2.6 字段表;
/// 20241022/20250124 无 args,不需要 validator)。
final _textEditor20250728ArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'maxCharacters': {'type': 'integer'},
    },
  }),
);

/// `advisor_20260301` 的 args 校验 schema(报告 09 §1.7/§6 字段表;model
/// 必填 string、maxUses 可选 number(无 bounds、无 int 限定,上游 zod 同)、
/// caching 可选对象(`type` 恒 'ephemeral'、`ttl` 枚举 '5m'/'1h')。本批
/// 7 个工厂中唯一带 args 校验者,其余 6 个无 args 不需要 validator,与
/// 上游"仅 advisor 走 validateTypes"一致(报告 09 §2)。
final _advisorArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'model': {'type': 'string'},
      'maxUses': {'type': 'number'},
      'caching': {
        'type': 'object',
        'properties': {
          'type': {
            'enum': ['ephemeral'],
          },
          'ttl': {
            'enum': ['5m', '1h'],
          },
        },
        'required': ['type', 'ttl'],
      },
    },
    'required': ['model'],
  }),
);

/// 从工具级 [ProviderOptions] 解析 `cache_control` 的回调。
///
/// 用回调解耦对 `cache_control.dart` 的编译期依赖:真实接线(Task 16)由
/// 模型层传入 `CacheControlValidator.getCacheControl` 的偏应用(context
/// `'tool definition'`、`canCache: true`,上游 anthropic-prepare-tools.ts
/// :75-78);单测可注入 stub。返回 null 表示该工具不带 `cache_control`。
typedef ToolCacheControlResolver = Map<String, Object?>? Function(
  ProviderOptions? providerOptions,
);

/// [prepareAnthropicTools] 的返回值:wire 工具数组 + toolChoice + 告警 +
/// 工具面触发的 beta 集合。
final class AnthropicToolsResult {
  /// 构造一份工具准备结果。
  const AnthropicToolsResult({
    this.tools,
    this.toolChoice,
    required this.warnings,
    required this.betas,
  });

  /// Anthropic `tools` 数组;`null` 表示不下发该字段(空输入或全部工具被
  /// 跳过,上游 :60/:71 空数组不发)。
  final List<Map<String, Object?>>? tools;

  /// Anthropic `tool_choice` 对象;wire 无字符串形态,且**无** `none` 形态
  /// (anthropic-api.ts :527-529),契约 [ToolChoiceNone] 映射为整体省略
  /// tools/tool_choice。
  final Map<String, Object?>? toolChoice;

  /// 工具映射期间产生的告警(不支持的工具类型、strict 门控等)。
  final List<Warning> warnings;

  /// function tool 触发的 beta 集合(:121-127),由模型层并入请求级
  /// beta 合成 Set(Task 16/18 接线)。
  final Set<String> betas;
}

/// 把契约层工具集合映射为 Anthropic Messages 的 `tools` 字段。
///
/// wire 语义逐字对照上游 `anthropic-prepare-tools.ts`(报告 05 §1.1):
/// Anthropic function tool 是**扁平对象**(非 OpenAI 嵌套形态),字段
/// `name` / `description` / `input_schema` / `cache_control` /
/// `eager_input_streaming` / `strict` / `defer_loading` /
/// `allowed_callers` / `input_examples`。工具级 providerOptions 只读
/// canonical `'anthropic'` key(上游 :42)。首版无 provider tools:
/// [ProviderTool] 一律推 [UnsupportedWarning](文案带 id,spec 疑点 #5)
/// 并丢弃。
///
/// [toolChoice] 映射(报告 05 §1.3,上游 :387-441):契约 `required` →
/// wire `any`;[ToolChoiceNone] → 整体省略 tools/tool_choice(wire 无
/// `none` 形态),但 warnings 与 betas **不回滚**(spec 疑点 #7 照上游);
/// [toolChoice] 为 null 时仅在 [disableParallelToolUse] 为 truthy 时发
/// `{'type':'auto','disable_parallel_tool_use':true}`(上游 :389-396,
/// falsy → 不发,与显式 choice 分支保留显式 false 的行为差异是上游语义)。
AnthropicToolsResult prepareAnthropicTools({
  required List<LanguageModelTool>? tools,
  required ToolChoice? toolChoice,
  required bool? disableParallelToolUse,
  required ToolCacheControlResolver getCacheControl,
  required bool supportsStructuredOutput,
  required bool supportsStrictTools,
  bool defaultEagerInputStreaming = false,
}) {
  // 空数组归一化为 null(上游 :60);tools 为空时不处理 toolChoice(:66-68)。
  final normalizedTools = (tools == null || tools.isEmpty) ? null : tools;

  final warnings = <Warning>[];
  final betas = <String>{};

  if (normalizedTools == null) {
    return AnthropicToolsResult(warnings: warnings, betas: betas);
  }

  final anthropicTools = <Map<String, Object?>>[];
  for (final tool in normalizedTools) {
    switch (tool) {
      case FunctionTool(
          :final name,
          :final description,
          :final inputSchema,
          :final inputExamples,
          :final strict,
          :final providerOptions,
        ):
        final anthropicOptions = providerOptions?['anthropic'];
        final cacheControl = getCacheControl(providerOptions);
        // 工具级选项优先,缺省回退调用级默认;最终值 falsy 时字段完全不发
        // (上游 :86-87、:104)。
        final eagerInputStreaming =
            anthropicOptions?['eagerInputStreaming'] as bool? ??
                defaultEagerInputStreaming;
        final deferLoading = anthropicOptions?['deferLoading'];
        final allowedCallers = anthropicOptions?['allowedCallers'];

        // strict 门控(上游 :91-97、:105-107):模型不支持而显式设置时
        // 推 warning 且不发字段。
        var sendStrict = false;
        if (strict != null) {
          if (supportsStrictTools) {
            sendStrict = true;
          } else {
            warnings.add(
              UnsupportedWarning(
                'strict',
                details: "Tool '$name' has strict: $strict, but strict mode "
                    'is not supported by this provider. The strict property '
                    'will be ignored.',
              ),
            );
          }
        }

        anthropicTools.add({
          'name': name,
          if (description != null) 'description': description,
          'input_schema': inputSchema.value,
          if (cacheControl != null) 'cache_control': cacheControl,
          if (eagerInputStreaming) 'eager_input_streaming': true,
          if (sendStrict) 'strict': strict,
          // deferLoading 显式 false 也发送(上游 :108)。
          if (deferLoading != null) 'defer_loading': deferLoading,
          if (allowedCallers != null) 'allowed_callers': allowedCallers,
          // pigcode 契约 inputExamples 已是裸 List<JsonObject>,直接透传。
          if (inputExamples != null) 'input_examples': inputExamples,
        });

        // function tool 触发的 beta(上游 :121-127,Set 天然去重)。
        if (supportsStructuredOutput) {
          betas.add('structured-outputs-2025-11-13');
        }
        if (inputExamples != null || allowedCallers != null) {
          betas.add('advanced-tool-use-2025-11-20');
        }
      case ProviderTool(:final id, :final args):
        switch (id) {
          case 'anthropic.web_search_20250305':
            validateTypes(args, _webSearchArgsValidator);
            anthropicTools.add({
              'type': 'web_search_20250305',
              'name': 'web_search',
              if (args['maxUses'] != null) 'max_uses': args['maxUses'],
              if (args['allowedDomains'] != null)
                'allowed_domains': args['allowedDomains'],
              if (args['blockedDomains'] != null)
                'blocked_domains': args['blockedDomains'],
              if (args['userLocation'] != null)
                'user_location': args['userLocation'],
            });
          // 20250305 无 beta(报告 07 §1.6)。
          case 'anthropic.web_search_20260209':
            validateTypes(args, _webSearchArgsValidator);
            betas.add('code-execution-web-tools-2026-02-09');
            anthropicTools.add({
              'type': 'web_search_20260209',
              'name': 'web_search',
              if (args['maxUses'] != null) 'max_uses': args['maxUses'],
              if (args['allowedDomains'] != null)
                'allowed_domains': args['allowedDomains'],
              if (args['blockedDomains'] != null)
                'blocked_domains': args['blockedDomains'],
              if (args['userLocation'] != null)
                'user_location': args['userLocation'],
            });
          case 'anthropic.web_fetch_20250910':
            validateTypes(args, _webFetchArgsValidator);
            betas.add('web-fetch-2025-09-10');
            anthropicTools.add({
              'type': 'web_fetch_20250910',
              'name': 'web_fetch',
              if (args['maxUses'] != null) 'max_uses': args['maxUses'],
              if (args['allowedDomains'] != null)
                'allowed_domains': args['allowedDomains'],
              if (args['blockedDomains'] != null)
                'blocked_domains': args['blockedDomains'],
              if (args['citations'] != null) 'citations': args['citations'],
              if (args['maxContentTokens'] != null)
                'max_content_tokens': args['maxContentTokens'],
            });
          case 'anthropic.web_fetch_20260209':
            validateTypes(args, _webFetchArgsValidator);
            betas.add('code-execution-web-tools-2026-02-09');
            anthropicTools.add({
              'type': 'web_fetch_20260209',
              'name': 'web_fetch',
              if (args['maxUses'] != null) 'max_uses': args['maxUses'],
              if (args['allowedDomains'] != null)
                'allowed_domains': args['allowedDomains'],
              if (args['blockedDomains'] != null)
                'blocked_domains': args['blockedDomains'],
              if (args['citations'] != null) 'citations': args['citations'],
              if (args['maxContentTokens'] != null)
                'max_content_tokens': args['maxContentTokens'],
            });
          case 'anthropic.computer_20241022':
            validateTypes(args, _computerArgsValidator);
            betas.add('computer-use-2024-10-22');
            anthropicTools.add({
              'type': 'computer_20241022',
              'name': 'computer',
              'display_width_px': args['displayWidthPx'],
              'display_height_px': args['displayHeightPx'],
              if (args['displayNumber'] != null)
                'display_number': args['displayNumber'],
            });
          case 'anthropic.computer_20250124':
            validateTypes(args, _computerArgsValidator);
            betas.add('computer-use-2025-01-24');
            anthropicTools.add({
              'type': 'computer_20250124',
              'name': 'computer',
              'display_width_px': args['displayWidthPx'],
              'display_height_px': args['displayHeightPx'],
              if (args['displayNumber'] != null)
                'display_number': args['displayNumber'],
            });
          case 'anthropic.computer_20251124':
            validateTypes(args, _computerArgsValidator);
            betas.add('computer-use-2025-11-24');
            anthropicTools.add({
              'type': 'computer_20251124',
              'name': 'computer',
              'display_width_px': args['displayWidthPx'],
              'display_height_px': args['displayHeightPx'],
              if (args['displayNumber'] != null)
                'display_number': args['displayNumber'],
              if (args['enableZoom'] != null) 'enable_zoom': args['enableZoom'],
            });
          case 'anthropic.text_editor_20241022':
            betas.add('computer-use-2024-10-22');
            anthropicTools.add({
              'type': 'text_editor_20241022',
              'name': 'str_replace_editor',
            });
          case 'anthropic.text_editor_20250124':
            betas.add('computer-use-2025-01-24');
            anthropicTools.add({
              'type': 'text_editor_20250124',
              'name': 'str_replace_editor',
            });
          case 'anthropic.text_editor_20250728':
            // 报告 08 §3.1(:220):20250728 无 beta,与前两版不同。
            validateTypes(args, _textEditor20250728ArgsValidator);
            anthropicTools.add({
              'type': 'text_editor_20250728',
              'name': 'str_replace_based_edit_tool',
              if (args['maxCharacters'] != null)
                'max_characters': args['maxCharacters'],
            });
          case 'anthropic.bash_20241022':
            // 无 args(报告 08 §3.1),直接 push wire 对象。
            betas.add('computer-use-2024-10-22');
            anthropicTools.add({'type': 'bash_20241022', 'name': 'bash'});
          case 'anthropic.bash_20250124':
            betas.add('computer-use-2025-01-24');
            anthropicTools.add({'type': 'bash_20250124', 'name': 'bash'});
          case 'anthropic.code_execution_20250522':
            // 无 args(报告 09 §1.1)。20250522 的 cache_control 上游写字面
            // 键 `cache_control: undefined`(JSON 序列化即丢),Dart 侧统一
            // 不写该键,语义等价(报告 09 §6.6),故此处与其余 6 个 case
            // 一样不出现 cache_control。
            betas.add('code-execution-2025-05-22');
            anthropicTools.add({
              'type': 'code_execution_20250522',
              'name': 'code_execution',
            });
          case 'anthropic.code_execution_20250825':
            // 无 args(报告 09 §1.2)。
            betas.add('code-execution-2025-08-25');
            anthropicTools.add({
              'type': 'code_execution_20250825',
              'name': 'code_execution',
            });
          case 'anthropic.code_execution_20260120':
            // 无 args、无 beta(报告 09 §1.3/§2)。
            anthropicTools.add({
              'type': 'code_execution_20260120',
              'name': 'code_execution',
            });
          case 'anthropic.memory_20250818':
            // 无 args(报告 09 §1.4)。
            betas.add('context-management-2025-06-27');
            anthropicTools.add({
              'type': 'memory_20250818',
              'name': 'memory',
            });
          case 'anthropic.tool_search_regex_20251119':
            // 无 args、无 beta;id 段无中间 tool,wire type/name 才有
            // (报告 09 §1.5)。
            anthropicTools.add({
              'type': 'tool_search_tool_regex_20251119',
              'name': 'tool_search_tool_regex',
            });
          case 'anthropic.tool_search_bm25_20251119':
            // 无 args、无 beta;id 段无中间 tool,wire type/name 才有
            // (报告 09 §1.6)。
            anthropicTools.add({
              'type': 'tool_search_tool_bm25_20251119',
              'name': 'tool_search_tool_bm25',
            });
          case 'anthropic.advisor_20260301':
            // 本批唯一带 args 校验;model 无条件写键,max_uses/caching
            // 缺席写键(报告 09 §2 advisor case 全文,D6)。
            validateTypes(args, _advisorArgsValidator);
            betas.add('advisor-tool-2026-03-01');
            anthropicTools.add({
              'type': 'advisor_20260301',
              'name': 'advisor',
              'model': args['model'],
              if (args['maxUses'] != null) 'max_uses': args['maxUses'],
              if (args['caching'] != null) 'caching': args['caching'],
            });
          default:
            // 未知 provider tool 一律 warning + 丢弃(上游 :366-372;
            // 文案带 id,spec 疑点 #5)。
            warnings.add(UnsupportedWarning('provider-defined tool $id'));
        }
    }
  }

  // 所有工具都被丢弃后像"一开始就没传工具"一样省略 tools/tool_choice
  // (上游 :71 空数组不发),warnings 保留。
  if (anthropicTools.isEmpty) {
    return AnthropicToolsResult(warnings: warnings, betas: betas);
  }

  // toolChoice 映射(上游 :387-441)。Dart sealed 四变体穷举后不存在上游
  // "其他 toolChoice 类型抛错"分支(:435-440),不写不可达代码(openai 同型)。
  final dp = disableParallelToolUse;
  switch (toolChoice) {
    case null:
      // null-choice 分支仅 truthy 触发(上游 :389-396),falsy 不发。
      return AnthropicToolsResult(
        tools: anthropicTools,
        toolChoice: dp == true
            ? const {'type': 'auto', 'disable_parallel_tool_use': true}
            : null,
        warnings: warnings,
        betas: betas,
      );
    case ToolChoiceAuto():
      return AnthropicToolsResult(
        tools: anthropicTools,
        toolChoice: {
          'type': 'auto',
          if (dp != null) 'disable_parallel_tool_use': dp,
        },
        warnings: warnings,
        betas: betas,
      );
    case ToolChoiceRequired():
      // 契约 required → wire `any`(上游 :411-420)。
      return AnthropicToolsResult(
        tools: anthropicTools,
        toolChoice: {
          'type': 'any',
          if (dp != null) 'disable_parallel_tool_use': dp,
        },
        warnings: warnings,
        betas: betas,
      );
    case ToolChoiceNone():
      // wire 无 `none` 形态:整体省略 tools/tool_choice(上游 :421-423),
      // warnings 与 betas 不回滚(spec 疑点 #7 照上游)。
      return AnthropicToolsResult(warnings: warnings, betas: betas);
    case ToolChoiceTool(:final toolName):
      return AnthropicToolsResult(
        tools: anthropicTools,
        toolChoice: {
          'type': 'tool',
          'name': toolName,
          if (dp != null) 'disable_parallel_tool_use': dp,
        },
        warnings: warnings,
        betas: betas,
      );
  }
}
