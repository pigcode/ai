import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../logger/log_warnings.dart';

/// `uploadFile` 的结果。
final class UploadFileResult {
  const UploadFileResult({
    required this.providerReference,
    this.mediaType,
    this.filename,
    this.providerMetadata,
    required this.warnings,
  });

  /// provider 侧资源引用。
  final provider.ProviderReference providerReference;

  /// 上传后文件的媒体类型。
  final String? mediaType;

  /// 上传后文件名。
  final String? filename;

  /// provider 私有元数据。
  final provider.ProviderMetadata? providerMetadata;

  /// provider 侧告警。
  final List<provider.Warning> warnings;
}

/// 上传文件到 provider 的 Files 接口。
Future<UploadFileResult> uploadFile({
  required Object api,
  required provider.FileData data,
  String? mediaType,
  String? filename,
  provider.ProviderOptions? providerOptions,
}) async {
  final files = _resolveFiles(api);
  final uploadData = _ensureUploadFileData(data);
  final result = await files.uploadFile(
    provider.FilesUploadOptions(
      data: uploadData,
      mediaType: mediaType ?? _detectMediaType(uploadData),
      filename: filename,
      providerOptions: providerOptions,
    ),
  );
  logWarnings(
    warnings: result.warnings,
    provider: files.provider,
  );

  return UploadFileResult(
    providerReference: result.providerReference,
    mediaType: result.mediaType,
    filename: result.filename,
    providerMetadata: result.providerMetadata,
    warnings: result.warnings,
  );
}

provider.Files _resolveFiles(Object api) {
  if (api is provider.Files) {
    return api;
  }
  if (api is provider.Provider) {
    return api.files();
  }
  throw provider.InvalidArgumentError(
    argument: 'api',
    message: 'uploadFile api must be a Files or Provider instance.',
  );
}

provider.FileData _ensureUploadFileData(provider.FileData data) {
  return switch (data) {
    provider.FileDataBytes() ||
    provider.FileDataBase64() ||
    provider.FileDataText() =>
      data,
    provider.FileDataUrl() ||
    provider.FileDataReference() =>
      throw provider.InvalidArgumentError(
        argument: 'data',
        message:
            'uploadFile data must be FileDataBytes, FileDataBase64, or FileDataText.',
      ),
  };
}

String _detectMediaType(provider.FileData data) {
  return switch (data) {
    provider.FileDataText() => 'text/plain',
    provider.FileDataBytes(:final bytes) =>
      _detectBytesMediaType(bytes) ?? 'application/octet-stream',
    provider.FileDataBase64(:final base64) =>
      _detectBase64MediaType(base64) ?? 'application/octet-stream',
    provider.FileDataUrl() ||
    provider.FileDataReference() =>
      'application/octet-stream',
  };
}

String? _detectBase64MediaType(String base64) {
  try {
    return _detectBytesMediaType(base64Decode(base64));
  } on FormatException {
    return null;
  }
}

String? _detectBytesMediaType(Uint8List bytes) {
  if (_hasPrefix(bytes, const <int>[0x25, 0x50, 0x44, 0x46])) {
    return 'application/pdf';
  }
  if (_hasPrefix(bytes, const <int>[0x89, 0x50, 0x4e, 0x47])) {
    return 'image/png';
  }
  if (_hasPrefix(bytes, const <int>[0xff, 0xd8, 0xff])) {
    return 'image/jpeg';
  }
  if (bytes.length >= 12 &&
      _hasPrefix(bytes, const <int>[0x52, 0x49, 0x46, 0x46]) &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  if (_hasPrefix(bytes, const <int>[0x47, 0x49, 0x46, 0x38])) {
    return 'image/gif';
  }
  if (_isLikelyText(bytes)) {
    return 'text/plain';
  }
  return null;
}

bool _hasPrefix(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) {
      return false;
    }
  }
  return true;
}

bool _isLikelyText(Uint8List bytes) {
  final checkLength = bytes.length < 512 ? bytes.length : 512;
  if (checkLength == 0) {
    return false;
  }
  for (var i = 0; i < checkLength; i++) {
    final byte = bytes[i];
    if (byte == 0x00 ||
        (byte < 0x20 && byte != 0x09 && byte != 0x0a && byte != 0x0d)) {
      return false;
    }
  }
  return true;
}
