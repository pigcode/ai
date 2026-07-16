import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../language_model/results.dart';
import '../shared/cancellation.dart';
import '../shared/shared.dart';

/// speech 模型规范版本。
const speechModelSpecVersion = 'v4';

/// speech 模型契约:单个动作 `doGenerate`。
abstract interface class SpeechModel {
  /// speech 模型规范版本。
  String get specificationVersion;

  /// provider 名,如 `'openai.speech'`。
  String get provider;

  /// provider 侧模型 id,如 `'tts-1'`。
  String get modelId;

  /// 为给定文本生成语音音频。
  Future<SpeechModelResult> doGenerate(SpeechModelCallOptions options);
}

/// [SpeechModel.doGenerate] 的调用参数。
final class SpeechModelCallOptions with EquatableMixin {
  const SpeechModelCallOptions({
    required this.text,
    this.voice,
    this.outputFormat,
    this.instructions,
    this.speed,
    this.language,
    this.headers,
    this.providerOptions,
    this.cancellation,
  });

  /// 要转换成语音的文本。
  final String text;

  /// provider 侧 voice id/name。
  final String? voice;

  /// 期望的音频输出格式,如 `mp3` 或 `wav`。
  final String? outputFormat;

  /// 语音生成指令,如语气或节奏。
  final String? instructions;

  /// 语速。
  final num? speed;

  /// 期望语言代码。provider 支持情况不一。
  final String? language;

  /// 覆盖/追加的请求头。
  final Headers? headers;

  /// provider 私有选项(外层键为 provider 名)。
  final ProviderOptions? providerOptions;

  /// 只读取消信号。身份对象,不入值相等。
  final CancellationSignal? cancellation;

  @override
  List<Object?> get props => <Object?>[
        text,
        voice,
        outputFormat,
        instructions,
        speed,
        language,
        headers,
        providerOptions,
      ];
}

/// [SpeechModel.doGenerate] 的结果。
final class SpeechModelResult with EquatableMixin {
  const SpeechModelResult({
    required this.audio,
    required this.warnings,
    this.format,
    this.providerMetadata,
    this.request,
    this.response,
  });

  /// 生成出的音频原始字节。
  final Uint8List audio;

  /// 实际返回的音频格式,如 `mp3` 或 `wav`。
  final String? format;

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
        audio,
        format,
        warnings,
        providerMetadata,
        request,
        response,
      ];
}
