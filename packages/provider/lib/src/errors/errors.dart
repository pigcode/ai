import '../language_model/finish_reason.dart';
import '../language_model/results.dart';
import '../language_model/usage.dart';
import '../shared/shared.dart';

/// AI SDK 的统一错误基类。
///
/// 用普通类层次 + `is` 判型表达上游的判别错误族;不搬运 TS 的 symbol brand。
/// 错误是异常,不要求值相等,但都应给出可读的 [toString]。
sealed class AiError implements Exception {
  const AiError(this.message, {this.cause});

  /// 面向人类的错误描述(英文)。
  final String message;

  /// 触发本错误的底层原因(可空):可为另一个 [Object] 或异常。
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (cause != null) {
      buffer.write(' (cause: $cause)');
    }
    return buffer.toString();
  }
}

/// HTTP/API 调用失败。承载定位与重试所需的 wire 信息。
final class ApiCallError extends AiError {
  const ApiCallError({
    required String message,
    required this.url,
    required this.requestBody,
    this.statusCode,
    this.responseHeaders,
    this.responseBody,
    this.data,
    bool? isRetryable,
    Object? cause,
  })  : _isRetryable = isRetryable,
        super(message, cause: cause);

  /// 请求的目标 URL。
  final String url;

  /// 已序列化的请求体(诊断用,类型不定)。
  final Object? requestBody;

  /// HTTP 状态码;若在建立连接前失败则为 null。
  final int? statusCode;

  /// 响应头(如可得)。
  final Headers? responseHeaders;

  /// 原始响应体文本(如可得)。
  final String? responseBody;

  /// provider 侧结构化错误数据(如可得)。
  final Object? data;

  /// 显式重试标志;为 null 时按状态码推断(见 [isRetryable])。
  final bool? _isRetryable;

  /// 是否可重试。
  ///
  /// 显式 [isRetryable] 优先;否则默认对 408/409/429 及任意 5xx 返回 true。
  bool get isRetryable =>
      _isRetryable ??
      (statusCode != null &&
          (statusCode == 408 ||
              statusCode == 409 ||
              statusCode == 429 ||
              statusCode! >= 500));

  @override
  String toString() {
    final buffer = StringBuffer('ApiCallError: $message');
    if (statusCode != null) {
      buffer.write(' (status: $statusCode)');
    }
    buffer.write(' url=$url');
    if (cause != null) {
      buffer.write(' cause=$cause');
    }
    return buffer.toString();
  }
}

/// 模态类型标记,供 [NoSuchModelError] 指明缺失的是哪种模型。
enum ModelType {
  languageModel,
  embeddingModel,
  imageModel,
  transcriptionModel,
  speechModel,
  rerankingModel,
  videoModel,
}

/// 请求了 provider 未知的模型 id。
final class NoSuchModelError extends AiError {
  /// `enum.name`/`enum.toString()` 及任何函数调用均非常量表达式,无法在
  /// `const` 构造函数的初始化列表中用于拼接默认 message;因此改用逐值比较的
  /// 常量三元表达式内联展开 [ModelType] 到其可读名称(`dart format` 会将其
  /// 规整为单行,属已知限制)。
  const NoSuchModelError({
    required this.modelId,
    required this.modelType,
    String? message,
    Object? cause,
  }) : super(
          message ??
              'No such '
                  '${modelType == ModelType.languageModel ? 'languageModel' : modelType == ModelType.embeddingModel ? 'embeddingModel' : modelType == ModelType.imageModel ? 'imageModel' : modelType == ModelType.transcriptionModel ? 'transcriptionModel' : modelType == ModelType.speechModel ? 'speechModel' : modelType == ModelType.rerankingModel ? 'rerankingModel' : 'videoModel'}'
                  ': $modelId',
          cause: cause,
        );

  /// 请求但未找到的模型 id。
  final String modelId;

  /// 缺失模型的模态类型。
  final ModelType modelType;
}

