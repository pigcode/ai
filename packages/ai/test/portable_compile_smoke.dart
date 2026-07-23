import 'package:pigcode_ai/pigcode_ai.dart';

void main() {
  const metadata = <String, JsonObject>{
    'portable': <String, Object?>{'compiled': true},
  };
  final surface = <Object?>[
    const Prompt(prompt: 'portable'),
    CancellationController().signal,
    metadata,
    isStepCount(1),
  ];
  if (surface.length != 4) {
    throw StateError('ai portable surface is incomplete');
  }
}
