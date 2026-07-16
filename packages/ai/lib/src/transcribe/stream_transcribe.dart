import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:equatable/equatable.dart';

import '../generate_text/request_options_snapshot.dart';
import '../logger/log_warnings.dart';
import '../prompt/content_part.dart';

/// `streamTranscribe` 结果中需要额外包含的数据。
final class StreamTranscriptionInclude {
  const StreamTranscriptionInclude({this.rawChunks});

  /// 是否在流中透传 provider 原始分块。
  final bool? rawChunks;
}

/// 用户面 transcription 流式分块。
sealed class TranscriptionStreamPart extends Equatable {
  const TranscriptionStreamPart();
}

/// 追加式 transcript delta。
final class TranscriptDeltaPart extends TranscriptionStreamPart {
  const TranscriptDeltaPart({
    required this.delta,
    this.id,
    this.providerMetadata,
  });

  /// provider 定义的分块 id。
  final String? id;

  /// 追加文本。
  final String delta;

  /// provider 私有元数据。
  final provider.ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => <Object?>[id, delta, providerMetadata];
}

/// 可被后续分块修订的非最终 transcript 文本。
final class TranscriptPartialPart extends TranscriptionStreamPart {
  const TranscriptPartialPart({
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
  final provider.ProviderMetadata? providerMetadata;

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
final class TranscriptFinalPart extends TranscriptionStreamPart {
  const TranscriptFinalPart({
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
  final provider.ProviderMetadata? providerMetadata;

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

/// 原始 provider 分块。
final class TranscriptionRawPart extends TranscriptionStreamPart {
  const TranscriptionRawPart(this.rawValue);

  /// 原始 provider 值。
  final Object? rawValue;

  @override
  List<Object?> get props => <Object?>[rawValue];
}

/// transcription 流的终端错误。
final class TranscriptionErrorPart extends TranscriptionStreamPart {
  const TranscriptionErrorPart(this.error);

  /// 错误值。
  final Object error;

  @override
  List<Object?> get props => <Object?>[error];
}

/// `streamTranscribe` 的结果。
final class StreamTranscriptionResult {
  const StreamTranscriptionResult({
    required this.stream,
    required this.text,
    required this.segments,
    required this.language,
    required this.durationInSeconds,
    required this.warnings,
    required this.responses,
    required this.providerMetadata,
  });

  /// 用户面 transcription 分块流。
  final Stream<TranscriptionStreamPart> stream;

  /// 完整 transcript 文本。
  final Future<String> text;

  /// transcript 分段。
  final Future<List<provider.TranscriptionSegment>> segments;

  /// 识别出的语言代码,如 `en`。
  final Future<String?> language;

  /// 音频总时长(秒)。
  final Future<double?> durationInSeconds;

  /// provider 侧告警。
  final Future<List<provider.Warning>> warnings;

  /// provider 响应元数据。
  final Future<List<provider.ResponseInfo>> responses;

  /// provider 私有元数据。
  final Future<provider.ProviderMetadata> providerMetadata;
}

/// 用支持 streaming transcription 的 [model] 转写音频分块流。
StreamTranscriptionResult streamTranscribe({
  required provider.TranscriptionModel model,
  required Stream<DataContent> audio,
  required provider.TranscriptionInputAudioFormat inputAudioFormat,
  provider.ProviderOptions? providerOptions,
  Map<String, String>? headers,
  StreamTranscriptionInclude? include,
  provider.CancellationSignal? cancellation,
}) {
  if (model is! provider.StreamableTranscriptionModel) {
    throw provider.UnsupportedFunctionalityError(
      functionality:
          'streaming transcription for ${model.provider} ${model.modelId}',
    );
  }

  final controller = StreamController<TranscriptionStreamPart>();
  final textCompleter = Completer<String>();
  final segmentsCompleter = Completer<List<provider.TranscriptionSegment>>();
  final languageCompleter = Completer<String?>();
  final durationCompleter = Completer<double?>();
  final warningsCompleter = Completer<List<provider.Warning>>();
  final responsesCompleter = Completer<List<provider.ResponseInfo>>();
  final providerMetadataCompleter = Completer<provider.ProviderMetadata>();

  for (final future in <Future<Object?>>[
    textCompleter.future,
    segmentsCompleter.future,
    languageCompleter.future,
    durationCompleter.future,
    warningsCompleter.future,
    responsesCompleter.future,
    providerMetadataCompleter.future,
  ]) {
    // stream 是主要错误表面;调用方可以忽略这些聚合 Future。
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }

  final headersSnapshot = snapshotHeaders(headers);
  final providerOptionsSnapshot = snapshotProviderOptions(providerOptions);
  provider.ResponseInfo? response;

  void completeError(Object error, StackTrace stackTrace) {
    for (final completer in <Completer<Object?>>[
      textCompleter,
      segmentsCompleter,
      languageCompleter,
      durationCompleter,
      warningsCompleter,
      responsesCompleter,
      providerMetadataCompleter,
    ]) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }

  void emitTerminalError(Object error, StackTrace stackTrace) {
    completeError(error, stackTrace);
    controller.add(TranscriptionErrorPart(error));
  }

  provider.NoTranscriptGeneratedError noTranscriptError() {
    final currentResponse = response;
    return provider.NoTranscriptGeneratedError(
      responses: currentResponse == null ? const [] : [currentResponse],
    );
  }

  provider.ResponseInfo mergeResponseMetadata(
    provider.ResponseInfo? current,
    provider.ResponseInfo next,
  ) {
    if (current == null) {
      return next;
    }
    return provider.ResponseInfo(
      id: next.id ?? current.id,
      timestamp: next.timestamp ?? current.timestamp,
      modelId: next.modelId ?? current.modelId,
      headers: next.headers ?? current.headers,
      body: next.body ?? current.body,
    );
  }

  Future<void> run() async {
    try {
      final result = await model.doStream(
        provider.TranscriptionModelStreamOptions(
          audio: audio.map(_toTranscriptionAudio),
          inputAudioFormat: inputAudioFormat,
          headers: headersSnapshot,
          providerOptions: providerOptionsSnapshot,
          includeRawChunks: include?.rawChunks,
          cancellation: cancellation,
        ),
      );
      response = result.response;

      await for (final part in result.stream) {
        switch (part) {
          case provider.TranscriptionStreamStart(:final warnings):
            if (!warningsCompleter.isCompleted) {
              warningsCompleter.complete(warnings);
            }
            logWarnings(
              warnings: warnings,
              provider: model.provider,
              model: model.modelId,
            );
          case provider.TranscriptionDelta(
              :final id,
              :final delta,
              :final providerMetadata,
            ):
            controller.add(TranscriptDeltaPart(
              id: id,
              delta: delta,
              providerMetadata: providerMetadata,
            ));
          case provider.TranscriptionPartial(
              :final id,
              :final text,
              :final startSecond,
              :final durationInSeconds,
              :final channelIndex,
              :final providerMetadata,
            ):
            controller.add(TranscriptPartialPart(
              id: id,
              text: text,
              startSecond: startSecond,
              durationInSeconds: durationInSeconds,
              channelIndex: channelIndex,
              providerMetadata: providerMetadata,
            ));
          case provider.TranscriptionFinal(
              :final id,
              :final text,
              :final startSecond,
              :final endSecond,
              :final channelIndex,
              :final providerMetadata,
            ):
            controller.add(TranscriptFinalPart(
              id: id,
              text: text,
              startSecond: startSecond,
              endSecond: endSecond,
              channelIndex: channelIndex,
              providerMetadata: providerMetadata,
            ));
          case provider.TranscriptionResponseMetadata(
              response: final nextResponse
            ):
            response = mergeResponseMetadata(response, nextResponse);
          case provider.TranscriptionFinish(
              :final text,
              :final segments,
              :final language,
              :final durationInSeconds,
              :final providerMetadata,
            ):
            if (!warningsCompleter.isCompleted) {
              warningsCompleter.complete(const []);
            }
            if (text.isEmpty) {
              throw noTranscriptError();
            }
            textCompleter.complete(text);
            segmentsCompleter.complete(segments);
            languageCompleter.complete(language);
            durationCompleter.complete(durationInSeconds);
            final currentResponse = response;
            responsesCompleter.complete(
              currentResponse == null ? const [] : [currentResponse],
            );
            providerMetadataCompleter.complete(providerMetadata ?? const {});
          case provider.TranscriptionRaw(:final rawValue):
            controller.add(TranscriptionRawPart(rawValue));
          case provider.TranscriptionStreamError(:final error):
            emitTerminalError(error, StackTrace.current);
            return;
        }
      }

      if (!textCompleter.isCompleted) {
        throw noTranscriptError();
      }
    } catch (error, stackTrace) {
      emitTerminalError(error, stackTrace);
    } finally {
      await controller.close();
    }
  }

  unawaited(run());

  return StreamTranscriptionResult(
    stream: controller.stream,
    text: textCompleter.future,
    segments: segmentsCompleter.future,
    language: languageCompleter.future,
    durationInSeconds: durationCompleter.future,
    warnings: warningsCompleter.future,
    responses: responsesCompleter.future,
    providerMetadata: providerMetadataCompleter.future,
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
        message: 'streamTranscribe audio must contain DataBytes or DataBase64.',
      ),
  };
}
