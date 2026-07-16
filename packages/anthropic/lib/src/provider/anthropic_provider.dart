import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;

import '../files/files.dart';
import '../internal/config.dart';
import '../messages/messages_language_model.dart';
import '../skills/skills.dart';

/// 本包版本号,固定拼接进 User-Agent 后缀。
///
/// 纯 Dart 没有读取自身 `pubspec.yaml` 的轻量手段(无 `dart:mirrors`/
/// `package_info` 等价物),故硬编码;需与 `packages/anthropic/pubspec.yaml`
/// 的 `version` 字段保持一致(openai 包同为手写 `0.0.1` 约定)。
const _packageVersion = '0.0.1';

/// 创建一个 Anthropic provider 实例。
///
/// 认证二选一(报告 01 §4.3,anthropic-provider.ts:125-132):[apiKey] 走
/// `x-api-key` 头,[authToken] 走 `Authorization: Bearer` 头;两者同时提供
/// 时立即抛 [ArgumentError](互斥检查是 eager 的,仅检查显式参数——pigcode
/// 不读环境变量,上游"env 组合豁免"的问题在此自然成立)。都不传时构造
/// 不抛,headers 惰性求值:直到实际发请求时才经 [loadApiKey] 抛出契约
/// `LoadApiKeyError`(报告 01 §4.4 末段;authToken 同样不读 env,需要 env
/// 时调用方自行注入)。
///
/// [baseUrl] 经 [resolveAnthropicBaseUrl] 归一化(缺省官方地址,裸域自动
/// 补 `/v1`)。[headers] 为调用方自定义头,合并顺序上覆盖前面的默认头
/// (经 [combineHeaders] 语义);其中 `User-Agent` 例外——固定后缀恒
/// **追加**在调用方提供值之后而非覆盖(见 `_withUserAgentSuffix`)。
/// [client] 可选注入,贯穿到 Messages、Files 与 Skills 的 HTTP 调用。
AnthropicProvider createAnthropic({
  String? apiKey,
  String? authToken,
  String? baseUrl,
  Map<String, String>? headers,
  String name = 'anthropic.messages',
  http.Client? client,
}) {
  if (apiKey != null && authToken != null) {
    throw ArgumentError(
      'Both apiKey and authToken were provided. '
      'Please use only one authentication method.',
    );
  }

  final resolvedBaseUrl = resolveAnthropicBaseUrl(baseUrl);

  Map<String, String> getHeaders() {
    // 认证头组装顺序照上游 anthropic-provider.ts:134-153:authToken 优先
    // 走 Bearer;否则 apiKey 经 loadApiKey 校验后走 x-api-key。
    final auth = authToken != null
        ? {'Authorization': 'Bearer $authToken'}
        : {
            'x-api-key':
                loadApiKey(apiKey: apiKey, settingName: 'Anthropic API key'),
          };
    final base = combineHeaders([
      {
        'anthropic-version': anthropicVersionHeaderValue,
        ...auth,
      },
      headers,
    ]);
    return _withUserAgentSuffix(base, 'pigcode_ai_anthropic/$_packageVersion');
  }

  return AnthropicProvider._(
    providerName: name,
    baseUrl: resolvedBaseUrl,
    getHeaders: getHeaders,
    client: client,
  );
}

/// 把 [suffix] 追加到 [headers] 的 `User-Agent` 值末尾(空格分隔);若
/// 尚无 `User-Agent`,则新建一个只含 [suffix] 的值。
///
/// 照抄 openai 包同名私有实现的"追加而非覆盖"语义——`combineHeaders`
/// 是后者覆盖前者,若直接用它拼 UA 会让调用方通过
/// `headers: {'User-Agent': ...}` 传入的自定义 UA 被固定后缀覆盖丢失。
Map<String, String> _withUserAgentSuffix(
  Map<String, String> headers,
  String suffix,
) {
  final result = Map<String, String>.of(headers);
  String? current;
  for (final name in result.keys.toList()) {
    if (name.toLowerCase() == 'user-agent') {
      current = result.remove(name);
    }
  }
  result['User-Agent'] =
      (current == null || current.isEmpty) ? suffix : '$current $suffix';
  return result;
}

/// Anthropic provider:分派出 Messages、Files 与 Skills API 实现。
///
/// [languageModel]/[chat]/[messages] 三别名提供语言模型(照上游
/// :187-189),[files]/[skills] 提供对应 resource;其余六个模态抛
/// [NoSuchModelError]。
final class AnthropicProvider implements Provider {
  AnthropicProvider._({
    required String providerName,
    required String baseUrl,
    required Map<String, String> Function() getHeaders,
    required http.Client? client,
  })  : _providerName = providerName,
        _baseUrl = baseUrl,
        _getHeaders = getHeaders,
        _client = client;

  final String _providerName;
  final String _baseUrl;
  final Map<String, String> Function() _getHeaders;
  final http.Client? _client;

  @override
  String get specificationVersion => providerSpecVersion;

  AnthropicConfig get _config => AnthropicConfig(
        providerName: _providerName,
        baseUrl: _baseUrl,
        headers: _getHeaders,
        client: _client,
      );

  @override
  LanguageModel languageModel(String modelId) => messages(modelId);

  /// [messages] 的别名(照上游三别名并存)。
  LanguageModel chat(String modelId) => messages(modelId);

  /// 创建一个 Messages(`/v1/messages`)语言模型。
  LanguageModel messages(String modelId) =>
      AnthropicMessagesLanguageModel(modelId, config: _config);

  @override
  EmbeddingModel embeddingModel(String modelId) {
    throw NoSuchModelError(
      modelId: modelId,
      modelType: ModelType.embeddingModel,
    );
  }

  @override
  ImageModel imageModel(String modelId) {
    throw NoSuchModelError(
      modelId: modelId,
      modelType: ModelType.imageModel,
    );
  }

  @override
  TranscriptionModel transcriptionModel(String modelId) {
    throw NoSuchModelError(
      modelId: modelId,
      modelType: ModelType.transcriptionModel,
    );
  }

  @override
  SpeechModel speechModel(String modelId) {
    throw NoSuchModelError(
      modelId: modelId,
      modelType: ModelType.speechModel,
    );
  }

  @override
  VideoModel videoModel(String modelId) {
    throw NoSuchModelError(
      modelId: modelId,
      modelType: ModelType.videoModel,
    );
  }

  @override
  RerankingModel rerankingModel(String modelId) {
    throw NoSuchModelError(
      modelId: modelId,
      modelType: ModelType.rerankingModel,
    );
  }

  @override
  Files files() => AnthropicFiles(config: _config);

  @override
  Skills skills() => AnthropicSkills(config: _config);
}
