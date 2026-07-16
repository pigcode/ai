import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:equatable/equatable.dart';

/// `providerOptions['openai']` 的结构化值类(embedding wire 专用)。
///
/// 字段清单对齐 v7 `openaiEmbeddingModelOptions` zod schema(raw
/// `openai_emb__openai-embedding-model-options.ts`):`dimensions` 与
/// `user` 两个可选字段。schema 值类型较上游收紧:`dimensions` 声明
/// `'type': 'integer'`(维度数必然是整数;照 `chat_options.dart`
/// `maxCompletionTokens` 先例)、`user` 声明 `'type': 'string'`。
final class OpenAiEmbeddingProviderOptions with EquatableMixin {
  /// 构造一份 provider 选项值对象;所有字段均可缺省(对应"未显式设置")。
  const OpenAiEmbeddingProviderOptions({this.dimensions, this.user});

  /// 输出 embedding 的维度数,wire 字段 `dimensions`(仅
  /// text-embedding-3 及之后的模型支持)。
  final int? dimensions;

  /// 终端用户标识,wire 字段 `user`。
  final String? user;

  /// 从契约 [ProviderOptions] 中解析并校验出一份 `openai` 键对应的选项。
  ///
  /// [options] 为 `null` 或不含 `'openai'` 键时,返回全字段默认(`null`)的
  /// 实例。存在 `'openai'` 键时,先用 JSON Schema 做结构校验(字段类型),
  /// 失败时抛出契约 `TypeValidationError`(原样冒泡,不在此处二次包装)。
  ///
  /// 本方法固定读 `'openai'` 键(与 `OpenAiChatProviderOptions.
  /// fromProviderOptions` 签名同构);azure 派生 key 的重映射由调用方
  /// (`embedding_model.dart`)先经 `resolveOpenAiProviderOptions` 完成,
  /// 见 `provider_options.dart` 文档。
  factory OpenAiEmbeddingProviderOptions.fromProviderOptions(
    ProviderOptions? options,
  ) {
    final raw = options?['openai'];
    if (raw == null) {
      return const OpenAiEmbeddingProviderOptions();
    }

    final validationResult = _validator.validate(raw);
    if (validationResult is ValidationFailure) {
      throw validationResult.error;
    }
    final value = (validationResult as ValidationSuccess).value! as JsonObject;

    return OpenAiEmbeddingProviderOptions(
      dimensions: value['dimensions'] as int?,
      user: value['user'] as String?,
    );
  }

  @override
  List<Object?> get props => [dimensions, user];
}

final JsonSchemaValidator _validator = JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'dimensions': <String, Object?>{'type': 'integer'},
      'user': <String, Object?>{'type': 'string'},
    },
    'additionalProperties': true,
  }),
);
