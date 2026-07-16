import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:equatable/equatable.dart';

/// Creates the Anthropic Messages API `advisor_20260301` provider tool.
ProviderTool advisor_20260301({
  required String model,
  num? maxUses,
  AnthropicAdvisorCaching? caching,
}) {
  final args = <String, Object?>{
    'model': model,
    'maxUses': maxUses,
    'caching': caching?.toJson(),
  }..removeWhere((_, value) => value == null);

  return ProviderTool(
    id: 'anthropic.advisor_20260301',
    name: 'advisor',
    args: args,
    // provider 工具自动续接标注(:123)。
    supportsDeferredResults: true,
  );
}

/// Ephemeral prompt-cache configuration for the Anthropic `advisor` tool.
final class AnthropicAdvisorCaching extends Equatable {
  const AnthropicAdvisorCaching({required this.ttl});

  /// Cache time-to-live: `'5m'` or `'1h'`.
  final String ttl;

  /// Serializes this cache configuration to provider-tool arguments.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'ephemeral',
      'ttl': ttl,
    };
  }

  @override
  List<Object?> get props => [ttl];
}
