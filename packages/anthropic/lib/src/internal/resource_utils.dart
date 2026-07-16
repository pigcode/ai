import 'config.dart';

Map<String, String> anthropicResourceHeaders(
  Map<String, String> headers,
  Iterable<String> requiredBetas,
) {
  final betas = <String>{...requiredBetas};
  final result = <String, String>{};
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == anthropicBetaHeaderName) {
      betas.addAll(anthropicBetasFromHeaderValue(entry.value));
    } else {
      result[entry.key] = entry.value;
    }
  }
  result.addAll(anthropicBetaHeader(betas));
  return result;
}

String anthropicResourceProviderName(String providerName, String resource) {
  const messagesSuffix = '.messages';
  final prefix = providerName.endsWith(messagesSuffix)
      ? providerName.substring(0, providerName.length - messagesSuffix.length)
      : providerName;
  return '$prefix.$resource';
}
