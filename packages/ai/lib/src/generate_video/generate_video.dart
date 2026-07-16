import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart'
    as utils;
import 'package:equatable/equatable.dart';

import '../logger/log_warnings.dart';

/// `generateVideo` 生成出的单个视频。
final class GeneratedVideo with EquatableMixin {
  const GeneratedVideo({
    required this.data,
    required this.mediaType,
    required this.format,
  });

  /// 视频数据。URL 结果会原样保留为 [provider.FileDataUrl],不自动下载。
  final provider.OutputFileData data;

  /// 视频媒体类型,如 `video/mp4`。
  final String mediaType;

  /// 视频格式,如 `mp4`。
  final String format;

  @override
  List<Object?> get props => <Object?>[data, mediaType, format];
}

/// `generateVideo` 的结果。
final class GenerateVideoResult {
  const GenerateVideoResult({
    required this.videos,
    required this.warnings,
    required this.responses,
    required this.providerMetadata,
  });

  /// 生成出的视频列表。
  final List<GeneratedVideo> videos;

  /// 第一个生成视频。
  GeneratedVideo get video => videos.first;

  /// provider 侧告警。
  final List<provider.Warning> warnings;

  /// provider 响应元数据。
  final List<provider.ResponseInfo> responses;

  /// provider 私有元数据。
  final provider.ProviderMetadata providerMetadata;
}

/// 用给定 video [model] 从 prompt / image 输入生成视频。
Future<GenerateVideoResult> generateVideo({
  required provider.VideoModel model,
  String? prompt,
  int n = 1,
  int? maxVideosPerCall,
  String? aspectRatio,
  String? resolution,
  num? duration,
  num? fps,
  int? seed,
  provider.VideoModelFile? image,
  List<provider.VideoFrameImage>? frameImages,
  List<provider.VideoModelFile>? inputReferences,
  bool? generateAudio,
  provider.ProviderOptions? providerOptions,
  Map<String, String>? headers,
  provider.CancellationSignal? cancellation,
}) async {
  if (n <= 0) {
    throw ArgumentError.value(n, 'n', 'must be greater than 0');
  }

  final effectiveMaxVideosPerCall =
      maxVideosPerCall ?? await model.maxVideosPerCall ?? 1;
  if (effectiveMaxVideosPerCall <= 0) {
    throw ArgumentError.value(
      effectiveMaxVideosPerCall,
      'maxVideosPerCall',
      'must be greater than 0',
    );
  }

  final results = await Future.wait(
    _videoCountBatches(n, effectiveMaxVideosPerCall).map(
      (batchSize) => model.doGenerate(
        provider.VideoModelCallOptions(
          prompt: prompt,
          n: batchSize,
          aspectRatio: aspectRatio,
          resolution: resolution,
          duration: duration,
          fps: fps,
          seed: seed,
          image: image,
          frameImages: frameImages,
          inputReferences: inputReferences,
          generateAudio: generateAudio,
          headers: headers,
          providerOptions: providerOptions,
          cancellation: cancellation,
        ),
      ),
    ),
  );

  final videos = <GeneratedVideo>[];
  final warnings = <provider.Warning>[];
  final responses = <provider.ResponseInfo>[];
  provider.ProviderMetadata? providerMetadata;

  for (final result in results) {
    logWarnings(
      warnings: result.warnings,
      provider: model.provider,
      model: model.modelId,
    );
    videos.addAll(result.videos.map(_toGeneratedVideo));
    warnings.addAll(result.warnings);
    final response = result.response;
    if (response != null) {
      responses.add(response);
    }
    final batchMetadata = result.providerMetadata;
    if (batchMetadata != null) {
      providerMetadata = _mergeProviderMetadata(
        providerMetadata,
        batchMetadata,
      );
    }
  }

  if (videos.isEmpty) {
    throw provider.NoVideoGeneratedError(responses: responses);
  }

  return GenerateVideoResult(
    videos: videos,
    warnings: warnings,
    responses: responses,
    providerMetadata: providerMetadata ?? const {},
  );
}

List<int> _videoCountBatches(int n, int maxVideosPerCall) {
  final batches = <int>[];
  var remaining = n;
  while (remaining > 0) {
    final batchSize =
        remaining > maxVideosPerCall ? maxVideosPerCall : remaining;
    batches.add(batchSize);
    remaining -= batchSize;
  }
  return batches;
}

GeneratedVideo _toGeneratedVideo(provider.VideoModelVideoData video) {
  return switch (video) {
    provider.VideoModelVideoDataBytes(:final bytes, :final mediaType) =>
      _generatedVideo(
        data: provider.FileDataBytes(bytes),
        mediaType: mediaType ?? _videoMediaTypeFromBytes(bytes),
      ),
    provider.VideoModelVideoDataBase64(:final base64, :final mediaType) =>
      _generatedVideo(
        data: provider.FileDataBase64(base64),
        mediaType: mediaType ?? _videoMediaTypeFromBase64(base64),
      ),
    provider.VideoModelVideoDataUrl(:final url, :final mediaType) =>
      _generatedVideo(
        data: provider.FileDataUrl(url),
        mediaType: mediaType ?? _videoMediaTypeFromUrl(url),
      ),
  };
}

GeneratedVideo _generatedVideo({
  required provider.OutputFileData data,
  required String mediaType,
}) {
  return GeneratedVideo(
    data: data,
    mediaType: mediaType,
    format: _videoFormat(mediaType),
  );
}

String _videoMediaTypeFromBytes(List<int> bytes) {
  return utils.detectMediaType(data: bytes, topLevelType: 'video') ??
      'video/mp4';
}

String _videoMediaTypeFromBase64(String base64) {
  return utils.detectMediaType(data: base64, topLevelType: 'video') ??
      'video/mp4';
}

String _videoMediaTypeFromUrl(Uri url) {
  final path = url.path.toLowerCase();
  final dotIndex = path.lastIndexOf('.');
  final extension = dotIndex == -1 ? '' : path.substring(dotIndex + 1);
  return switch (extension) {
    'webm' => 'video/webm',
    'mov' || 'qt' => 'video/quicktime',
    'avi' => 'video/x-msvideo',
    'ogv' || 'ogg' => 'video/ogg',
    'mp4' || 'm4v' => 'video/mp4',
    _ => 'video/mp4',
  };
}

String _videoFormat(String mediaType) {
  if (mediaType.toLowerCase().split(';').first.trim() == 'video/x-msvideo') {
    return 'avi';
  }
  return utils.mediaTypeToExtension(mediaType);
}

provider.ProviderMetadata _mergeProviderMetadata(
  provider.ProviderMetadata? existing,
  provider.ProviderMetadata incoming,
) {
  final merged = <String, provider.JsonObject>{
    if (existing != null) ...existing,
  };
  for (final entry in incoming.entries) {
    final existingProviderMetadata = merged[entry.key];
    final mergedProviderMetadata = <String, Object?>{
      ...?existingProviderMetadata,
      ...entry.value,
    };
    final existingVideos = existingProviderMetadata?['videos'];
    final incomingVideos = entry.value['videos'];
    if (existingVideos is List && incomingVideos is List) {
      mergedProviderMetadata['videos'] = <Object?>[
        ...existingVideos,
        ...incomingVideos,
      ];
    }
    merged[entry.key] = mergedProviderMetadata;
  }
  return merged;
}
