import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:equatable/equatable.dart';

/// `providerOptions['openai']` 的结构化值类(speech wire 专用)。
final class OpenAiSpeechProviderOptions with EquatableMixin {
  const OpenAiSpeechProviderOptions({this.instructions, this.speed});

  /// 语音生成指令。
  final String? instructions;

  /// 语速。
  final num? speed;

  factory OpenAiSpeechProviderOptions.fromProviderOptions(
    ProviderOptions? options,
  ) {
    final raw = options?['openai'];
    if (raw == null) {
      return const OpenAiSpeechProviderOptions();
    }

    final validationResult = _validator.validate(raw);
    if (validationResult is ValidationFailure) {
      throw validationResult.error;
    }
    final value = (validationResult as ValidationSuccess).value! as JsonObject;

    return OpenAiSpeechProviderOptions(
      instructions: value['instructions'] as String?,
      speed: value['speed'] as num?,
    );
  }

  @override
  List<Object?> get props => <Object?>[instructions, speed];
}

final JsonSchemaValidator _validator = JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'instructions': <String, Object?>{'type': 'string'},
      'speed': <String, Object?>{
        'type': 'number',
        'minimum': 0.25,
        'maximum': 4.0,
      },
    },
    'additionalProperties': true,
  }),
);
