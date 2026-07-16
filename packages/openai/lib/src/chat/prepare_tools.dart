import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// [prepareOpenAiChatTools] 的返回值:wire 工具数组 + toolChoice + 告警。
final class OpenAiChatToolsResult {
  const OpenAiChatToolsResult({
    this.tools,
    this.toolChoice,
    required this.warnings,
  });

  /// OpenAI `tools` 数组;`null` 表示不下发该字段(空输入或全部工具被跳过)。
  final List<Map<String, Object?>>? tools;

  /// OpenAI `tool_choice`:`String`('auto'/'none'/'required')或
  /// `Map`(`{'type':'function','function':{'name':...}}`);`null` 表示不
  /// 下发该字段。
  final Object? toolChoice;

  /// 工具映射期间产生的告警(如不支持的工具类型)。
  final List<Warning> warnings;
}

/// 把契约层工具集合与 toolChoice 映射为 OpenAI Chat Completions 的
/// `tools`/`tool_choice` 字段。
///
/// wire 语义逐字对照 v7 `prepareChatTools`(`raw/openai-chat-prepare-tools.ts`):
/// 仅 `FunctionTool` 受支持,其余工具类型(如 provider 内置工具)推
/// [UnsupportedWarning] 并跳过,不中断整体转换;toolChoice 的
/// `auto`/`none`/`required` 直接透传字符串,`tool` 转为
/// `{type:'function', function:{name}}`;toolChoice 类型理论上已被契约层
/// sealed class 穷尽,若未来新增分支则 throw [UnsupportedFunctionalityError]
/// (防御性分支,当前不可达)。
OpenAiChatToolsResult prepareOpenAiChatTools({
  required List<LanguageModelTool>? tools,
  required ToolChoice? toolChoice,
}) {
  final normalizedTools = (tools == null || tools.isEmpty) ? null : tools;

  final warnings = <Warning>[];

  if (normalizedTools == null) {
    return OpenAiChatToolsResult(warnings: warnings);
  }

  final openaiTools = <Map<String, Object?>>[];
  for (final tool in normalizedTools) {
    switch (tool) {
      case FunctionTool(
          :final name,
          :final description,
          :final inputSchema,
          :final strict,
        ):
        openaiTools.add({
          'type': 'function',
          'function': {
            'name': name,
            if (description != null) 'description': description,
            'parameters': inputSchema.value,
            if (strict != null) 'strict': strict,
          },
        });
      case ProviderTool(:final id):
        warnings.add(UnsupportedWarning('tool type: $id'));
    }
  }

  // 所有工具都因不支持被过滤后,openaiTools 为空;此时应像"一开始就没传
  // 工具"一样省略 tools/tool_choice,而不是发送空数组(OpenAI 拒绝空
  // `tools`),让调用方优雅降级为无工具请求,Warning 仍保留。
  if (openaiTools.isEmpty) {
    return OpenAiChatToolsResult(warnings: warnings);
  }

  if (toolChoice == null) {
    return OpenAiChatToolsResult(tools: openaiTools, warnings: warnings);
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

  return OpenAiChatToolsResult(
    tools: openaiTools,
    toolChoice: mappedToolChoice,
    warnings: warnings,
  );
}
