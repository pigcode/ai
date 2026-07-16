import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:equatable/equatable.dart';

/// Creates the Anthropic Messages API `web_fetch_20250910` provider tool.
ProviderTool webFetch_20250910({
  int? maxUses,
  List<String>? allowedDomains,
  List<String>? blockedDomains,
  AnthropicWebFetchCitations? citations,
  int? maxContentTokens,
}) {
  final args = <String, Object?>{
    'maxUses': maxUses,
    'allowedDomains': allowedDomains,
    'blockedDomains': blockedDomains,
    'citations': citations?.toJson(),
    'maxContentTokens': maxContentTokens,
  }..removeWhere((_, value) => value == null);

  return ProviderTool(
    id: 'anthropic.web_fetch_20250910',
    name: 'web_fetch',
    args: args,
    // provider 工具自动续接标注(:138)。
    supportsDeferredResults: true,
  );
}

/// Creates the Anthropic Messages API `web_fetch_20260209` provider tool.
ProviderTool webFetch_20260209({
  int? maxUses,
  List<String>? allowedDomains,
  List<String>? blockedDomains,
  AnthropicWebFetchCitations? citations,
  int? maxContentTokens,
}) {
  final args = <String, Object?>{
    'maxUses': maxUses,
    'allowedDomains': allowedDomains,
    'blockedDomains': blockedDomains,
    'citations': citations?.toJson(),
    'maxContentTokens': maxContentTokens,
  }..removeWhere((_, value) => value == null);

  return ProviderTool(
    id: 'anthropic.web_fetch_20260209',
    name: 'web_fetch',
    args: args,
    // provider 工具自动续接标注(:138)。
    supportsDeferredResults: true,
  );
}

/// Citation options for the Anthropic `web_fetch` tool.
final class AnthropicWebFetchCitations extends Equatable {
  const AnthropicWebFetchCitations({required this.enabled});

  /// Whether citations are enabled for fetched documents.
  final bool enabled;

  /// Serializes these citation options to provider-tool arguments.
  Map<String, Object?> toJson() => {'enabled': enabled};

  @override
  List<Object?> get props => [enabled];
}
