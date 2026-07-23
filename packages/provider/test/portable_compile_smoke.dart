import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

void main() {
  const metadata = <String, JsonObject>{
    'portable': <String, Object?>{'compiled': true},
  };
  final controller = CancellationController();
  final surface = <Object?>[
    metadata,
    controller.signal,
    const LanguageModelFinishReason(FinishReasonType.stop),
  ];
  if (surface.length != 3) {
    throw StateError('provider portable surface is incomplete');
  }
}
