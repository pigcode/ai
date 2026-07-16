import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:equatable/equatable.dart';

/// `providerOptions['openai']` 的结构化值类(transcription wire 专用)。
final class OpenAiTranscriptionProviderOptions with EquatableMixin {
  const OpenAiTranscriptionProviderOptions({
    this.include,
    this.language,
    this.prompt,
    this.temperature,
    this.timestampGranularities,
    this.streaming,
  });

  /// 额外包含的响应字段。
  final List<String>? include;

  /// 输入音频语言,ISO-639-1。
  final String? language;

  /// 用于引导模型风格或延续前文的提示。
  final String? prompt;

  /// 采样温度。
  final num? temperature;

  /// 时间戳粒度,如 `word` 或 `segment`。
  final List<String>? timestampGranularities;

  /// realtime transcription 专用选项。
  final OpenAiTranscriptionStreamingOptions? streaming;

  factory OpenAiTranscriptionProviderOptions.fromProviderOptions(
    ProviderOptions? options,
  ) {
    final raw = options?['openai'];
    if (raw == null) {
      return const OpenAiTranscriptionProviderOptions();
    }

    final validationResult = _validator.validate(raw);
    if (validationResult is ValidationFailure) {
      throw validationResult.error;
    }
    final value = (validationResult as ValidationSuccess).value! as JsonObject;

    return OpenAiTranscriptionProviderOptions(
      include: (value['include'] as List<Object?>?)
          ?.map((item) => item! as String)
          .toList(),
      language: value['language'] as String?,
      prompt: value['prompt'] as String?,
      temperature: value['temperature'] as num?,
      timestampGranularities:
          (value['timestampGranularities'] as List<Object?>?)
              ?.map((item) => item! as String)
              .toList(),
      streaming: switch (value['streaming']) {
        final JsonObject streaming => OpenAiTranscriptionStreamingOptions(
            delay: streaming['delay'] as String?,
            include: (streaming['include'] as List<Object?>?)
                ?.map((item) => item! as String)
                .toList(),
          ),
        null => null,
        _ => throw StateError('validated streaming has unexpected shape'),
      },
    );
  }

  @override
  List<Object?> get props => <Object?>[
        include,
        language,
        prompt,
        temperature,
        timestampGranularities,
        streaming,
      ];
}

/// OpenAI realtime transcription streaming options.
final class OpenAiTranscriptionStreamingOptions with EquatableMixin {
  const OpenAiTranscriptionStreamingOptions({
    this.delay,
    this.include,
  });

  /// Latency/accuracy tradeoff.
  final String? delay;

  /// Additional fields to include in realtime events.
  final List<String>? include;

  @override
  List<Object?> get props => <Object?>[delay, include];
}

final JsonSchemaValidator _validator = JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'include': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
      'language': <String, Object?>{'type': 'string'},
      'prompt': <String, Object?>{'type': 'string'},
      'temperature': <String, Object?>{'type': 'number'},
      'timestampGranularities': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{
          'enum': <Object?>['word', 'segment'],
        },
      },
      'streaming': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'delay': <String, Object?>{
            'enum': <Object?>['minimal', 'low', 'medium', 'high', 'xhigh'],
          },
          'include': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
          },
        },
        'additionalProperties': true,
      },
    },
    'additionalProperties': true,
  }),
);
