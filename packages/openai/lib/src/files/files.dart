import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http_parser/http_parser.dart';
import 'package:http/http.dart' as http;

import '../internal/config.dart';
import '../internal/error.dart';
import '../internal/provider_options.dart';
import 'files_options.dart';

/// OpenAI Files(`/files`)的 [Files] 实现。
final class OpenAiFiles implements Files {
  OpenAiFiles({required this.config});

  /// 共享的 provider 配置(baseUrl/headers/client)。
  final OpenAiConfig config;

  @override
  String get specificationVersion => filesSpecVersion;

  @override
  String get provider => '${config.providerName}.files';

  Uri get _requestUrl => Uri.parse('${config.baseUrl}/files');

  @override
  Future<FilesUploadResult> uploadFile(FilesUploadOptions options) async {
    final openAiOptions = OpenAiFilesProviderOptions.fromProviderOptions(
      resolveOpenAiProviderOptions(
          config.providerName, options.providerOptions),
    );
    final fileBytes = fileDataToBytes(options.data, argument: 'data');

    final response = await postMultipartToApi<_OpenAiFilesResponse>(
      url: _requestUrl,
      headers: combineHeaders([config.headers()]),
      build: (request) {
        request
          ..fields['purpose'] = openAiOptions.purpose ?? 'assistants'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              fileBytes,
              filename: options.filename ?? 'blob',
              contentType: MediaType.parse(options.mediaType),
            ),
          );
        final expiresAfter = openAiOptions.expiresAfter;
        if (expiresAfter != null) {
          request
            ..fields['expires_after[anchor]'] = 'created_at'
            ..fields['expires_after[seconds]'] = expiresAfter.toString();
        }
      },
      successHandler: jsonResponseHandler<_OpenAiFilesResponse>(
        decode: _decodeOpenAiFilesResponse,
      ),
      failureHandler: openAiFailedResponseHandler(),
      client: config.client,
    );

    final metadataKey = resolveOpenAiProviderOptionsName(config.providerName);
    return FilesUploadResult(
      providerReference: {metadataKey: response.id},
      mediaType: options.mediaType,
      filename: response.filename ?? options.filename,
      providerMetadata: {
        metadataKey: {
          if (response.filename != null) 'filename': response.filename,
          if (response.purpose != null) 'purpose': response.purpose,
          if (response.bytes != null) 'bytes': response.bytes,
          if (response.createdAt != null) 'createdAt': response.createdAt,
          if (response.status != null) 'status': response.status,
          if (response.expiresAt != null) 'expiresAt': response.expiresAt,
        },
      },
      warnings: const [],
    );
  }
}

final class _OpenAiFilesResponse {
  const _OpenAiFilesResponse({
    required this.id,
    this.bytes,
    this.createdAt,
    this.filename,
    this.purpose,
    this.status,
    this.expiresAt,
  });

  final String id;
  final int? bytes;
  final int? createdAt;
  final String? filename;
  final String? purpose;
  final String? status;
  final int? expiresAt;
}

_OpenAiFilesResponse _decodeOpenAiFilesResponse(JsonValue json) {
  if (json case final JsonObject root) {
    final id = root['id'];
    if (id is! String) {
      throw InvalidResponseDataError(data: json);
    }
    return _OpenAiFilesResponse(
      id: id,
      bytes: _optionalInt(root, 'bytes'),
      createdAt: _optionalInt(root, 'created_at'),
      filename: _optionalString(root, 'filename'),
      purpose: _optionalString(root, 'purpose'),
      status: _optionalString(root, 'status'),
      expiresAt: _optionalInt(root, 'expires_at'),
    );
  }
  throw InvalidResponseDataError(data: json);
}

String? _optionalString(JsonObject root, String key) {
  final value = root[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw InvalidResponseDataError(data: root);
}

int? _optionalInt(JsonObject root, String key) {
  final value = root[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toInt();
  }
  throw InvalidResponseDataError(data: root);
}
