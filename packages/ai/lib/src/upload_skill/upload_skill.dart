import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../logger/log_warnings.dart';

/// `uploadSkill` 的结果。
final class UploadSkillResult {
  const UploadSkillResult({
    required this.providerReference,
    this.displayTitle,
    this.name,
    this.description,
    this.latestVersion,
    this.providerMetadata,
    required this.warnings,
  });

  /// provider 侧资源引用。
  final provider.ProviderReference providerReference;

  /// 人类可读标题。
  final String? displayTitle;

  /// provider 返回的 skill 名称。
  final String? name;

  /// provider 返回的 skill 描述。
  final String? description;

  /// provider 返回的最新版本标识。
  final String? latestVersion;

  /// provider 私有元数据。
  final provider.ProviderMetadata? providerMetadata;

  /// provider 侧告警。
  final List<provider.Warning> warnings;
}

/// 上传 skill 文件集到 provider 的 Skills 接口。
Future<UploadSkillResult> uploadSkill({
  required Object api,
  required List<provider.SkillFile> files,
  String? displayTitle,
  provider.ProviderOptions? providerOptions,
}) async {
  final skills = _resolveSkills(api);
  final result = await skills.uploadSkill(
    provider.SkillsUploadOptions(
      files: files,
      displayTitle: displayTitle,
      providerOptions: providerOptions,
    ),
  );
  logWarnings(
    warnings: result.warnings,
    provider: skills.provider,
  );

  return UploadSkillResult(
    providerReference: result.providerReference,
    displayTitle: result.displayTitle,
    name: result.name,
    description: result.description,
    latestVersion: result.latestVersion,
    providerMetadata: result.providerMetadata,
    warnings: result.warnings,
  );
}

provider.Skills _resolveSkills(Object api) {
  if (api is provider.Skills) {
    return api;
  }
  if (api is provider.Provider) {
    return api.skills();
  }
  throw provider.InvalidArgumentError(
    argument: 'api',
    message: 'uploadSkill api must be a Skills or Provider instance.',
  );
}
