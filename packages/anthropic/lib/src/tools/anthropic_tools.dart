// 契约类型直接从契约包 import(包内惯例);禁止 src 内部文件反向 import 公共
// barrel(barrel 又 export 本文件,会成循环依赖)。
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

import 'advisor.dart' as advisor;
import 'bash.dart' as bash;
import 'code_execution.dart' as code_execution;
import 'computer.dart' as computer;
import 'memory.dart' as memory;
import 'text_editor.dart' as text_editor;
import 'tool_search.dart' as tool_search;
import 'web_fetch.dart' as web_fetch;
import 'web_search.dart' as web_search;

/// Anthropic provider-executed tool factories 聚合入口。
const anthropicTools = AnthropicTools();

/// Anthropic provider-executed tool factories 聚合类。
final class AnthropicTools {
  const AnthropicTools();

  /// Creates the Anthropic Messages API `web_search_20250305` provider tool.
  ProviderTool webSearch_20250305({
    int? maxUses,
    List<String>? allowedDomains,
    List<String>? blockedDomains,
    web_search.AnthropicWebSearchUserLocation? userLocation,
  }) =>
      web_search.webSearch_20250305(
        maxUses: maxUses,
        allowedDomains: allowedDomains,
        blockedDomains: blockedDomains,
        userLocation: userLocation,
      );

  /// Creates the Anthropic Messages API `web_search_20260209` provider tool.
  ProviderTool webSearch_20260209({
    int? maxUses,
    List<String>? allowedDomains,
    List<String>? blockedDomains,
    web_search.AnthropicWebSearchUserLocation? userLocation,
  }) =>
      web_search.webSearch_20260209(
        maxUses: maxUses,
        allowedDomains: allowedDomains,
        blockedDomains: blockedDomains,
        userLocation: userLocation,
      );

  /// Creates the Anthropic Messages API `web_fetch_20250910` provider tool.
  ProviderTool webFetch_20250910({
    int? maxUses,
    List<String>? allowedDomains,
    List<String>? blockedDomains,
    web_fetch.AnthropicWebFetchCitations? citations,
    int? maxContentTokens,
  }) =>
      web_fetch.webFetch_20250910(
        maxUses: maxUses,
        allowedDomains: allowedDomains,
        blockedDomains: blockedDomains,
        citations: citations,
        maxContentTokens: maxContentTokens,
      );

  /// Creates the Anthropic Messages API `web_fetch_20260209` provider tool.
  ProviderTool webFetch_20260209({
    int? maxUses,
    List<String>? allowedDomains,
    List<String>? blockedDomains,
    web_fetch.AnthropicWebFetchCitations? citations,
    int? maxContentTokens,
  }) =>
      web_fetch.webFetch_20260209(
        maxUses: maxUses,
        allowedDomains: allowedDomains,
        blockedDomains: blockedDomains,
        citations: citations,
        maxContentTokens: maxContentTokens,
      );

  /// Creates the Anthropic Messages API `computer_20241022` provider tool.
  ProviderTool computer_20241022({
    required int displayWidthPx,
    required int displayHeightPx,
    int? displayNumber,
  }) =>
      computer.computer_20241022(
        displayWidthPx: displayWidthPx,
        displayHeightPx: displayHeightPx,
        displayNumber: displayNumber,
      );

  /// Creates the Anthropic Messages API `computer_20250124` provider tool.
  ProviderTool computer_20250124({
    required int displayWidthPx,
    required int displayHeightPx,
    int? displayNumber,
  }) =>
      computer.computer_20250124(
        displayWidthPx: displayWidthPx,
        displayHeightPx: displayHeightPx,
        displayNumber: displayNumber,
      );

  /// Creates the Anthropic Messages API `computer_20251124` provider tool.
  ProviderTool computer_20251124({
    required int displayWidthPx,
    required int displayHeightPx,
    int? displayNumber,
    bool? enableZoom,
  }) =>
      computer.computer_20251124(
        displayWidthPx: displayWidthPx,
        displayHeightPx: displayHeightPx,
        displayNumber: displayNumber,
        enableZoom: enableZoom,
      );

  /// Creates the Anthropic Messages API `text_editor_20241022` provider tool.
  ProviderTool textEditor_20241022() => text_editor.textEditor_20241022();

  /// Creates the Anthropic Messages API `text_editor_20250124` provider tool.
  ProviderTool textEditor_20250124() => text_editor.textEditor_20250124();

  /// Creates the Anthropic Messages API `text_editor_20250728` provider tool.
  ProviderTool textEditor_20250728({int? maxCharacters}) =>
      text_editor.textEditor_20250728(maxCharacters: maxCharacters);

  /// Creates the Anthropic Messages API `bash_20241022` provider tool.
  ProviderTool bash_20241022() => bash.bash_20241022();

  /// Creates the Anthropic Messages API `bash_20250124` provider tool.
  ProviderTool bash_20250124() => bash.bash_20250124();

  /// Creates the Anthropic Messages API `code_execution_20250522` provider
  /// tool.
  ProviderTool codeExecution_20250522() =>
      code_execution.codeExecution_20250522();

  /// Creates the Anthropic Messages API `code_execution_20250825` provider
  /// tool.
  ProviderTool codeExecution_20250825() =>
      code_execution.codeExecution_20250825();

  /// Creates the Anthropic Messages API `code_execution_20260120` provider
  /// tool.
  ProviderTool codeExecution_20260120() =>
      code_execution.codeExecution_20260120();

  /// Creates the Anthropic Messages API `memory_20250818` provider tool.
  ProviderTool memory_20250818() => memory.memory_20250818();

  /// Creates the Anthropic Messages API `tool_search_tool_regex_20251119`
  /// provider tool.
  ProviderTool toolSearchRegex_20251119() =>
      tool_search.toolSearchRegex_20251119();

  /// Creates the Anthropic Messages API `tool_search_tool_bm25_20251119`
  /// provider tool.
  ProviderTool toolSearchBm25_20251119() =>
      tool_search.toolSearchBm25_20251119();

  /// Creates the Anthropic Messages API `advisor_20260301` provider tool.
  ProviderTool advisor_20260301({
    required String model,
    num? maxUses,
    advisor.AnthropicAdvisorCaching? caching,
  }) =>
      advisor.advisor_20260301(
        model: model,
        maxUses: maxUses,
        caching: caching,
      );
}
