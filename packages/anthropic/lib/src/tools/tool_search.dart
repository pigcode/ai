import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// Creates the Anthropic Messages API `tool_search_tool_regex_20251119`
/// provider tool.
///
/// pigcode 工厂/`ProviderTool.id` 用 `tool_search_regex_20251119`(无中间
/// `tool`);wire 请求体的 `type`/`name` 字段才带 `tool_search_tool_...`
/// 前缀(报告 09 §1.5,prepare_tools 分派时勿混淆两者)。
ProviderTool toolSearchRegex_20251119() {
  return const ProviderTool(
    id: 'anthropic.tool_search_regex_20251119',
    name: 'tool_search_tool_regex',
    args: <String, Object?>{},
    // provider 工具自动续接标注(:79)。
    supportsDeferredResults: true,
  );
}

/// Creates the Anthropic Messages API `tool_search_tool_bm25_20251119`
/// provider tool.
///
/// pigcode 工厂/`ProviderTool.id` 用 `tool_search_bm25_20251119`(无中间
/// `tool`);wire 请求体的 `type`/`name` 字段才带 `tool_search_tool_...`
/// 前缀(报告 09 §1.6,prepare_tools 分派时勿混淆两者)。
ProviderTool toolSearchBm25_20251119() {
  return const ProviderTool(
    id: 'anthropic.tool_search_bm25_20251119',
    name: 'tool_search_tool_bm25',
    args: <String, Object?>{},
    // provider 工具自动续接标注(:67)。
    supportsDeferredResults: true,
  );
}
