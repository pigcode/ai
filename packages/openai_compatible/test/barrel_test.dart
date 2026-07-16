import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('barrel 导出完整性', () {
    test('createOpenAiCompatible 与 OpenAiCompatibleProvider 经 barrel 可达', () {
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
      );
      expect(provider, isA<OpenAiCompatibleProvider>());
      expect(provider, isA<Provider>());
    });

    test('OpenAiCompatibleChatLanguageModel 经 barrel 可直接构造', () {
      final config = OpenAiCompatibleChatConfig(
        providerName: 'mycustom',
        url: (path) => Uri.parse('https://api.example.com/v1$path'),
        headers: () => const {},
      );
      final model = OpenAiCompatibleChatLanguageModel('m1', config: config);
      expect(model.provider, 'mycustom.chat');
      expect(model, isA<LanguageModel>());
    });

    test('OpenAiCompatibleChatProviderOptions.fromProviderOptions 经 barrel 可达',
        () {
      final options = OpenAiCompatibleChatProviderOptions.fromProviderOptions(
        null,
        providerOptionsName: 'mycustom',
      );
      expect(options, isA<OpenAiCompatibleChatProviderOptions>());
    });

    test('defaultOpenAiCompatibleErrorStructure 经 barrel 可达', () {
      expect(
        defaultOpenAiCompatibleErrorStructure,
        isA<ProviderErrorStructure>(),
      );
    });

    test('mapOpenAiCompatibleFinishReason 经 barrel 可达', () {
      expect(
        mapOpenAiCompatibleFinishReason('stop'),
        isA<LanguageModelFinishReason>(),
      );
    });

    test('convertOpenAiCompatibleChatUsage 经 barrel 可达', () {
      expect(convertOpenAiCompatibleChatUsage(null), isA<LanguageModelUsage>());
    });

    test('prepareOpenAiCompatibleTools 经 barrel 可达', () {
      final result = prepareOpenAiCompatibleTools(tools: null);
      expect(result, isA<OpenAiCompatibleToolsResult>());
    });
  });
}
