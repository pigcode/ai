import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../tool/tool.dart';

/// 控制工具广告给 provider 时的顺序。
///
/// 列出的工具会优先按该顺序发送；未列出的工具随后按名称排序发送。
typedef ToolOrder = List<String>;

/// 按 [toolOrder] 构建发给 provider 的工具列表(函数工具 + provider 工具混合）。
List<provider.LanguageModelTool> buildOrderedLanguageModelTools(
  ToolSet tools,
  ToolOrder? toolOrder,
  ToolSet? knownTools,
) =>
    buildLanguageModelTools(orderTools(tools, toolOrder, knownTools));

/// 按 [toolOrder] 重新排列工具集。
ToolSet orderTools(
  ToolSet tools,
  ToolOrder? toolOrder,
  ToolSet? knownTools,
) {
  if (toolOrder == null) {
    return tools;
  }

  final knownToolNames = knownTools?.keys.toSet() ?? tools.keys.toSet();
  final unknownNames = toolOrder
      .where((toolName) => !knownToolNames.contains(toolName))
      .toSet()
      .toList(growable: false);
  if (unknownNames.isNotEmpty) {
    unknownNames.sort();
    throw ArgumentError.value(
      toolOrder,
      'toolOrder',
      'contains unknown tool names: ${unknownNames.join(', ')}',
    );
  }

  final orderedNames = <String>[];
  final orderedNameSet = <String>{};
  for (final toolName in toolOrder) {
    if (tools.containsKey(toolName) && orderedNameSet.add(toolName)) {
      orderedNames.add(toolName);
    }
  }

  final unorderedNames = tools.keys
      .where((toolName) => !orderedNameSet.contains(toolName))
      .toList(growable: false)
    ..sort();

  return Map<String, Tool>.unmodifiable({
    for (final toolName in [...orderedNames, ...unorderedNames])
      toolName: tools[toolName]!,
  });
}
