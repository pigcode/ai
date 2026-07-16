import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;

/// 错误体结构可插拔契约类型。
///
/// 逐字对齐 raw `compatible__openai-compatible-error.ts` 的
/// `ProviderErrorStructure<T>`:Dart 侧无泛型 schema 推断,[validator]
/// 校验通过后,[errorToMessage] 拿到的是原始 [JsonValue](不做类型转换)。
/// [isRetryable] 签名对照 `pigcode_ai_provider_utils`
/// `jsonErrorResponseHandler` 现用回调形状
/// `bool Function(http.StreamedResponse, JsonValue?)`(已沙盒验证;骨架
/// 契约草稿中的 `(int statusCode, JsonValue?)` 系尚未核对 utils 实际签名
/// 前的占位猜测,以本文件为准)。
final class ProviderErrorStructure {
  const ProviderErrorStructure({
    required this.validator,
    required this.errorToMessage,
    this.isRetryable,
  });

  /// 错误体结构校验器。
  final JsonSchemaValidator validator;

  /// 从已通过 [validator] 校验的错误体中提取人类可读消息。
  final String Function(JsonValue error) errorToMessage;

  /// 可选的可重试性覆盖;未提供时由契约 `ApiCallError.isRetryable` 按
  /// 状态码默认推断(408/409/429/5xx)。
  final bool Function(http.StreamedResponse response, JsonValue? error)?
      isRetryable;
}

/// OpenAI 官方错误体 `{ error: { message, type?, param?, code? } }` 的
/// 结构校验器。
///
/// 对照 raw `compatible__openai-compatible-error.ts` 的
/// `openaiCompatibleErrorDataSchema`:`error.message` 必填字符串;
/// `type`/`param`/`code` 均为宽松可选字段("handled loosely to support
/// OpenAI-compatible providers that have slightly different error
/// responses"),故本 schema 只约束 `error.message` 为必填字符串,其余
/// 字段不写进 schema、不做任何类型收窄。
final JsonSchemaValidator _defaultValidator = JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'error': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'message': <String, Object?>{'type': 'string'},
        },
        'required': <Object?>['message'],
      },
    },
    'required': <Object?>['error'],
  }),
);

/// 从已通过 [_defaultValidator] 校验的默认结构错误体中提取消息。
///
/// 对照 raw `errorToMessage: data => data.error.message`——只取
/// `error.message`,不拼接 `type`/`code`/`param`。调用方(经
/// `jsonErrorResponseHandler`)保证在校验通过后才调用本函数,故此处的
/// `!`/`as` 类型收窄是安全的。
String _defaultErrorToMessage(JsonValue error) {
  final root = error! as JsonObject;
  final errorObject = root['error']! as JsonObject;
  return errorObject['message']! as String;
}

/// 默认 OpenAI 风格错误结构。
///
/// 对照 raw `defaultOpenAICompatibleErrorStructure`:不提供
/// `isRetryable`,完全依赖契约 `ApiCallError.isRetryable` 的默认按状态码
/// 推断。
final ProviderErrorStructure defaultOpenAiCompatibleErrorStructure =
    ProviderErrorStructure(
  validator: _defaultValidator,
  errorToMessage: _defaultErrorToMessage,
);

/// 由 [structure] 构造 utils 的失败响应 handler。
///
/// 对照 `packages/openai/lib/src/error.dart` 的
/// `openAiFailedResponseHandler` 用法,本函数是其参数化版本:把硬编码的
/// `openAiErrorValidator`/`openAiErrorToMessage` 换成 [structure] 携带的
/// 字段,并把 [ProviderErrorStructure.isRetryable] 原样转发给
/// `jsonErrorResponseHandler` 的同名具名参数——可插拔性完全由参数化
/// 天然解决,`pigcode_ai_provider_utils` 零改动。
FailedResponseHandler openAiCompatibleFailedResponseHandler(
  ProviderErrorStructure structure,
) {
  return jsonErrorResponseHandler(
    validator: structure.validator,
    errorToMessage: structure.errorToMessage,
    isRetryable: structure.isRetryable,
  );
}
