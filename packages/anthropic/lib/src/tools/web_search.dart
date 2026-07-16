import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:equatable/equatable.dart';

/// Creates the Anthropic Messages API `web_search_20250305` provider tool.
ProviderTool webSearch_20250305({
  int? maxUses,
  List<String>? allowedDomains,
  List<String>? blockedDomains,
  AnthropicWebSearchUserLocation? userLocation,
}) {
  final args = <String, Object?>{
    'maxUses': maxUses,
    'allowedDomains': allowedDomains,
    'blockedDomains': blockedDomains,
    'userLocation': userLocation?.toJson(),
  }..removeWhere((_, value) => value == null);

  return ProviderTool(
    id: 'anthropic.web_search_20250305',
    name: 'web_search',
    args: args,
    // provider 工具自动续接标注(:129)。
    supportsDeferredResults: true,
  );
}

/// Creates the Anthropic Messages API `web_search_20260209` provider tool.
ProviderTool webSearch_20260209({
  int? maxUses,
  List<String>? allowedDomains,
  List<String>? blockedDomains,
  AnthropicWebSearchUserLocation? userLocation,
}) {
  final args = <String, Object?>{
    'maxUses': maxUses,
    'allowedDomains': allowedDomains,
    'blockedDomains': blockedDomains,
    'userLocation': userLocation?.toJson(),
  }..removeWhere((_, value) => value == null);

  return ProviderTool(
    id: 'anthropic.web_search_20260209',
    name: 'web_search',
    args: args,
    // provider 工具自动续接标注(:129)。
    supportsDeferredResults: true,
  );
}

/// Approximate user location for geographically relevant Anthropic web
/// search.
final class AnthropicWebSearchUserLocation extends Equatable {
  const AnthropicWebSearchUserLocation({
    this.city,
    this.region,
    this.country,
    this.timezone,
  });

  /// City name.
  final String? city;

  /// Region name.
  final String? region;

  /// Two-letter ISO country code, for example `US`.
  final String? country;

  /// IANA timezone, for example `America/Los_Angeles`.
  final String? timezone;

  /// Serializes this location to provider-tool arguments.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'approximate',
      'city': city,
      'region': region,
      'country': country,
      'timezone': timezone,
    }..removeWhere((_, value) => value == null);
  }

  @override
  List<Object?> get props => [city, region, country, timezone];
}
