import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../language_model/results.dart';
import '../shared/cancellation.dart';
import '../shared/shared.dart';

/// video 模型规范版本。
const videoModelSpecVersion = 'v4';

/// video 模型契约:单个动作 `doGenerate`。
abstract interface class VideoModel {
  /// video 模型规范版本。
  String get specificationVersion;

  /// provider 名,如 `'google.video'`。
  String get provider;

  /// provider 侧模型 id,如 `'veo-3.1-generate-preview'`。
  String get modelId;

  /// 单次 `doGenerate` 调用最多可生成的视频数量。
  ///
  /// `null` 表示模型未声明上限;上层入口可按自身默认策略处理。可能需要
  /// 异步计算,故用 [FutureOr]。
  FutureOr<int?> get maxVideosPerCall;

  /// 为给定 prompt / image 输入生成视频。
  Future<VideoModelResult> doGenerate(VideoModelCallOptions options);
}

/// video 生成输入文件。
sealed class VideoModelFile extends Equatable {
  const VideoModelFile({this.mediaType});

  /// 输入文件的媒体类型,如 `image/png`。
  final String? mediaType;
}

/// 原始字节输入文件。
final class VideoModelFileBytes extends VideoModelFile {
  const VideoModelFileBytes(this.bytes, {required super.mediaType});

  /// 文件原始字节。
  final Uint8List bytes;

  @override
  List<Object?> get props => <Object?>[bytes, mediaType];
}

/// Base64 输入文件。
final class VideoModelFileBase64 extends VideoModelFile {
  const VideoModelFileBase64(this.base64, {required super.mediaType});

  /// 文件内容的 Base64 编码。
  final String base64;

  @override
  List<Object?> get props => <Object?>[base64, mediaType];
}

/// URL 输入文件。
final class VideoModelFileUrl extends VideoModelFile {
  const VideoModelFileUrl(this.url, {super.mediaType});

  /// 文件 URL。
  final Uri url;

  @override
  List<Object?> get props => <Object?>[url, mediaType];
}

/// video 首尾帧标记。
enum VideoFrameType {
  /// 生成视频的首帧。
  firstFrame('first_frame'),

  /// 生成视频的末帧。
  lastFrame('last_frame');

  const VideoFrameType(this.wireValue);

  /// provider wire 层通用值。
  final String wireValue;
}

/// 带首尾帧角色的 image 输入。
final class VideoFrameImage with EquatableMixin {
  const VideoFrameImage({
    required this.image,
    required this.frameType,
  });

  /// 帧图片。
  final VideoModelFile image;

  /// 帧角色。
  final VideoFrameType frameType;

  @override
  List<Object?> get props => <Object?>[image, frameType];
}

/// [VideoModel.doGenerate] 的调用参数。
final class VideoModelCallOptions with EquatableMixin {
  const VideoModelCallOptions({
    this.prompt,
    this.n = 1,
    this.aspectRatio,
    this.resolution,
    this.duration,
    this.fps,
    this.seed,
    this.image,
    this.frameImages,
    this.inputReferences,
    this.generateAudio,
    this.headers,
    this.providerOptions,
    this.cancellation,
  });

  /// 用于生成视频的文本 prompt。
  final String? prompt;

  /// 要生成的视频数量。
  final int n;

  /// 视频宽高比,如 `16:9`。
  final String? aspectRatio;

  /// 视频分辨率,如 `1920x1080`。
  final String? resolution;

  /// 视频时长(秒)。
  final num? duration;

  /// 每秒帧数。
  final num? fps;

  /// 生成种子。provider 支持情况不一。
  final int? seed;

  /// image-to-video 起始图片。
  final VideoModelFile? image;

  /// 首尾帧图片输入。
  final List<VideoFrameImage>? frameImages;

  /// reference-to-video 参考图片输入。
  final List<VideoModelFile>? inputReferences;

  /// 是否让模型同时生成音频。
  final bool? generateAudio;

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
        aspectRatio,
        resolution,
        duration,
        fps,
        seed,
        image,
        frameImages,
        inputReferences,
        generateAudio,
        headers,
        providerOptions,
      ];
}

/// video 生成结果数据。
sealed class VideoModelVideoData extends Equatable {
  const VideoModelVideoData({this.mediaType});

  /// 视频媒体类型,如 `video/mp4`。
  final String? mediaType;
}

/// 原始字节视频。
final class VideoModelVideoDataBytes extends VideoModelVideoData {
  const VideoModelVideoDataBytes(this.bytes, {super.mediaType});

  /// 视频原始字节。
  final Uint8List bytes;

  @override
  List<Object?> get props => <Object?>[bytes, mediaType];
}

/// Base64 视频。
final class VideoModelVideoDataBase64 extends VideoModelVideoData {
  const VideoModelVideoDataBase64(this.base64, {super.mediaType});

  /// 视频内容的 Base64 编码。
  final String base64;

  @override
  List<Object?> get props => <Object?>[base64, mediaType];
}

/// URL 视频。
final class VideoModelVideoDataUrl extends VideoModelVideoData {
  const VideoModelVideoDataUrl(this.url, {super.mediaType});

  /// 视频 URL。
  final Uri url;

  @override
  List<Object?> get props => <Object?>[url, mediaType];
}

/// [VideoModel.doGenerate] 的结果。
final class VideoModelResult with EquatableMixin {
  const VideoModelResult({
    required this.videos,
    required this.warnings,
    this.providerMetadata,
    this.request,
    this.response,
  });

  /// 生成出的视频数据列表。
  final List<VideoModelVideoData> videos;

  /// 调用告警。
  final List<Warning> warnings;

  /// provider 私有元数据。
  final ProviderMetadata? providerMetadata;

  /// 请求侧元数据。
  final RequestInfo? request;

  /// 响应侧元数据。
  final ResponseInfo? response;

  @override
  List<Object?> get props => <Object?>[
        videos,
        warnings,
        providerMetadata,
        request,
        response,
      ];
}
