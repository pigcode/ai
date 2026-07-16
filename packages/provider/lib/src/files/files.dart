import 'package:equatable/equatable.dart';

import '../shared/shared.dart';

/// files 接口规范版本。
const filesSpecVersion = 'v4';

/// provider 文件上传接口。
abstract interface class Files {
  /// files 接口规范版本。
  String get specificationVersion;

  /// provider 名,如 `'openai.files'`。
  String get provider;

  /// 上传文件并返回 provider 侧资源引用。
  Future<FilesUploadResult> uploadFile(FilesUploadOptions options);
}

/// [Files.uploadFile] 的调用参数。
final class FilesUploadOptions with EquatableMixin {
  const FilesUploadOptions({
    required this.data,
    required this.mediaType,
    this.filename,
    this.providerOptions,
  });

  /// 待上传的文件数据。
  final FileData data;

  /// IANA 媒体类型,如 `application/pdf`。
  final String mediaType;

  /// provider 侧可见的文件名。
  final String? filename;

  /// provider 私有选项(外层键为 provider 名)。
  final ProviderOptions? providerOptions;

  @override
  List<Object?> get props => <Object?>[
        data,
        mediaType,
        filename,
        providerOptions,
      ];
}

/// [Files.uploadFile] 的结果。
final class FilesUploadResult with EquatableMixin {
  const FilesUploadResult({
    required this.providerReference,
    this.mediaType,
    this.filename,
    this.providerMetadata,
    required this.warnings,
  });

  /// provider 侧资源引用。
  final ProviderReference providerReference;

  /// 上传后文件的媒体类型。
  final String? mediaType;

  /// 上传后文件名。
  final String? filename;

  /// provider 私有元数据。
  final ProviderMetadata? providerMetadata;

  /// 调用告警。
  final List<Warning> warnings;

  @override
  List<Object?> get props => <Object?>[
        providerReference,
        mediaType,
        filename,
        providerMetadata,
        warnings,
      ];
}
