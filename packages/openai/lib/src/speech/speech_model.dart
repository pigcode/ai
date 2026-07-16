import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import '../internal/config.dart';
import '../internal/error.dart';
import '../internal/provider_options.dart';
import 'speech_options.dart';

/// OpenAI Audio Speech(`/audio/speech`)的 [SpeechModel] 实现。
final class OpenAiSpeechModel implements SpeechModel {
  OpenAiSpeechModel(this.modelId, {required this.config});

  @override
  final String modelId;

  /// 共享的 provider 配置(baseUrl/headers/client)。
  final OpenAiConfig config;

  @override
  String get specificationVersion => speechModelSpecVersion;

  @override
  String get provider => '${config.providerName}.speech';

  Uri get _requestUrl => Uri.parse('${config.baseUrl}/audio/speech');

  @override
  Future<SpeechModelResult> doGenerate(SpeechModelCallOptions options) async {
    final openAiOptions = OpenAiSpeechProviderOptions.fromProviderOptions(
      resolveOpenAiProviderOptions(
          config.providerName, options.providerOptions),
    );
    final warnings = <Warning>[];

    var responseFormat = 'mp3';
    final outputFormat = options.outputFormat;
    if (outputFormat != null) {
      if (_supportedOutputFormats.contains(outputFormat)) {
        responseFormat = outputFormat;
      } else {
        warnings.add(
          UnsupportedWarning(
            'outputFormat',
            details: 'Unsupported output format: $outputFormat. '
                'Using mp3 instead.',
          ),
        );
      }
    }

    if (options.language != null) {
      warnings.add(
        UnsupportedWarning(
          'language',
          details: 'OpenAI speech models do not support language selection. '
              'Language parameter "${options.language}" was ignored.',
        ),
      );
    }

    final instructions = options.instructions ?? openAiOptions.instructions;
    if (instructions != null && _legacyTtsModels.contains(modelId)) {
      warnings.add(
        UnsupportedWarning(
          'instructions',
          details: 'OpenAI speech model "$modelId" does not support '
              'instructions. The instructions parameter was ignored.',
        ),
      );
    }

    final body = <String, Object?>{
      'model': modelId,
      'input': options.text,
      'voice': options.voice ?? 'alloy',
      'response_format': responseFormat,
      'speed': options.speed ?? openAiOptions.speed,
      if (!_legacyTtsModels.contains(modelId)) 'instructions': instructions,
    }..removeWhere((_, value) => value == null);

    Map<String, String>? responseHeaders;
    final audio = await postJsonToApi<Uint8List>(
      url: _requestUrl,
      headers: combineHeaders([config.headers(), options.headers]),
      body: body,
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return ctx.response.stream.toBytes();
      },
      failureHandler: openAiFailedResponseHandler(),
      client: config.client,
      cancellation: options.cancellation,
    );

    return SpeechModelResult(
      audio: audio,
      format: responseFormat,
      warnings: warnings,
      request: RequestInfo(body: jsonEncode(body)),
      response: ResponseInfo(
        timestamp: DateTime.now(),
        modelId: modelId,
        headers: responseHeaders,
        body: audio,
      ),
    );
  }
}

const _legacyTtsModels = <String>{'tts-1', 'tts-1-hd'};

const _supportedOutputFormats = <String>{
  'mp3',
  'opus',
  'aac',
  'flac',
  'wav',
  'pcm',
};