/// 请求了 registry 中不存在的 provider。
final class NoSuchProviderError extends NoSuchModelError {
  NoSuchProviderError({
    required super.modelId,
    required super.modelType,
    required this.providerId,
    required this.availableProviders,
    String? message,
    super.cause,
  }) : super(
          message:
              message ?? _noSuchProviderMessage(providerId, availableProviders),
        );

  /// 请求但未找到的 provider id。
  final String providerId;

  /// registry 中可用的 provider id 列表。
  final List<String> availableProviders;
}

String _noSuchProviderMessage(
  String providerId,
  List<String> availableProviders,
) =>
    'No such provider: $providerId '
    '(available providers: ${availableProviders.join(', ')})';

/// 请求了 provider 引用表中不存在的 provider。
final class NoSuchProviderReferenceError extends AiError {
  NoSuchProviderReferenceError({
    required this.provider,
    required this.reference,
    String? message,
    Object? cause,
  }) : super(
          message ?? _noSuchProviderReferenceMessage(provider, reference),
          cause: cause,
        );

  /// 请求但未找到的 provider 名。
  final String provider;

  /// 可用 provider 引用表。
  final ProviderReference reference;
}

String _noSuchProviderReferenceMessage(
  String provider,
  ProviderReference reference,
) =>
    "No provider reference found for provider '$provider'. "
    'Available providers: ${reference.keys.join(', ')}';

/// prompt 不合法(结构/内容无法被 provider 接受)。
final class InvalidPromptError extends AiError {
  const InvalidPromptError({
    required this.prompt,
    required String message,
    Object? cause,
  }) : super(message, cause: cause);

  /// 触发错误的 prompt(诊断用,类型不定)。
  final Object? prompt;
}

/// provider 不支持所请求的功能。
final class UnsupportedFunctionalityError extends AiError {
  const UnsupportedFunctionalityError({
    required this.functionality,
    String? message,
    Object? cause,
  }) : super(
          message ?? 'Unsupported functionality: $functionality',
          cause: cause,
        );

  /// 不受支持的功能名。
  final String functionality;
}

/// 调用参数不合法。
final class InvalidArgumentError extends AiError {
  const InvalidArgumentError({
    required this.argument,
    required String message,
    Object? cause,
  }) : super(message, cause: cause);

  /// 不合法的参数名。
  final String argument;
}

/// 响应数据不符合预期结构。
final class InvalidResponseDataError extends AiError {
  const InvalidResponseDataError({
    required this.data,
    String? message,
    Object? cause,
  }) : super(
          message ?? 'Invalid response data',
          cause: cause,
        );

  /// 触发错误的响应数据(诊断用,类型不定)。
  final Object? data;
}

/// JSON 文本解析失败。
final class JsonParseError extends AiError {
  const JsonParseError({
    required this.text,
    Object? cause,
    String? message,
  }) : super(
          message ?? 'Failed to parse JSON response',
          cause: cause,
        );

  /// 解析失败的原始文本。
  final String text;
}

/// 值与预期类型/模式不符。
final class TypeValidationError extends AiError {
  const TypeValidationError({
    required this.value,
    Object? cause,
    String? message,
  }) : super(
          message ?? 'Type validation failed',
          cause: cause,
        );

  /// 校验失败的值(诊断用,类型不定)。
  final Object? value;
}

/// 模型未产出任何内容。
final class NoContentGeneratedError extends AiError {
  const NoContentGeneratedError({
    String message = 'No content generated',
    Object? cause,
  }) : super(message, cause: cause);
}

/// The transcription model did not produce any transcript text.
final class NoTranscriptGeneratedError extends AiError {
  const NoTranscriptGeneratedError({
    this.responses = const <ResponseInfo>[],
    String message = 'No transcript generated.',
    Object? cause,
  }) : super(message, cause: cause);

  /// Provider responses that led to the empty transcript.
  final List<ResponseInfo> responses;
}

