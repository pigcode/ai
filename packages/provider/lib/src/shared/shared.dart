import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../json_value/json.dart';

/// provider 元数据映射:外层键为 provider 名,内层为该 provider 的元数据。
typedef ProviderMetadata = Map<String, JsonObject>;

/// provider 选项映射:外层键为 provider 名,内层为该 provider 的选项。
typedef ProviderOptions = Map<String, JsonObject>;

/// provider 侧资源引用:provider 名 → 该 provider 的文件/资源 id。
typedef ProviderReference = Map<String, String>;

/// HTTP 头映射:头名 → 头值。
typedef Headers = Map<String, String>;

/// 调用告警:随 stream-start 事件或生成结果一并携带。
sealed class Warning extends Equatable {
  const Warning();
}

/// 请求了模型不支持的能力(该能力被忽略)。
final class UnsupportedWarning extends Warning {
  const UnsupportedWarning(this.feature, {this.details});

  /// 被忽略的能力名称。
  final String feature;

  /// 可选的补充说明。
  final String? details;

  @override
  List<Object?> get props => <Object?>[feature, details];
}

/// 为兼容而对请求做了调整(能力被降级或改写)。
final class CompatibilityWarning extends Warning {
  const CompatibilityWarning(this.feature, {this.details});

  /// 受影响的能力名称。
  final String feature;

  /// 可选的补充说明。
  final String? details;

  @override
  List<Object?> get props => <Object?>[feature, details];
}

/// 使用了已废弃的设置。
final class DeprecatedWarning extends Warning {
  const DeprecatedWarning(this.setting, this.message);

  /// 被废弃的设置名称。
  final String setting;

  /// 面向调用方的说明文案。
  final String message;

  @override
  List<Object?> get props => <Object?>[setting, message];
}

/// 其他无法归类的告警。
final class OtherWarning extends Warning {
  const OtherWarning(this.message);

  /// 告警文案。
  final String message;

  @override
  List<Object?> get props => <Object?>[message];
}

/// 文件数据:把上游的 `Uint8Array | string` 等来源拆成类型安全的变体。
sealed class FileData extends Equatable {
  const FileData();
}

/// 生成/流式**输出**侧的文件数据子集:仅 bytes/base64/url(对齐 v7 输出侧
/// `SharedV4FileDataData | SharedV4FileDataUrl`)。`reference`/`text` 仅**输入**侧
/// (prompt / 工具结果)可用,不属此子集。
sealed class OutputFileData extends FileData {
  const OutputFileData();
}

/// 原始字节。
final class FileDataBytes extends OutputFileData {
  const FileDataBytes(this.bytes);

  /// 文件的原始字节。
  final Uint8List bytes;

  @override
  List<Object?> get props => <Object?>[bytes];
}

/// Base64 编码字符串。
final class FileDataBase64 extends OutputFileData {
  const FileDataBase64(this.base64);

  /// 文件内容的 Base64 编码。
  final String base64;

  @override
  List<Object?> get props => <Object?>[base64];
}

/// 远端 URL(命中 provider 支持模式时由其原生透传,不下载)。
final class FileDataUrl extends OutputFileData {
  const FileDataUrl(this.url);

  /// 文件的 URL。
  final Uri url;

  @override
  List<Object?> get props => <Object?>[url];
}

/// provider 侧文件引用(不携带字节,仅携带 provider 名 → 资源 id)。
final class FileDataReference extends FileData {
  const FileDataReference(this.reference);

  /// provider 侧的文件/资源引用。
  final ProviderReference reference;

  @override
  List<Object?> get props => <Object?>[reference];
}

/// 纯文本内容。
final class FileDataText extends FileData {
  const FileDataText(this.text);

  /// 文件的文本内容。
  final String text;

  @override
  List<Object?> get props => <Object?>[text];
}
