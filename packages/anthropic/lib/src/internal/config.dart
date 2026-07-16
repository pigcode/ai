import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;

/// Anthropic 官方 API 的裸域地址(不带版本段)。
const String _anthropicApiUrl = 'https://api.anthropic.com';

/// Anthropic 官方 API 的带版本默认地址。
const String _anthropicApiVersionedUrl = '$_anthropicApiUrl/v1';

/// `anthropic-beta` 请求头名称(报告 01 §6)。
const String anthropicBetaHeaderName = 'anthropic-beta';

/// `anthropic-version` 请求头的唯一版本值(anthropic-provider.ts:147)。
const String anthropicVersionHeaderValue = '2023-06-01';

/// Runtime configuration shared by Anthropic Messages, Files, and Skills
/// requests.
///
/// `AnthropicProvider` constructs instances for its models and resources;
/// callers may also use the public constructor directly.
final class AnthropicConfig {
  /// Creates runtime configuration from the supplied request settings.
  const AnthropicConfig({
    required this.providerName,
    required this.baseUrl,
    required this.headers,
    this.client,
  });

  /// Provider name used directly by Messages models.
  ///
  /// Resources remove a terminal `.messages` suffix when present, then append
  /// their resource suffix. Without that terminal suffix, they append the
  /// resource suffix directly. The providerOptions key is the first segment,
  /// `providerName.split('.').first`.
  final String providerName;

  /// Base URL for API requests, normalized by the caller with
  /// [resolveAnthropicBaseUrl].
  final String baseUrl;

  /// Header factory evaluated once per request, allowing credentials to rotate.
  final Map<String, String> Function() headers;

  /// Optional client shared by Messages, Files, and Skills requests.
  ///
  /// An injected client remains caller-owned. When `null`, the transport helper
  /// initiating the request creates and closes a temporary client.
  final http.Client? client;
}

/// 归一化 Anthropic baseURL(报告 01 §4.1,anthropic-provider.ts:24-37)。
///
/// 规则:先去掉尾部斜杠;若结果恰等于官方裸域
/// `https://api.anthropic.com` 则补 `/v1`;[baseUrl] 为 `null` 时回退默认
/// `https://api.anthropic.com/v1`;其余自定义地址原样返回(不补 `/v1`)。
///
/// 偏离上游:不读取 `ANTHROPIC_BASE_URL` 环境变量(pigcode 保持 web/wasm
/// 兼容,不读 env;需要 env 时调用方自行注入),优先级退化为
/// "显式参数 > 默认值"。
String resolveAnthropicBaseUrl(String? baseUrl) {
  final normalized = withoutTrailingSlash(baseUrl);
  if (normalized == null) {
    return _anthropicApiVersionedUrl;
  }
  if (normalized == _anthropicApiUrl) {
    return _anthropicApiVersionedUrl;
  }
  return normalized;
}

/// 解析一条 `anthropic-beta` 头的值为 beta 名称集合(报告 01 §6,
/// anthropic-language-model.ts:797-815)。
///
/// 语义:整体 `toLowerCase` 后按逗号切分、逐项 trim、丢弃空串,Set 自动
/// 去重;[headerValue] 为 `null` 时返回空集。messages 模型请求期用本助手
/// 从 config headers 与本次请求 headers 收集用户自带 betas。
Set<String> anthropicBetasFromHeaderValue(String? headerValue) {
  if (headerValue == null) {
    return <String>{};
  }
  return headerValue
      .toLowerCase()
      .split(',')
      .map((beta) => beta.trim())
      .where((beta) => beta.isNotEmpty)
      .toSet();
}

/// 把汇总后的 beta 集合合成为最终请求头(报告 01 §6,
/// anthropic-language-model.ts:783-795)。
///
/// [betas] 为空时返回空 Map(不发该头);非空时值为逗号 join、无空格。
Map<String, String> anthropicBetaHeader(Set<String> betas) {
  if (betas.isEmpty) {
    return const <String, String>{};
  }
  return <String, String>{anthropicBetaHeaderName: betas.join(',')};
}

/// 模型 `supportedUrls` getter 返回的原生可取 URL 声明(报告 01 §4.6)。
///
/// 仅 `image/*` 与 `application/pdf` 两类,均接受任意 http/https URL
/// (上游模式 `/^https?:\/\/.*$/`)。
Map<String, List<RegExp>> anthropicSupportedUrls() => <String, List<RegExp>>{
      'image/*': [RegExp(r'^https?://.*$')],
      'application/pdf': [RegExp(r'^https?://.*$')],
    };
