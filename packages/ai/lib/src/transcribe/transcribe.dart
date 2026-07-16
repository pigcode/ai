import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../logger/log_warnings.dart';
import '../prompt/content_part.dart';

/// `transcribe` 的结果。
final class TranscriptionResult {
  const TranscriptionResult({
    required this.text,
    required this.segments,
    this.language,
    this.durationInSeconds,
    required this.warnings,
    required this.responses,
    required this.providerMetadata,
  });

  /// 完整 transcript 文本。
  final String text;

  /// transcript 分段。
  final List<provider.TranscriptionSegment> segments;

  /// 识别出的语言代码,如 `en`。
  final String? language;

  /// 音频总时长(秒)。
  final double? durationInSeconds;

  /// provider 侧告警。
  final List<provider.Warning> warnings;

  /// provider 响应元数据。
  final List<provider.ResponseInfo> responses;

  /// provider 私有元数据。
  final provider.ProviderMetadata providerMetadata;
}

/// 用给定 transcription [model] 转写 [audio]。
///
/// 本入口当前支持 [DataBytes] 与 [DataBase64] 音频输入;URL 下载、provider
/// 引用与文本文件数据不属于转写音频输入。
Future<TranscriptionResult> transcribe({
  required provider.TranscriptionModel model,
  required DataContent audio,
  required String mediaType,
  provider.ProviderOptions? providerOptions,
  Map<String, String>? headers,
  provider.CancellationSignal? cancellation,
}) async {
  final modelResponse = await model.doGenerate(
    provider.TranscriptionModelCallOptions(
      audio: _toTranscriptionAudio(audio),
      mediaType: mediaType,
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
  if (modelResponse.text.isEmpty) {
    throw provider.NoTranscriptGeneratedError(
      responses: response == null ? const [] : [response],
    );
  }

  return TranscriptionResult(
    text: modelResponse.text,
    segments: modelResponse.segments,
    language: modelResponse.language,
    durationInSeconds: modelResponse.durationInSeconds,
    warnings: modelResponse.warnings,
    responses: response == null ? const [] : [response],
    providerMetadata: modelResponse.providerMetadata ?? const {},
  );
}

provider.TranscriptionAudio _toTranscriptionAudio(DataContent audio) {
  return switch (audio) {
    DataBytes(:final bytes) => provider.TranscriptionAudioBytes(bytes),
    DataBase64(:final base64) => provider.TranscriptionAudioBase64(base64),
    DataText() ||
    DataUrl() ||
    DataProviderRef() =>
      throw provider.InvalidArgumentError(
        argument: 'audio',
        message: 'transcribe audio must be DataBytes or DataBase64.',
      ),
  };
}
