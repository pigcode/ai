import 'package:equatable/equatable.dart';

import 'finish_reason.dart';
import 'language_model_events.dart';
import '../shared/shared.dart';
import 'usage.dart';

/// 请求侧轻量元数据:承载(可能已序列化的)请求体,供调试/回放。
final class RequestInfo with EquatableMixin {
  const RequestInfo({this.body});

  /// 已发送的请求体(provider 侧原样承载,类型不透明)。
  final Object? body;

  @override
  List<Object?> get props => [body];
}

/// 响应侧轻量元数据:响应 id / 时间戳 / 模型 id / 响应头 / 响应体。
final class ResponseInfo with EquatableMixin {
  const ResponseInfo({
    this.id,
    this.timestamp,
    this.modelId,
    this.headers,
    this.body,
  });

  /// provider 侧响应 id。
  final String? id;

  /// 响应时间戳。
  final DateTime? timestamp;

  /// provider 回报的实际模型 id。
  final String? modelId;

  /// 响应头。
  final Headers? headers;

  /// 原始响应体(类型不透明)。
  final Object? body;

  @override
  List<Object?> get props => [id, timestamp, modelId, headers, body];
}

/// [LanguageModel.doGenerate] 的结果:有序内容项 + 终止原因 + 用量 + 告警。
final class LanguageModelGenerateResult with EquatableMixin {
  const LanguageModelGenerateResult({
    required this.content,
    required this.finishReason,
    required this.usage,
    required this.warnings,
    this.providerMetadata,
    this.request,
    this.response,
  });

  /// 有序输出内容项。
  final List<LanguageModelContent> content;

  /// 本轮终止原因(对象化,保留 provider 原值)。
  final LanguageModelFinishReason finishReason;

  /// 本轮 token 用量(嵌套)。
  final LanguageModelUsage usage;

  /// 本轮告警(如降级/不支持特性)。
  final List<Warning> warnings;

  /// provider 私有元数据。
  final ProviderMetadata? providerMetadata;

  /// 请求侧元数据。
  final RequestInfo? request;

  /// 响应侧元数据。
  final ResponseInfo? response;

  @override
  List<Object?> get props => [
        content,
        finishReason,
        usage,
        warnings,
        providerMetadata,
        request,
        response
      ];
}

/// [LanguageModel.doStream] 的结果:事件流 + 请求/响应元数据。
final class LanguageModelStreamResult with EquatableMixin {
  const LanguageModelStreamResult({
    required this.stream,
    this.request,
    this.response,
  });

  /// 有序流式分块(首个通常为 [StreamStart],末个为 [FinishPart];
  /// 错误以 [ErrorPart] 事件形式出现,不抛异常)。
  final Stream<LanguageModelStreamPart> stream;

  /// 请求侧元数据。
  final RequestInfo? request;

  /// 响应侧元数据。
  final ResponseInfo? response;

  // stream 是身份对象(Stream 无值相等),仅比较元数据。
  @override
  List<Object?> get props => [request, response];
}
