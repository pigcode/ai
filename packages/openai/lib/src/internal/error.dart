import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

/// OpenAI 官方错误体 `{ error: { message, type?, param?, code? } }` 的
/// 结构校验器。
///
/// 对照 raw `openai-error.ts` 的 `openaiErrorDataSchema`:`message` 必填
/// 字符串;`type`/`param`/`code` 均为宽松可选字段(`param` 可以是字符串/
/// 对象/数组等任意形状,`code` 可以是字符串或数字),故本 schema 只约束
/// `error.message` 为必填字符串,其余字段不写进 schema、不做任何类型
/// 收窄——保持与上游同等宽松,以兼容行为略有差异的 OpenAI 兼容第三方
/// 响应体。
final JsonSchemaValidator openAiErrorValidator =
    JsonSchemaValidator.fromContract(
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

/// 从已通过 [openAiErrorValidator] 校验的 OpenAI 错误体 [error] 中提取
/// 人类可读消息。
///
/// 对照 raw `errorToMessage: data => data.error.message`——只取
/// `error.message`,不拼接 `type`/`code`/`param`。调用方(经
/// `jsonErrorResponseHandler`)保证在校验通过后才调用本函数,故此处的
/// `!`/`as` 类型收窄是安全的。
String openAiErrorToMessage(JsonValue error) {
  final root = error! as JsonObject;
  final errorObject = root['error']! as JsonObject;
  return errorObject['message']! as String;
}

/// 构造 OpenAI 官方错误体的 [FailedResponseHandler]。
///
/// 对照 raw:
/// ```typescript
/// export const openaiFailedResponseHandler = createJsonErrorResponseHandler({
///   errorSchema: openaiErrorDataSchema,
///   errorToMessage: data => data.error.message,
/// });
/// ```
/// 不传 `isRetryable`——完全依赖 utils `jsonErrorResponseHandler` /
/// 契约 `ApiCallError.isRetryable` 的默认按状态码推断(408/409/429/5xx),
/// 与上游"openai 包对 chat completions 完全依赖 APICallError 默认推断"
/// 的策略一致(调研报告 `errors-metadata.md` §1.1/§3)。
FailedResponseHandler openAiFailedResponseHandler() {
  return jsonErrorResponseHandler(
    validator: openAiErrorValidator,
    errorToMessage: openAiErrorToMessage,
  );
}
