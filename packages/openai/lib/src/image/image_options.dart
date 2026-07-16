import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:equatable/equatable.dart';

/// `providerOptions['openai']` 的结构化值类(image generation wire 专用)。
final class OpenAiImageProviderOptions with EquatableMixin {
  const OpenAiImageProviderOptions({
    this.quality,
    this.style,
    this.background,
    this.moderation,
    this.outputFormat,
    this.outputCompression,
    this.inputFidelity,
    this.user,
  });

  /// 图片质量。
  final String? quality;

  /// 图片风格。
  final String? style;

  /// 背景行为。
  final String? background;

  /// 内容审核强度。
  final String? moderation;

  /// 输出图片格式。
  final String? outputFormat;

  /// 输出压缩等级(0-100)。
  final int? outputCompression;

  /// 编辑输出与输入图的一致性。
  final String? inputFidelity;

  /// 终端用户标识。
  final String? user;

  factory OpenAiImageProviderOptions.fromProviderOptions(
    ProviderOptions? options,
  ) {
    final raw = options?['openai'];
    if (raw == null) {
      return const OpenAiImageProviderOptions();
    }

    final validationResult = _validator.validate(raw);
    if (validationResult is ValidationFailure) {
      throw validationResult.error;
    }
    final value = (validationResult as ValidationSuccess).value! as JsonObject;

    return OpenAiImageProviderOptions(
      quality: value['quality'] as String?,
      style: value['style'] as String?,
      background: value['background'] as String?,
      moderation: value['moderation'] as String?,
      outputFormat: value['outputFormat'] as String?,
      outputCompression: value['outputCompression'] as int?,
      inputFidelity: value['inputFidelity'] as String?,
      user: value['user'] as String?,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        quality,
        style,
        background,
        moderation,
        outputFormat,
        outputCompression,
        inputFidelity,
        user,
      ];
}

final JsonSchemaValidator _validator = JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'quality': <String, Object?>{
        'enum': <Object?>['standard', 'hd', 'low', 'medium', 'high', 'auto'],
      },
      'style': <String, Object?>{
        'enum': <Object?>['vivid', 'natural'],
      },
      'background': <String, Object?>{
        'enum': <Object?>['transparent', 'opaque', 'auto'],
      },
      'moderation': <String, Object?>{
        'enum': <Object?>['auto', 'low'],
      },
      'outputFormat': <String, Object?>{
        'enum': <Object?>['png', 'jpeg', 'webp'],
      },
      'outputCompression': <String, Object?>{
        'type': 'integer',
        'minimum': 0,
        'maximum': 100,
      },
      'inputFidelity': <String, Object?>{
        'enum': <Object?>['high', 'low'],
      },
      'user': <String, Object?>{'type': 'string'},
    },
    'additionalProperties': true,
  }),
);
