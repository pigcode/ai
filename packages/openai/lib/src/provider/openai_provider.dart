import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;

import '../chat/chat_language_model.dart';
import '../internal/config.dart';
import '../embedding/embedding_model.dart';
import '../files/files.dart';
import '../image/image_model.dart';
import '../skills/skills.dart';
import '../speech/speech_model.dart';
import '../transcription/transcription_model.dart';
import '../responses/responses_language_model.dart';

/// 本包版本号,固定拼接进 User-Agent 后缀。
///
/// 纯 Dart 没有读取自身 `pubspec.yaml` 的轻量手段(无 `dart:mirrors`/
/// `package_info` 等价物),故硬编码;需与 `packages/openai/pubspec.yaml`
/// 的 `version` 字段保持一致(`pigcode_ai_provider`/`pigcode_ai_provider_utils`
/// 亦是同样的手写 `0.0.1` 约定)。
const _packageVersion = '0.0.1';

/// OpenAI 官方 API 的默认 base URL。
const _defaultBaseUrl = 'https://api.openai.com/v1';

/// 创建一个 OpenAI provider 实例。
///
/// [apiKey] 缺失时经 [loadApiKey] 抛出契约 `LoadApiKeyError`(在每次
/// 求值 headers 时才会真正触发,而非本函数调用时——与 v7 的惰性 header
/// 求值语义一致,便于 provider 实例先构造、apiKey 校验推迟到实际发起
/// 请求前)。[baseUrl] 缺省为官方地址,经 [withoutTrailingSlash] 去除
/// 唯一一个尾部斜杠。[organization]/[project] 非空时分别追加
/// `OpenAI-Organization`/`OpenAI-Project` 头。[headers] 为调用方自定义头,
/// 合并顺序上覆盖前面的默认头(经 [combineHeaders] 语义);其中
/// `User-Agent` 例外——固定后缀恒**追加**在调用方提供值之后而非覆盖
/// (见 `_withUserAgentSuffix`)。[client] 可选注入,贯穿到两套 wire 的
/// HTTP 调用。
OpenAiProvider createOpenAi({
  required String apiKey,
  String? baseUrl,
  String? organization,
  String? project,
  Map<String, String>? headers,
  String name = 'openai',
  http.Client? client,
}) {
  if (baseUrl != null && baseUrl.isEmpty) {
    throw const InvalidArgumentError(
      argument: 'baseUrl',
      message: 'baseUrl must be a non-empty string.',
    );
  }
  final resolvedBaseUrl = withoutTrailingSlash(baseUrl) ?? _defaultBaseUrl;

  Map<String, String> getHeaders() {
    final resolvedApiKey = loadApiKey(
      apiKey: apiKey,
      settingName: 'OpenAI API key',
    );
    final base = combineHeaders([
      {
        'Authorization': 'Bearer $resolvedApiKey',
        'OpenAI-Organization': organization,
        'OpenAI-Project': project,
      },
      headers,
    ]);
    return _withUserAgentSuffix(base, 'pigcode_ai_openai/$_packageVersion');
  }

  return OpenAiProvider._(
    providerName: name,
    baseUrl: resolvedBaseUrl,
    getHeaders: getHeaders,
    client: client,
  );
}

/// 把 [suffix] 追加到 [headers] 的 `User-Agent` 值末尾(空格分隔);若
/// 尚无 `User-Agent`,则新建一个只含 [suffix] 的值。
///
/// 照抄上游 `withUserAgentSuffix`(`scratchpad/v7research-provider-utils/
/// with-user-agent-suffix.ts`)的“追加而非覆盖”语义——`pigcode_ai_provider_utils`
/// 未提供等价工具(`combineHeaders` 是後者覆盖前者,若直接用它拼 UA 会让
/// 调用方通过 `headers: {'User-Agent': ...}` 传入的自定义 UA 被固定后缀
/// 覆盖丢失),故在本文件内自行实现,不改动 utils。
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

/// OpenAI provider:按 wire 协议分派出 [LanguageModel] 实现。
///
/// [languageModel] 默认指向 Responses API(与当前上游语义一致);
/// Chat Completions 需显式调用 [chat]。
final class OpenAiProvider implements Provider {
  OpenAiProvider._({
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

  OpenAiConfig get _config => OpenAiConfig(
        providerName: _providerName,
        baseUrl: _baseUrl,
        headers: _getHeaders,
        client: _client,
      );

  @override
  LanguageModel languageModel(String modelId) => responses(modelId);

  /// 创建一个 Chat Completions(`/chat/completions`)语言模型。
  LanguageModel chat(String modelId) =>
      OpenAiChatLanguageModel(modelId, config: _config);

  /// 创建一个 Responses(`/responses`)语言模型。
  LanguageModel responses(String modelId) =>
      OpenAiResponsesLanguageModel(modelId, config: _config);

  /// 创建一个 Embeddings(`/embeddings`)embedding 模型。
  @override
  EmbeddingModel embeddingModel(String modelId) =>
      OpenAiEmbeddingModel(modelId, config: _config);

  /// 创建一个 Images(`/images/generations`)image 模型。
  @override
  ImageModel imageModel(String modelId) =>
      OpenAiImageModel(modelId, config: _config);

  /// 创建一个 Audio Transcriptions(`/audio/transcriptions`)transcription 模型。
  @override
  TranscriptionModel transcriptionModel(String modelId) =>
      OpenAiTranscriptionModel(modelId, config: _config);

  /// 创建一个 Audio Speech(`/audio/speech`)speech 模型。
  @override
  SpeechModel speechModel(String modelId) =>
      OpenAiSpeechModel(modelId, config: _config);

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

  /// 创建 OpenAI Files(`/files`)上传接口。
  @override
  Files files() => OpenAiFiles(config: _config);

  /// 创建 OpenAI Skills(`/skills`)上传接口。
  @override
  Skills skills() => OpenAiSkills(config: _config);
}
