import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../tool/tool.dart';

/// 当前步骤可供模型调用的工具名列表。
///
/// `null` 表示不限制工具;非空列表表示本步骤只广告这些工具。列表中的未知
/// 工具名会被忽略。
typedef ActiveTools = List<String>;

/// 根据 [activeTools] 过滤当前步骤可用工具。
ToolSet? filterActiveTools(ToolSet? tools, ActiveTools? activeTools) {
  if (tools == null || activeTools == null) {
    return tools;
  }
  final activeNames = activeTools.toSet();
  return Map<String, Tool>.unmodifiable(
    Map<String, Tool>.fromEntries(
      tools.entries.where((entry) => activeNames.contains(entry.key)),
    ),
  );
}

/// 过滤后已不可用的强制工具选择会让 provider 收到非法组合。
provider.ToolChoice? filterToolChoiceForTools(
  provider.ToolChoice? toolChoice,
  ToolSet? tools,
) {
  if (toolChoice is provider.ToolChoiceTool &&
      (tools == null || !tools.containsKey(toolChoice.toolName))) {
    return null;
  }
  return toolChoice;
}
