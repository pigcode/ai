import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

void main() {
  group('resolveProviderReference', () {
    test('returns the provider-specific identifier when the key exists', () {
      final result = resolveProviderReference(
        reference: const {'openai': 'file-abc', 'anthropic': 'file-xyz'},
        provider: 'openai',
      );

      expect(result, 'file-abc');
    });

    test('returns the correct identifier for a different provider', () {
      final result = resolveProviderReference(
        reference: const {'openai': 'file-abc', 'anthropic': 'file-xyz'},
        provider: 'anthropic',
      );

      expect(result, 'file-xyz');
    });

    test('throws NoSuchProviderReferenceError when the provider is missing',
        () {
      const reference = {'anthropic': 'file-xyz', 'google': 'file-123'};

      expect(
        () => resolveProviderReference(
          reference: reference,
          provider: 'openai',
        ),
        throwsA(
          isA<NoSuchProviderReferenceError>()
              .having((error) => error.provider, 'provider', 'openai')
              .having((error) => error.reference, 'reference', reference),
        ),
      );
    });

    test('throws NoSuchProviderReferenceError when the reference is empty', () {
      const reference = <String, String>{};

      expect(
        () => resolveProviderReference(
          reference: reference,
          provider: 'openai',
        ),
        throwsA(
          isA<NoSuchProviderReferenceError>()
              .having((error) => error.provider, 'provider', 'openai')
              .having((error) => error.reference, 'reference', reference),
        ),
      );
    });

    test('works with a single-provider reference', () {
      final result = resolveProviderReference(
        reference: const {'openai': 'file-only'},
        provider: 'openai',
      );

      expect(result, 'file-only');
    });
  });
}
