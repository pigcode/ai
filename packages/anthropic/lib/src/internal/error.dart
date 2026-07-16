import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

/// Anthropic 官方错误体
/// `{ type: 'error', error: { type, message } }` 的结构校验器。
///
/// 对照 raw `anthropic-error.ts:9-19` 的 `anthropicErrorDataSchema`
/// (报告 06 §1.1 四字段表):顶层 `type` 为字面量 `'error'`(zod
/// `z.literal('error')`,此处用 JSON Schema `const` 表达)、`error` 对象
/// 必填,`error.type` / `error.message` 均为必填字符串。
///
/// 上游 zod v4 默认 strip 未知键(校验通过后 `value` 中剥除额外键);
/// pigcode 的 `JsonSchemaValidator` 不删键、原值透传——差异仅在 data 的
/// 保留形态,校验通过性一致。
final JsonSchemaValidator anthropicErrorValidator =
    JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'type': <String, Object?>{'const': 'error'},
      'error': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'type': <String, Object?>{'type': 'string'},
          'message': <String, Object?>{'type': 'string'},
        },
        'required': <Object?>['type', 'message'],
      },
    },
    'required': <Object?>['type', 'error'],
  }),
);

/// 从已通过 [anthropicErrorValidator] 校验的 Anthropic 错误体 [error] 中
/// 提取人类可读消息。
///
/// 对照 raw `errorToMessage: data => data.error.message`(报告 06
/// §1.2)——只取 `error.message`,不拼接 `error.type`。调用方(经
/// `jsonErrorResponseHandler`)保证在校验通过后才调用本函数,故此处的
/// `!`/`as` 类型收窄是安全的。
String anthropicErrorToMessage(JsonValue error) {
  final root = error! as JsonObject;
  final errorObject = root['error']! as JsonObject;
  return errorObject['message']! as String;
}

/// 构造 Anthropic 官方错误体的 [FailedResponseHandler]。
///
/// 对照 raw(anthropic-error.ts:23-26):
/// ```typescript
/// export const anthropicFailedResponseHandler = createJsonErrorResponseHandler({
///   errorSchema: anthropicErrorDataSchema,
///   errorToMessage: data => data.error.message,
/// });
/// ```
/// 不传 `isRetryable`(上游同样未传)——重试判定完全落在契约
/// `ApiCallError` 的默认按状态码推断(408/409/429/≥500,报告 06 §1.4)。
/// `overloaded_error` 等 `error.type` 不参与重试判定,只影响 message。
/// 流式 HTTP 200 + error 事件的 529/500 合成属另一条路径(stream error
/// probe),与本 handler 无关。
FailedResponseHandler anthropicFailedResponseHandler() {
  return jsonErrorResponseHandler(
    validator: anthropicErrorValidator,
    errorToMessage: anthropicErrorToMessage,
  );
}
