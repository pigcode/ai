import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../language_model/results.dart';
import '../shared/cancellation.dart';
import '../shared/shared.dart';

/// transcription 模型规范版本。
const transcriptionModelSpecVersion = 'v4';

/// transcription 输入音频载体。
///
/// 对齐 v7 provider contract 的 `Uint8Array | string`:Dart 侧用显式
/// bytes/base64 两个变体表达,避免用 `Object` 或 `dynamic` 穿透契约边界。
sealed class TranscriptionAudio extends Equatable {
  const TranscriptionAudio();
}

/// 原始音频字节。
final class TranscriptionAudioBytes extends TranscriptionAudio {
  const TranscriptionAudioBytes(this.bytes);

  /// 音频原始字节。
  final Uint8List bytes;

  @override
  List<Object?> get props => <Object?>[bytes];
}

/// base64 编码的音频字节。
final class TranscriptionAudioBase64 extends TranscriptionAudio {
  const TranscriptionAudioBase64(this.base64);

  /// base64 编码后的音频内容。
  final String base64;

  @override
  List<Object?> get props => <Object?>[base64];
}

/// transcript 分段。
final class TranscriptionSegment with EquatableMixin {
  const TranscriptionSegment({
    required this.text,
    required this.startSecond,
    required this.endSecond,
  });

  /// 该分段文本。
  final String text;

  /// 分段开始时间(秒)。
  final double startSecond;

  /// 分段结束时间(秒)。
  final double endSecond;

  @override
  List<Object?> get props => <Object?>[text, startSecond, endSecond];
}

/// 流式 transcription 输入音频格式。
final class TranscriptionInputAudioFormat with EquatableMixin {
  const TranscriptionInputAudioFormat({
    required this.type,
    this.rate,
  });

  /// 音频格式类型,如 `audio/pcm`、`audio/pcmu` 或 `audio/pcma`。
  final String type;

  /// 采样率(Hz)。仅部分格式需要。
  final int? rate;

  @override
  List<Object?> get props => <Object?>[type, rate];
}

/// transcription 模型契约:单个动作 `doGenerate`。
abstract interface class TranscriptionModel {
  /// transcription 模型规范版本。
  String get specificationVersion;

  /// provider 名,如 `'openai.transcription'`。
  String get provider;

  /// provider 侧模型 id,如 `'whisper-1'`。
  String get modelId;

  /// 为给定音频生成 transcript。
  Future<TranscriptionModelResult> doGenerate(
    TranscriptionModelCallOptions options,
  );
}

/// 支持实时/流式 transcription 的模型契约。
abstract interface class StreamableTranscriptionModel
    implements TranscriptionModel {
  /// 为音频分块流生成 transcript 分块流。
  Future<TranscriptionModelStreamResult> doStream(
    TranscriptionModelStreamOptions options,
  );
}

/// [TranscriptionModel.doGenerate] 的调用参数。
final class TranscriptionModelCallOptions with EquatableMixin {
  const TranscriptionModelCallOptions({
    required this.audio,
    required this.mediaType,
    this.headers,
    this.providerOptions,
    this.cancellation,
  });

  /// 待转写音频数据。
  final TranscriptionAudio audio;

  /// IANA 音频媒体类型,如 `audio/wav`。
  final String mediaType;

  /// 覆盖/追加的请求头。
  final Headers? headers;

  /// provider 私有选项(外层键为 provider 名)。
  final ProviderOptions? providerOptions;

  /// 只读取消信号。身份对象,不入值相等。
  final CancellationSignal? cancellation;

  @override
  List<Object?> get props => <Object?>[
        audio,
        mediaType,
        headers,
        providerOptions,
      ];
}

/// [TranscriptionModel.doGenerate] 的结果。
final class TranscriptionModelResult with EquatableMixin {
  const TranscriptionModelResult({
    required this.text,
    required this.segments,
    this.language,
    this.durationInSeconds,
    required this.warnings,
    this.providerMetadata,
    this.request,
    this.response,
  });

  /// 完整 transcript 文本。
  final String text;

  /// transcript 分段。
  final List<TranscriptionSegment> segments;

  /// 识别出的语言代码,如 `en`。
  final String? language;

  /// 音频总时长(秒)。
  final double? durationInSeconds;

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
        text,
        segments,
        language,
        durationInSeconds,
        warnings,
        providerMetadata,
        request,
        response,
      ];
}

/// [StreamableTranscriptionModel.doStream] 的调用参数。
final class TranscriptionModelStreamOptions with EquatableMixin {
  const TranscriptionModelStreamOptions({
    required this.audio,
    required this.inputAudioFormat,
    this.headers,
    this.providerOptions,
    this.includeRawChunks,
    this.cancellation,
  });

  /// 待转写的音频分块流。
  final Stream<TranscriptionAudio> audio;

  /// 输入音频格式。
  final TranscriptionInputAudioFormat inputAudioFormat;

