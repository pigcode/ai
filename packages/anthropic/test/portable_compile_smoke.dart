import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';

void main() {
  final provider = createAnthropic(apiKey: 'portable-test-key');
  final surface = <Object?>[
    provider,
    provider.languageModel('claude-sonnet-4-5'),
    getAnthropicModelCapabilities('claude-sonnet-4-5'),
  ];
  if (surface.length != 3) {
    throw StateError('anthropic portable surface is incomplete');
  }
}
