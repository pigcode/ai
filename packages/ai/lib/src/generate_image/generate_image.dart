import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart'
    as utils;
import 'package:equatable/equatable.dart';

import '../logger/log_warnings.dart';
import '../prompt/content_part.dart';

/// `generateImage` 生成出的单张图片。
final class GeneratedImage with EquatableMixin {
  const GeneratedImage({
    required this.bytes,
    required this.mediaType,
    required this.format,
  });

  /// 图片原始字节。
  final Uint8List bytes;

  /// 图片媒体类型,如 `image/png`。
  final String mediaType;

  /// 图片格式,如 `png`。
  final String format;

  @override
  List<Object?> get props => <Object?>[bytes, mediaType, format];
}

/// `generateImage` 的结果。
final class GenerateImageResult {
  const GenerateImageResult({
    required this.images,
    required this.warnings,
    required this.responses,
    required this.providerMetadata,
    required this.usage,
  });

  /// 生成出的图片列表。
  final List<GeneratedImage> images;

  /// 第一张生成图片。
  GeneratedImage get image => images.first;

  /// provider 侧告警。
  final List<provider.Warning> warnings;

  /// provider 响应元数据。
  final List<provider.ResponseInfo> responses;

  /// provider 私有元数据。
  final provider.ProviderMetadata providerMetadata;

  /// 汇总后的图片生成用量。
  final provider.ImageModelUsage usage;
}

/// 用给定 image [model] 从文本 [prompt] 生成图片。
///
/// 传入 [images] 时进入 image editing / variation 语义;[mask] 用于
/// inpainting。URL 输入会原样透传到 provider,本入口不自动下载。
Future<GenerateImageResult> generateImage({
  required provider.ImageModel model,
  required String prompt,
  int n = 1,
  int? maxImagesPerCall,
  String? size,
  String? aspectRatio,
  int? seed,
  List<DataContent>? images,
  DataContent? mask,
  provider.ProviderOptions? providerOptions,
  Map<String, String>? headers,
  provider.CancellationSignal? cancellation,
}) async {
  if (n <= 0) {
    throw ArgumentError.value(n, 'n', 'must be greater than 0');
  }
  if (mask != null && (images == null || images.isEmpty)) {
    throw const provider.InvalidArgumentError(
      argument: 'mask',
      message: 'mask requires at least one image.',
    );
  }
  if (images != null && images.isEmpty) {
    throw const provider.InvalidArgumentError(
      argument: 'images',
      message: 'images must not be empty.',
    );
  }

  final effectiveMaxImagesPerCall =
      maxImagesPerCall ?? await model.maxImagesPerCall ?? 1;
  if (effectiveMaxImagesPerCall <= 0) {
    throw ArgumentError.value(
      effectiveMaxImagesPerCall,
      'maxImagesPerCall',
      'must be greater than 0',
    );
  }

  final results = await Future.wait(
    _imageCountBatches(n, effectiveMaxImagesPerCall).map(
      (batchSize) => model.doGenerate(
        provider.ImageModelCallOptions(
          prompt: prompt,
          n: batchSize,
          size: size,
          aspectRatio: aspectRatio,
          seed: seed,
          files: images
              ?.map((image) => _toImageModelFile(image, argument: 'images'))
              .toList(growable: false),
          mask: mask == null ? null : _toImageModelFile(mask, argument: 'mask'),
          headers: headers,
          providerOptions: providerOptions,
          cancellation: cancellation,
        ),
      ),
    ),
  );

  final generatedImages = <GeneratedImage>[];
  final warnings = <provider.Warning>[];
  final responses = <provider.ResponseInfo>[];
  provider.ProviderMetadata? providerMetadata;

  for (final result in results) {
    logWarnings(
      warnings: result.warnings,
      provider: model.provider,
      model: model.modelId,
    );
    generatedImages.addAll(result.images.map(_toGeneratedImage));
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

  if (generatedImages.isEmpty) {
    throw provider.NoImageGeneratedError(responses: responses);
  }

  return GenerateImageResult(
    images: generatedImages,
    warnings: warnings,
    responses: responses,
    providerMetadata: providerMetadata ?? const {},
    usage: _sumUsage(results.map((result) => result.usage)),
  );
}

List<int> _imageCountBatches(int n, int maxImagesPerCall) {
  final batches = <int>[];
  var remaining = n;
  while (remaining > 0) {
    final batchSize =
        remaining > maxImagesPerCall ? maxImagesPerCall : remaining;
    batches.add(batchSize);
    remaining -= batchSize;
  }
  return batches;
}

provider.ImageModelFile _toImageModelFile(
  DataContent data, {
  required String argument,
}) {
  return switch (data) {
    DataBytes(:final bytes) => provider.ImageModelFileBytes(
        bytes,
        mediaType: _imageMediaTypeFromBytes(bytes),
      ),
    DataBase64(:final base64) => provider.ImageModelFileBase64(
        base64,
        mediaType: _imageMediaTypeFromBase64(base64),
      ),
    DataUrl(:final url) => provider.ImageModelFileUrl(url),
    DataText() || DataProviderRef() => throw provider.InvalidArgumentError(
        argument: argument,
        message: '$argument must contain DataBytes, DataBase64, or DataUrl.',
      ),
  };
}

String _imageMediaTypeFromBytes(List<int> bytes) {
  return utils.detectMediaType(data: bytes, topLevelType: 'image') ??
      'image/png';
}

String _imageMediaTypeFromBase64(String base64) {
  return utils.detectMediaType(data: base64, topLevelType: 'image') ??
      'image/png';
}

GeneratedImage _toGeneratedImage(Uint8List bytes) {
  final format = _imageFormat(bytes);
  return GeneratedImage(
    bytes: bytes,
    mediaType: 'image/$format',
    format: format,
  );
}

String _imageFormat(Uint8List bytes) {
  if (_hasPrefix(bytes, const [0x89, 0x50, 0x4e, 0x47])) {
    return 'png';
  }
  if (_hasPrefix(bytes, const [0xff, 0xd8, 0xff])) {
    return 'jpeg';
  }
  if (bytes.length >= 12 &&
      _hasPrefix(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  return 'png';
}

bool _hasPrefix(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) {
      return false;
    }
  }
  return true;
}

provider.ImageModelUsage _sumUsage(
  Iterable<provider.ImageModelUsage> usages,
) {
  var inputTokens = 0;
  var outputTokens = 0;
  var totalTokens = 0;
  var hasInputTokens = false;
  var hasOutputTokens = false;
  var hasTotalTokens = false;

  for (final usage in usages) {
    final input = usage.inputTokens;
    if (input != null) {
      hasInputTokens = true;
      inputTokens += input;
    }

    final output = usage.outputTokens;
    if (output != null) {
      hasOutputTokens = true;
      outputTokens += output;
    }

    final total = usage.totalTokens;
    if (total != null) {
      hasTotalTokens = true;
      totalTokens += total;
    }
  }

  return provider.ImageModelUsage(
    inputTokens: hasInputTokens ? inputTokens : null,
    outputTokens: hasOutputTokens ? outputTokens : null,
    totalTokens: hasTotalTokens ? totalTokens : null,
  );
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
    final existingImages = existingProviderMetadata?['images'];
    final incomingImages = entry.value['images'];
    if (existingImages is List && incomingImages is List) {
      mergedProviderMetadata['images'] = <Object?>[
        ...existingImages,
        ...incomingImages,
      ];
    }
    merged[entry.key] = mergedProviderMetadata;
  }
  return merged;
}
