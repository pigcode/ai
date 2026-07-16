import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('AnthropicConfig', () {
    test('exposes providerName/baseUrl/headers/client as constructed', () {
      final client = http.Client();
      addTearDown(client.close);

      Map<String, String> headers() => <String, String>{
            'x-api-key': 'sk-test',
          };

      final config = AnthropicConfig(
        providerName: 'anthropic.messages',
        baseUrl: 'https://api.anthropic.com/v1',
        headers: headers,
        client: client,
      );

      expect(config.providerName, 'anthropic.messages');
      expect(config.baseUrl, 'https://api.anthropic.com/v1');
      expect(config.headers(), <String, String>{'x-api-key': 'sk-test'});
      expect(config.client, same(client));
    });

    test('client is optional and defaults to null', () {
      final config = AnthropicConfig(
        providerName: 'anthropic.messages',
        baseUrl: 'https://api.anthropic.com/v1',
        headers: () => const <String, String>{},
      );

      expect(config.client, isNull);
    });

    test('headers is evaluated per call, not cached at construction', () {
      var callCount = 0;
      final config = AnthropicConfig(
        providerName: 'anthropic.messages',
        baseUrl: 'https://api.anthropic.com/v1',
        headers: () {
          callCount += 1;
          return <String, String>{'X-Call-Count': '$callCount'};
        },
      );

      expect(config.headers(), <String, String>{'X-Call-Count': '1'});
      expect(config.headers(), <String, String>{'X-Call-Count': '2'});
      expect(callCount, 2);
    });
  });

  group('resolveAnthropicBaseUrl', () {
    test('null falls back to the default versioned URL', () {
      expect(
        resolveAnthropicBaseUrl(null),
        'https://api.anthropic.com/v1',
      );
    });

    test('bare official host gets /v1 appended', () {
      expect(
        resolveAnthropicBaseUrl('https://api.anthropic.com'),
        'https://api.anthropic.com/v1',
      );
    });

    test('trailing slash is stripped before the exact-match check', () {
      expect(
        resolveAnthropicBaseUrl('https://api.anthropic.com/'),
        'https://api.anthropic.com/v1',
      );
    });

    test('custom base URL only loses its trailing slash, no /v1 appended', () {
      expect(
        resolveAnthropicBaseUrl('https://proxy.example.com/anthropic/'),
        'https://proxy.example.com/anthropic',
      );
    });

    test('http variant of the official host is not exact-matched', () {
      expect(
        resolveAnthropicBaseUrl('http://api.anthropic.com'),
        'http://api.anthropic.com',
      );
    });
  });

  group('beta header helpers', () {
    test('anthropicBetasFromHeaderValue(null) is an empty set', () {
      expect(anthropicBetasFromHeaderValue(null), isEmpty);
    });

    test('splits on commas, trims, lowercases, drops empties, dedupes', () {
      expect(
        anthropicBetasFromHeaderValue('Files-API-2025-04-14, foo ,, BAR'),
        <String>{'files-api-2025-04-14', 'foo', 'bar'},
      );
    });

    test('anthropicBetaHeader with an empty set emits no header', () {
      expect(anthropicBetaHeader(<String>{}), isEmpty);
    });

    test('anthropicBetaHeader joins with commas and no spaces', () {
      expect(
        anthropicBetaHeader(<String>{'a', 'b'}),
        <String, String>{'anthropic-beta': 'a,b'},
      );
    });

    test('header name and version constants match the wire values', () {
      expect(anthropicBetaHeaderName, 'anthropic-beta');
      expect(anthropicVersionHeaderValue, '2023-06-01');
    });
  });

  group('anthropicSupportedUrls', () {
    test('declares exactly image/* and application/pdf over http(s)', () {
      final supportedUrls = anthropicSupportedUrls();

      expect(
        supportedUrls.keys,
        unorderedEquals(<String>['image/*', 'application/pdf']),
      );
      for (final patterns in supportedUrls.values) {
        expect(patterns, hasLength(1));
        expect(patterns.single.hasMatch('https://example.com/a.png'), isTrue);
        expect(patterns.single.hasMatch('ftp://x'), isFalse);
      }
    });
  });
}
