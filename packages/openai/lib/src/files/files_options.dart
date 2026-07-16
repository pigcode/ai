import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:equatable/equatable.dart';

/// `providerOptions['openai']` 的结构化值类(files wire 专用)。
final class OpenAiFilesProviderOptions with EquatableMixin {
  const OpenAiFilesProviderOptions({
    this.purpose,
    this.expiresAfter,
  });

  /// OpenAI files purpose。缺省由 provider 实现设为 `assistants`。
  final String? purpose;

  /// OpenAI `expires_after` 秒数。
  final int? expiresAfter;

  factory OpenAiFilesProviderOptions.fromProviderOptions(
    ProviderOptions? options,
  ) {
    final raw = options?['openai'];
    if (raw == null) {
      return const OpenAiFilesProviderOptions();
    }

    final validationResult = _validator.validate(raw);
    if (validationResult is ValidationFailure) {
      throw validationResult.error;
    }
    final value = (validationResult as ValidationSuccess).value! as JsonObject;

    return OpenAiFilesProviderOptions(
      purpose: value['purpose'] as String?,
      expiresAfter: value['expiresAfter'] as int?,
    );
  }

  @override
  List<Object?> get props => <Object?>[purpose, expiresAfter];
}

final JsonSchemaValidator _validator = JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'purpose': <String, Object?>{'type': 'string'},
      'expiresAfter': <String, Object?>{'type': 'integer'},
    },
    'additionalProperties': true,
  }),
);
