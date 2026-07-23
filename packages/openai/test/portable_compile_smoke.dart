import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';

void main() {
  final provider = createOpenAi(apiKey: 'portable-test-key');
  final surface = <Object?>[
    provider,
    provider.languageModel('gpt-4o-mini'),
    getOpenAiLanguageModelCapabilities('gpt-4o-mini'),
  ];
  if (surface.length != 3) {
    throw StateError('openai portable surface is incomplete');
  }
}
