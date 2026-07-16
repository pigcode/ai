import 'package:equatable/equatable.dart';

import '../shared/shared.dart';

/// skills 接口规范版本。
const skillsSpecVersion = 'v4';

/// provider skill 上传接口。
abstract interface class Skills {
  /// skills 接口规范版本。
  String get specificationVersion;

  /// provider 名,如 `'openai.skills'`。
  String get provider;

  /// 上传 skill 文件集并返回 provider 侧资源引用。
  Future<SkillsUploadResult> uploadSkill(SkillsUploadOptions options);
}

/// skill 内的单个文件。
final class SkillFile with EquatableMixin {
  const SkillFile({
    required this.path,
    required this.data,
  });

  /// 相对于 skill 根目录的文件路径。
  final String path;

  /// 文件数据。
  final FileData data;

  @override
  List<Object?> get props => <Object?>[path, data];
}

/// [Skills.uploadSkill] 的调用参数。
final class SkillsUploadOptions with EquatableMixin {
  const SkillsUploadOptions({
    required this.files,
    this.displayTitle,
    this.providerOptions,
  });

  /// 组成 skill 的文件。
  final List<SkillFile> files;

  /// 可选的人类可读标题。
  final String? displayTitle;

  /// provider 私有选项(外层键为 provider 名)。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => <Object?>[files, displayTitle, providerOptions];
}

/// [Skills.uploadSkill] 的结果。
final class SkillsUploadResult with EquatableMixin {
  const SkillsUploadResult({
    required this.providerReference,
    this.displayTitle,
    this.name,
    this.description,
    this.latestVersion,
    this.providerMetadata,
    required this.warnings,
  });

  /// provider 侧资源引用。
  final ProviderReference providerReference;

  /// 人类可读标题。
  final String? displayTitle;

  /// provider 返回的 skill 名称。
  final String? name;

  /// provider 返回的 skill 描述。
  final String? description;

  /// provider 返回的最新版本标识。
  final String? latestVersion;

  /// provider 私有元数据。
  final ProviderMetadata? providerMetadata;

  /// 调用告警。
  final List<Warning> warnings;

  @override
  List<Object?> get props => <Object?>[
        providerReference,
        displayTitle,
        name,
        description,
        latestVersion,
        providerMetadata,
        warnings,
      ];
}
