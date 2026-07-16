import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// Resolves [reference] to the provider-specific identifier for [provider].
///
/// Throws [NoSuchProviderReferenceError] when [reference] has no entry for
/// [provider].
String resolveProviderReference({
  required ProviderReference reference,
  required String provider,
}) {
  final id = reference[provider];
  if (id != null) {
    return id;
  }

  throw NoSuchProviderReferenceError(
    provider: provider,
    reference: reference,
  );
}