/// The speech model did not produce any audio bytes.
final class NoSpeechGeneratedError extends AiError {
  const NoSpeechGeneratedError({
    this.responses = const <ResponseInfo>[],
    String message = 'No speech generated.',
    Object? cause,
  }) : super(message, cause: cause);

  /// Provider responses that led to the empty audio.
  final List<ResponseInfo> responses;
}

/// The image model did not produce any image bytes.
final class NoImageGeneratedError extends AiError {
  const NoImageGeneratedError({
    this.responses = const <ResponseInfo>[],
    String message = 'No image generated.',
    Object? cause,
  }) : super(message, cause: cause);

  /// Provider responses that led to the empty image list.
  final List<ResponseInfo> responses;
}

/// The video model did not produce any video data.
final class NoVideoGeneratedError extends AiError {
  const NoVideoGeneratedError({
    this.responses = const <ResponseInfo>[],
    String message = 'No video generated.',
    Object? cause,
  }) : super(message, cause: cause);

  /// Provider responses that led to the empty video list.
  final List<ResponseInfo> responses;
}

/// No parsed output was available.
final class NoOutputGeneratedError extends AiError {
  const NoOutputGeneratedError({
    String message = 'No output generated.',
    Object? cause,
  }) : super(message, cause: cause);
}

/// The model did not produce a valid object output.
///
/// This covers three cases: no text response, JSON parse failure, and schema
/// validation failure. [text] is the raw model text when available.
final class NoObjectGeneratedError extends AiError {
  const NoObjectGeneratedError({
    String message = 'No object generated.',
    Object? cause,
    this.text,
    this.response,
    this.usage,
    this.finishReason,
  }) : super(message, cause: cause);

  final String? text;
  final ResponseInfo? response;
  final LanguageModelUsage? usage;
  final LanguageModelFinishReason? finishReason;
}

/// 期望有响应体但为空。
final class EmptyResponseBodyError extends AiError {
  const EmptyResponseBodyError({
    String message = 'Empty response body',
    Object? cause,
  }) : super(message, cause: cause);
}

/// 无法加载 API key(缺失或读取失败)。
final class LoadApiKeyError extends AiError {
  const LoadApiKeyError({
    required String message,
    Object? cause,
  }) : super(message, cause: cause);
}

/// 无法加载某项设置(缺失或读取失败)。
final class LoadSettingError extends AiError {
  const LoadSettingError({
    required String message,
    Object? cause,
  }) : super(message, cause: cause);
}

/// 单次 embedding 调用请求的值数量超过了模型的 [maxEmbeddingsPerCall] 上限。
///
/// 这是 `EmbeddingModel.doEmbed` 的**抛异常**路径:embedding 没有流式接口,
/// 不存在"错误即事件"的适用面;与 `Provider.languageModel` 遇到未知 id 抛
/// [NoSuchModelError] 同属"调用方用法错误"类——问题出在调用方传入的
/// `values` 长度,而非模型这一轮的生成结果。
///
/// 对齐上游 `@ai-sdk/provider` 的
/// `too-many-embedding-values-for-call-error.ts`(message 文案逐字对齐;
/// 上游用 `values: Array<unknown>` 持有完整原始值数组用于报告
/// `values.length`,本类主动偏离为 [valuesCount]:错误报告只需要"传了多少
/// 个值"这个数量事实,不需要保留可能很大的原始字符串负载)。
final class TooManyEmbeddingValuesForCallError extends AiError {
  TooManyEmbeddingValuesForCallError({
    required this.provider,
    required this.modelId,
    required this.maxEmbeddingsPerCall,
    required this.valuesCount,
  }) : super('Too many values for a single embedding call. '
            'The $provider model "$modelId" can only embed up to '
            '$maxEmbeddingsPerCall values per call, but $valuesCount values were provided.');

  /// 触发错误的 embedding provider 名。
  final String provider;

  /// 触发错误的 embedding 模型 id。
  final String modelId;

  /// 该模型单次调用允许的 embedding 数量上限。
  final int maxEmbeddingsPerCall;

  /// 调用方实际传入的值数量。
  final int valuesCount;
}
