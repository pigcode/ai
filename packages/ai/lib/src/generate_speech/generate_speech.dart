import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../logger/log_warnings.dart';

/// `generateSpeech` 的结果。
final class SpeechResult {
  const SpeechResult({
    required this.audio,
    required this.mediaType,
    required this.format,
    required this.warnings,
    required this.responses,
    required this.providerMetadata,
  });

  /// 生成出的音频原始字节。
  final Uint8List audio;

  /// 音频媒体类型,如 `audio/mp3`。
  final String mediaType;

  /// 音频格式,如 `mp3`。
  final String format;

  /// provider 侧告警。
  final List<provider.Warning> warnings;

  /// provider 响应元数据。
  final List<provider.ResponseInfo> responses;

  /// provider 私有元数据。
  final provider.ProviderMetadata providerMetadata;
}

/// 用给定 speech [model] 把 [text] 转成语音音频。
Future<SpeechResult> generateSpeech({
  required provider.SpeechModel model,
  required String text,
  String? voice,
  String? outputFormat,
  String? instructions,
  num? speed,
  String? language,
  provider.ProviderOptions? providerOptions,
  Map<String, String>? headers,
  provider.CancellationSignal? cancellation,
}) async {
  final modelResponse = await model.doGenerate(
    provider.SpeechModelCallOptions(
      text: text,
      voice: voice,
      outputFormat: outputFormat,
      instructions: instructions,
      speed: speed,
      language: language,
      headers: headers,
      providerOptions: providerOptions,
      cancellation: cancellation,
    ),
  );
  logWarnings(
    warnings: modelResponse.warnings,
    provider: model.provider,
    model: model.modelId,
  );

  final response = modelResponse.response;
  if (modelResponse.audio.isEmpty) {
    throw provider.NoSpeechGeneratedError(
      responses: response == null ? const [] : [response],
    );
  }

  final format =
      _audioFormat(modelResponse.format ?? outputFormat, response?.headers);
  return SpeechResult(
    audio: modelResponse.audio,
    mediaType: _audioMediaType(format, response?.headers),
    format: format,
    warnings: modelResponse.warnings,
    responses: response == null ? const [] : [response],
    providerMetadata: modelResponse.providerMetadata ?? const {},
  );
}

String _audioFormat(String? outputFormat, provider.Headers? headers) {
  final contentType = _audioContentType(headers);
  if (contentType != null) {
    final subtype = contentType.split('/').last;
    if (subtype.isNotEmpty) {
      return subtype == 'mpeg' ? 'mp3' : subtype;
    }
  }
  return outputFormat ?? 'mp3';
}

String _audioMediaType(String format, provider.Headers? headers) {
  final contentType = _audioContentType(headers);
  if (contentType != null) {
    return contentType;
  }
  return format == 'mp3' ? 'audio/mp3' : 'audio/$format';
}

String? _audioContentType(provider.Headers? headers) {
  final contentType = _headerValue(headers, 'content-type');
  if (contentType == null) {
    return null;
  }

  final type = contentType.split(';').first.trim().toLowerCase();
  return type.startsWith('audio/') ? type : null;
}

String? _headerValue(provider.Headers? headers, String name) {
  if (headers == null) {
    return null;
  }

  final normalizedName = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == normalizedName) {
      return entry.value;
    }
  }
  return null;
}
