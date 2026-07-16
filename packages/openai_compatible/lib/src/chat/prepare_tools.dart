import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// [prepareOpenAiCompatibleTools] 的返回值:wire 工具数组 + toolChoice + 告警。
final class OpenAiCompatibleToolsResult {
  const OpenAiCompatibleToolsResult({
    required this.tools,
    required this.toolChoice,
    required this.warnings,
  });

  /// OpenAI 兼容 `tools` 数组;`null` 表示不下发该字段(输入为 `null`/空)。
  ///
  /// **注意**:若输入非空但全部工具都因是 `ProviderTool` 被过滤,本字段是
  /// **空数组 `[]`**,不是 `null`(对照 raw 源码逐字取齐,这一点与
  /// `pigcode_ai_openai` 的 `prepareOpenAiChatTools`——全部过滤后归零为 `null`——
  /// **不同**,是本包相对 openai 包的独立差异,不是实现疏漏)。
  final List<JsonObject>? tools;

  /// OpenAI 兼容 `tool_choice`:`String`('auto'/'none'/'required')或
  /// `Map`(`{'type':'function','function':{'name':...}}`);`null` 表示不
  /// 下发该字段。
  final Object? toolChoice;

  /// 工具映射期间产生的告警(如 provider-defined 工具不受支持)。
  final List<Warning> warnings;
}

/// 把契约层工具集合与 toolChoice 映射为 OpenAI 兼容 Chat Completions 的
/// `tools`/`tool_choice` 字段。
///
/// wire 语义逐字对照 v7 `prepareTools`
/// (`raw/compatible__openai-compatible-prepare-tools.ts`):比
/// `pigcode_ai_openai` 的 chat 版本更宽松——**`type != 'provider'` 一律当作
/// function 处理**(在 Dart sealed `LanguageModelTool` 上体现为
/// `FunctionTool` 走正常映射、`ProviderTool` 推 unsupported warning 并跳过,
/// 与 openai 包结构一致,因为契约层本来就只有这两态判别联合;差异体现在
/// warning 文案与"全部过滤后是否归零"两点,详见字段/分支注释)。
OpenAiCompatibleToolsResult prepareOpenAiCompatibleTools({
  required List<LanguageModelTool>? tools,
  ToolChoice? toolChoice,
}) {
  final normalizedTools = (tools == null || tools.isEmpty) ? null : tools;

  final warnings = <Warning>[];

  if (normalizedTools == null) {
    return OpenAiCompatibleToolsResult(
      tools: null,
      toolChoice: null,
      warnings: warnings,
    );
  }

  final openaiCompatTools = <JsonObject>[];
  for (final tool in normalizedTools) {
    switch (tool) {
      case ProviderTool(:final id):
        // warning 文案逐字对齐 raw 的 `provider-defined tool ${tool.id}`,
        // 与 openai 包的 'tool type: $id' 措辞不同,不套用。
        warnings.add(UnsupportedWarning('provider-defined tool $id'));
      case FunctionTool(
          :final name,
          :final description,
          :final inputSchema,
          :final strict,
        ):
        // description/strict 仅在非 null 时携带键(raw 对 strict 即条件
        // 展开;description 在 TS 侧是恒定键但 JSON.stringify 会丢弃
        // undefined 值,Dart 侧选择等价且更干净的"不携带",与 openai 包
        // prepare_tools 的既定惯例一致)。
        openaiCompatTools.add({
          'type': 'function',
          'function': {
            'name': name,
            if (description != null) 'description': description,
            'parameters': inputSchema.value,
            if (strict != null) 'strict': strict,
          },
        });
    }
  }

  // raw 在"工具全部被过滤为 provider 类型"后不做归零(tools 保持空数组
  // 继续走 toolChoice 判定),此处如实对齐,不套用 openai 包的提前返回。
  if (toolChoice == null) {
    return OpenAiCompatibleToolsResult(
      tools: openaiCompatTools,
      toolChoice: null,
      warnings: warnings,
    );
  }

  final Object mappedToolChoice = switch (toolChoice) {
    ToolChoiceAuto() => 'auto',
    ToolChoiceNone() => 'none',
    ToolChoiceRequired() => 'required',
    ToolChoiceTool(:final toolName) => {
        'type': 'function',
        'function': {'name': toolName},
      },
  };

  return OpenAiCompatibleToolsResult(
    tools: openaiCompatTools,
    toolChoice: mappedToolChoice,
    warnings: warnings,
  );
}
