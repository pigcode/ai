import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';

void main() {
  final provider = createOpenAiCompatible(
    name: 'portable',
    baseUrl: 'https://example.invalid/v1',
  );
  final surface = <Object?>[
    provider,
    provider.languageModel('portable-model'),
    mapOpenAiCompatibleFinishReason('stop'),
  ];
  if (surface.length != 3) {
    throw StateError('openai_compatible portable surface is incomplete');
  }
}