  /// 覆盖/追加的请求头。
  final Headers? headers;

  /// provider 私有选项(外层键为 provider 名)。
  final ProviderOptions? providerOptions;

  /// 是否要求 provider 在流中包含原始 provider 分块。
  final bool? includeRawChunks;

  /// 只读取消信号。身份对象,不入值相等。
  final CancellationSignal? cancellation;

  @override
  List<Object?> get props => <Object?>[
        inputAudioFormat,
        headers,
        providerOptions,
        includeRawChunks,
      ];
}

/// transcription 模型流式输出分块。
sealed class TranscriptionModelStreamPart extends Equatable {
  const TranscriptionModelStreamPart();
}

/// 流开始事件。
final class TranscriptionStreamStart extends TranscriptionModelStreamPart {
  const TranscriptionStreamStart(this.warnings);

  /// 调用告警。
  final List<Warning> warnings;

  @override
  List<Object?> get props => <Object?>[warnings];
}

/// 追加式 transcript delta。
final class TranscriptionDelta extends TranscriptionModelStreamPart {
  const TranscriptionDelta({
    required this.delta,
    this.id,
    this.providerMetadata,
  });

  /// provider 定义的分块 id。
  final String? id;

  /// 追加文本。
  final String delta;

  /// provider 私有元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => <Object?>[id, delta, providerMetadata];
}

/// 可被后续分块修订的非最终 transcript 文本。
final class TranscriptionPartial extends TranscriptionModelStreamPart {
  const TranscriptionPartial({
    required this.text,
    this.id,
    this.startSecond,
    this.durationInSeconds,
    this.channelIndex,
    this.providerMetadata,
  });

  /// provider 定义的分块 id。
  final String? id;

  /// 当前非最终文本。
  final String text;

  /// 起始时间(秒)。
  final double? startSecond;

  /// 持续时长(秒)。
  final double? durationInSeconds;

  /// 声道序号。
  final int? channelIndex;

  /// provider 私有元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => <Object?>[
        id,
        text,
        startSecond,
        durationInSeconds,
        channelIndex,
        providerMetadata,
      ];
}

/// provider 定义分段或话轮的最终 transcript 文本。
final class TranscriptionFinal extends TranscriptionModelStreamPart {
  const TranscriptionFinal({
    required this.text,
    this.id,
    this.startSecond,
    this.endSecond,
    this.channelIndex,
    this.providerMetadata,
  });

  /// provider 定义的分块 id。
  final String? id;

  /// 最终文本。
  final String text;

  /// 起始时间(秒)。
  final double? startSecond;

  /// 结束时间(秒)。
  final double? endSecond;

  /// 声道序号。
  final int? channelIndex;

  /// provider 私有元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => <Object?>[
        id,
        text,
        startSecond,
        endSecond,
        channelIndex,
        providerMetadata,
      ];
}

/// 流式响应元数据。
final class TranscriptionResponseMetadata extends TranscriptionModelStreamPart {
  const TranscriptionResponseMetadata(this.response);

  /// provider 响应元数据。
  final ResponseInfo response;

  @override
  List<Object?> get props => <Object?>[response];
}

/// 流结束事件,携带最终 transcript 元数据。
final class TranscriptionFinish extends TranscriptionModelStreamPart {
  const TranscriptionFinish({
    required this.text,
    required this.segments,
    this.language,
    this.durationInSeconds,
    this.providerMetadata,
  });

  /// 完整 transcript 文本。
  final String text;

  /// transcript 分段。
  final List<TranscriptionSegment> segments;

  /// 识别出的语言代码,如 `en`。
  final String? language;

  /// 音频总时长(秒)。
  final double? durationInSeconds;

  /// provider 私有元数据。
  final ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => <Object?>[
        text,
        segments,
        language,
        durationInSeconds,
        providerMetadata,
      ];
}

/// 原始 provider 分块。
final class TranscriptionRaw extends TranscriptionModelStreamPart {
  const TranscriptionRaw(this.rawValue);

  /// 原始 provider 值。
  final Object? rawValue;

  @override
  List<Object?> get props => <Object?>[rawValue];
}

/// 流式错误分块。
final class TranscriptionStreamError extends TranscriptionModelStreamPart {
  const TranscriptionStreamError(this.error);

  /// provider 或解析层错误。
  final Object error;

  @override
  List<Object?> get props => <Object?>[error];
}

/// [StreamableTranscriptionModel.doStream] 的结果。
final class TranscriptionModelStreamResult with EquatableMixin {
  const TranscriptionModelStreamResult({
    required this.stream,
    this.request,
    this.response,
  });

  /// 流式 transcription 分块。
  final Stream<TranscriptionModelStreamPart> stream;

  /// 请求侧元数据。
  final RequestInfo? request;

  /// 响应侧元数据。
  final ResponseInfo? response;

  @override
  List<Object?> get props => <Object?>[request, response];
}
