import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('barrel 导出完整性', () {
    test('createOpenAi 与 OpenAiProvider 经 barrel 可达', () {
      final provider = createOpenAi(apiKey: 'sk-test');
      expect(provider, isA<OpenAiProvider>());
      expect(provider, isA<Provider>());
    });

    test('OpenAiChatLanguageModel 经 barrel 可直接构造', () {
      final config = OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        headers: () => const {},
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: config);
      expect(model.provider, 'openai.chat');
      expect(model, isA<LanguageModel>());
    });

    test('OpenAiResponsesLanguageModel 经 barrel 可直接构造', () {
      final config = OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        headers: () => const {},
      );
      final model = OpenAiResponsesLanguageModel('gpt-4o', config: config);
      expect(model.provider, 'openai.responses');
      expect(model, isA<LanguageModel>());
    });

    test('OpenAiChatProviderOptions.fromProviderOptions 经 barrel 可达', () {
      final options = OpenAiChatProviderOptions.fromProviderOptions(null);
      expect(options, isA<OpenAiChatProviderOptions>());
    });

    test('OpenAiResponsesProviderOptions.fromProviderOptions 经 barrel 可达', () {
      final options = OpenAiResponsesProviderOptions.fromProviderOptions(null);
      expect(options, isA<OpenAiResponsesProviderOptions>());
    });

    test('getOpenAiLanguageModelCapabilities 经 barrel 可达', () {
      final capabilities = getOpenAiLanguageModelCapabilities('gpt-4o');
      expect(capabilities, isA<OpenAiLanguageModelCapabilities>());
    });

    test('OpenAiImageModel 经 barrel 可直接构造', () {
      final config = OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        headers: () => const {},
      );
      final model = OpenAiImageModel('gpt-image-1', config: config);
      expect(model.provider, 'openai.image');
      expect(model, isA<ImageModel>());
    });

    test('OpenAiSpeechModel 经 barrel 可直接构造', () {
      final config = OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        headers: () => const {},
      );
      final model = OpenAiSpeechModel('tts-1', config: config);
      expect(model.provider, 'openai.speech');
      expect(model, isA<SpeechModel>());
    });

    test('OpenAiFiles 经 barrel 可直接构造', () {
      final config = OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        headers: () => const {},
      );
      final files = OpenAiFiles(config: config);
      expect(files.provider, 'openai.files');
      expect(files, isA<Files>());
    });

    test('OpenAiSkills 经 barrel 可直接构造', () {
      final config = OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        headers: () => const {},
      );
      final skills = OpenAiSkills(config: config);
      expect(skills.provider, 'openai.skills');
      expect(skills, isA<Skills>());
    });
  });
}
