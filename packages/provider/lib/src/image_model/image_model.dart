import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../language_model/results.dart';
import '../shared/cancellation.dart';
import '../shared/shared.dart';

/// image 模型规范版本。
const imageModelSpecVersion = 'v4';

/// image 模型契约:单个动作 `doGenerate`。
abstract interface class ImageModel {
  /// image 模型规范版本。
  String get specificationVersion;

  /// provider 名,如 `'openai.image'`。
  String get provider;

  /// provider 侧模型 id,如 `'gpt-image-1'`。
  String get modelId;

  /// 单次 `doGenerate` 调用最多可生成的图片数量。
  ///
  /// `null` 表示模型未声明上限;上层入口可按自身默认策略处理。可能需要
  /// 异步计算,故用 [FutureOr]。
  FutureOr<int?> get maxImagesPerCall;

  /// 为给定文本 prompt 生成图片。
  Future<ImageModelResult> doGenerate(ImageModelCallOptions options);
}

/// image 生成输入文件,用于图片编辑或变体生成。
sealed class ImageModelFile extends Equatable {
  const ImageModelFile({this.mediaType});

  /// 输入文件的媒体类型,如 `image/png`。
  final String? mediaType;
}

/// 原始字节 image 输入文件。
final class ImageModelFileBytes extends ImageModelFile {
  const ImageModelFileBytes(this.bytes, {required super.mediaType});

  /// 文件原始字节。
  final Uint8List bytes;

  @override
  List<Object?> get props => <Object?>[bytes, mediaType];
}

/// Base64 image 输入文件。
final class ImageModelFileBase64 extends ImageModelFile {
  const ImageModelFileBase64(this.base64, {required super.mediaType});

  /// 文件内容的 Base64 编码。
  final String base64;

  @override
  List<Object?> get props => <Object?>[base64, mediaType];
}

/// URL image 输入文件。
final class ImageModelFileUrl extends ImageModelFile {
  const ImageModelFileUrl(this.url, {super.mediaType});

  /// 文件 URL。
  final Uri url;

  @override
  List<Object?> get props => <Object?>[url, mediaType];
}

/// [ImageModel.doGenerate] 的调用参数。
final class ImageModelCallOptions with EquatableMixin {
  const ImageModelCallOptions({
    required this.prompt,
    this.n = 1,
    this.size,
    this.aspectRatio,
    this.seed,
    this.files,
    this.mask,
    this.headers,
    this.providerOptions,
    this.cancellation,
  });

  /// 用于生成图片的文本 prompt。
  final String prompt;

  /// 要生成的图片数量。
  final int n;

  /// 图片尺寸,如 `1024x1024`。
  final String? size;

  /// 图片宽高比,如 `1:1`。provider 支持情况不一。
  final String? aspectRatio;

  /// 生成种子。provider 支持情况不一。
  final int? seed;

  /// image editing / variation 的输入图片。
  final List<ImageModelFile>? files;

  /// image inpainting 的 mask 图片。
  final ImageModelFile? mask;

  /// 覆盖/追加的请求头。
  final Headers? headers;

  /// provider 私有选项(外层键为 provider 名)。
  final ProviderOptions? providerOptions;

  /// 只读取消信号。身份对象,不入值相等。
  final CancellationSignal? cancellation;

  @override
  List<Object?> get props => <Object?>[
        prompt,
        n,
        size,
        aspectRatio,
        seed,
        files,
        mask,
        headers,
        providerOptions,
      ];
}

/// image 生成调用的 token 用量。
final class ImageModelUsage with EquatableMixin {
  const ImageModelUsage({
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
  });

  /// 输入 token 数。
  final int? inputTokens;

  /// 输出 token 数。
  final int? outputTokens;

  /// 总 token 数。
  final int? totalTokens;

  @override
  List<Object?> get props => <Object?>[
        inputTokens,
        outputTokens,
        totalTokens,
      ];
}

/// [ImageModel.doGenerate] 的结果。
final class ImageModelResult with EquatableMixin {
  const ImageModelResult({
    required this.images,
    required this.warnings,
    this.usage = const ImageModelUsage(),
    this.providerMetadata,
    this.request,
    this.response,
  });

  /// 生成出的图片原始字节列表。
  final List<Uint8List> images;

  /// 调用告警。
  final List<Warning> warnings;

  /// 本次调用的 token 用量。
  final ImageModelUsage usage;

  /// provider 私有元数据。
  final ProviderMetadata? providerMetadata;

  /// 请求侧元数据。
  final RequestInfo? request;

  /// 响应侧元数据。
  final ResponseInfo? response;

  @override
  List<Object?> get props => <Object?>[
        images,
        warnings,
        usage,
        providerMetadata,
        request,
        response,
      ];
}
