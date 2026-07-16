import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

void main() {
  group('withoutTrailingSlash', () {
    test('removes a single trailing slash', () {
      expect(
        withoutTrailingSlash('https://api.example.com/'),
        'https://api.example.com',
      );
    });

    test('leaves a url without a trailing slash unchanged', () {
      expect(
        withoutTrailingSlash('https://api.example.com'),
        'https://api.example.com',
      );
    });

    test('returns null when given null', () {
      expect(withoutTrailingSlash(null), isNull);
    });

    test('only removes exactly one trailing slash', () {
      expect(
        withoutTrailingSlash('https://api.example.com//'),
        'https://api.example.com/',
      );
    });
  });

  group('loadApiKey', () {
    test('returns the explicit value when provided', () {
      expect(
        loadApiKey(apiKey: 'sk-test', settingName: 'OPENAI_API_KEY'),
        'sk-test',
      );
    });

    test('throws LoadApiKeyError when missing', () {
      expect(
        () => loadApiKey(settingName: 'OPENAI_API_KEY'),
        throwsA(isA<LoadApiKeyError>()),
      );
    });
  });

  group('loadSetting', () {
    test('returns the explicit value when provided', () {
      expect(
        loadSetting(
            settingValue: 'https://api.example.com', settingName: 'baseURL'),
        'https://api.example.com',
      );
    });

    test('throws LoadSettingError when missing', () {
      expect(
        () => loadSetting(settingName: 'baseURL'),
        throwsA(isA<LoadSettingError>()),
      );
    });
  });

  group('loadOptionalSetting', () {
    test('returns the explicit value when provided', () {
      expect(loadOptionalSetting(settingValue: 'org-123'), 'org-123');
    });

    test('returns null when missing', () {
      expect(loadOptionalSetting(), isNull);
    });
  });
}
