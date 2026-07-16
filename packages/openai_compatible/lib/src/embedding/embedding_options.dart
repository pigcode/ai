import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:equatable/equatable.dart';

/// `providerOptions[providerOptionsName]` 的结构化值类(embedding wire 专用)。
///
/// 字段清单对齐 v7 `openaiCompatibleEmbeddingModelOptions` zod schema(raw
/// `compatible_emb__openai-compatible-embedding-model-options.ts`):
/// [dimensions] 与 [user] 两个可选字段。schema 值类型较上游收紧:
/// `dimensions` 声明 `'type': 'integer'`、`user` 声明 `'type': 'string'`
/// (与 chat 侧 `maxCompletionTokens` 先例一致)。与 `pigcode_ai_openai` 的
/// `OpenAiEmbeddingProviderOptions` **结构相同但类型独立**——provider 包
/// 互不依赖,即便字段集合相同也不抽取共享基类或共享 schema 常量。
///
/// **与 chat 侧的刻意差异——无未知键透传**:chat wire 有
/// `extractPassthroughProviderOptions` 把未知键透传进请求体,而上游 raw
/// embedding 完全没有透传机制(raw 模型文件全文无 `Object.fromEntries`/
/// 透传逻辑,请求体只有五个固定字段),故本类只解析 `dimensions`/`user`
/// 两个已知字段,未知键校验通过后直接丢弃——这是对照 raw 的忠实行为,
/// 不是遗漏。
///
/// 另:不移植 raw 的三路 `Object.assign`/deprecated key 解析
/// (`'openai-compatible'` 兼容键、`warnIfDeprecatedProviderOptionsKey`)
/// ——pigcode 单 key 裁决已在 chat wire 落地(见 `chat_options.dart` 文档),
/// embedding 沿用同一裁决,不重新引入。
final class OpenAiCompatibleEmbeddingProviderOptions with EquatableMixin {
  /// 构造一份 provider 选项值对象;所有字段均可缺省(对应"未显式设置")。
  const OpenAiCompatibleEmbeddingProviderOptions({this.dimensions, this.user});

  /// 输出 embedding 的维度数,wire 字段 `dimensions`。
  final int? dimensions;

  /// 终端用户标识,wire 字段 `user`。
  final String? user;

  /// 从契约 [ProviderOptions] 中解析并校验出一份 [providerOptionsName] 键
  /// 对应的选项。
  ///
  /// [options] 为 `null` 或不含 [providerOptionsName] 键时,返回全字段默认
  /// (`null`)的实例。存在该键时,先用 JSON Schema 做结构校验,失败时抛出
  /// 契约 `TypeValidationError`(原样冒泡,不在此处二次包装)。
  ///
  /// [providerOptionsName] **必填**且无默认值(与
  /// `OpenAiCompatibleChatProviderOptions.fromProviderOptions` 同构):本包
  /// 无 azure 式派生 key,provider 名由 `createOpenAiCompatible(name: …)`
  /// 在运行期指定,没有可硬编码的固定键,调用方必须显式传入。
  static OpenAiCompatibleEmbeddingProviderOptions fromProviderOptions(
    ProviderOptions? options, {
    required String providerOptionsName,
  }) {
    final raw = options?[providerOptionsName];
    if (raw == null) {
      return const OpenAiCompatibleEmbeddingProviderOptions();
    }

    final validationResult = _validator.validate(raw);
    if (validationResult is ValidationFailure) {
      throw validationResult.error;
    }
    final value = (validationResult as ValidationSuccess).value! as JsonObject;

    return OpenAiCompatibleEmbeddingProviderOptions(
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
