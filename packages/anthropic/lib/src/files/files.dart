import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http_parser/http_parser.dart';
import 'package:http/http.dart' as http;

import '../internal/config.dart';
import '../internal/error.dart';
import '../internal/resource_utils.dart';

final JsonSchemaValidator _anthropicFilesResponseValidator =
    JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'id': <String, Object?>{'type': 'string'},
      'type': <String, Object?>{'const': 'file'},
      'filename': <String, Object?>{'type': 'string'},
      'mime_type': <String, Object?>{'type': 'string'},
      'size_bytes': <String, Object?>{'type': 'integer'},
      'created_at': <String, Object?>{'type': 'string'},
      'downloadable': <String, Object?>{
        'type': <Object?>['boolean', 'null'],
      },
      'scope': <String, Object?>{
        'oneOf': <Object?>[
          <String, Object?>{'type': 'null'},
          <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'type': <String, Object?>{'type': 'string'},
              'id': <String, Object?>{'type': 'string'},
            },
            'required': <Object?>['type', 'id'],
          },
        ],
      },
    },
    'required': <Object?>[
      'id',
      'type',
      'filename',
      'mime_type',
      'size_bytes',
      'created_at',
    ],
  }),
);

/// Anthropic Files(`/files`)的 [Files] 实现。
final class AnthropicFiles implements Files {
  AnthropicFiles({required this.config});

  /// 共享的 provider 配置(baseUrl/headers/client)。
  final AnthropicConfig config;

  @override
  String get specificationVersion => filesSpecVersion;

  @override
  String get provider =>
      anthropicResourceProviderName(config.providerName, 'files');

  Uri get _requestUrl => Uri.parse('${config.baseUrl}/files');

  @override
  Future<FilesUploadResult> uploadFile(FilesUploadOptions options) async {
    final bytes = fileDataToBytes(options.data, argument: 'data');
    final MediaType contentType;
    try {
      contentType = MediaType.parse(options.mediaType);
    } on FormatException catch (error) {
      throw InvalidArgumentError(
        argument: 'mediaType',
        message: 'mediaType must be a valid IANA media type.',
        cause: error,
      );
    }

    final response = await postMultipartToApi<_AnthropicFilesResponse>(
      url: _requestUrl,
      headers: anthropicResourceHeaders(
        config.headers(),
        const <String>['files-api-2025-04-14'],
      ),
      build: (request) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: options.filename ?? 'blob',
            contentType: contentType,
          ),
        );
      },
      successHandler: jsonResponseHandler<_AnthropicFilesResponse>(
        validator: _anthropicFilesResponseValidator,
        decode: _decodeAnthropicFilesResponse,
      ),
      failureHandler: anthropicFailedResponseHandler(),
      client: config.client,
    );

    return FilesUploadResult(
      providerReference: <String, String>{'anthropic': response.id},
      mediaType: response.mimeType,
      filename: response.filename,
      providerMetadata: <String, JsonObject>{
        'anthropic': <String, Object?>{
          'filename': response.filename,
          'mimeType': response.mimeType,
          'sizeBytes': response.sizeBytes,
          'createdAt': response.createdAt,
          if (response.downloadable != null)
            'downloadable': response.downloadable,
          if (response.scope != null) 'scope': response.scope,
        },
      },
      warnings: const <Warning>[],
    );
  }
}

final class _AnthropicFilesResponse {
  const _AnthropicFilesResponse({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    this.downloadable,
    this.scope,
  });

  final String id;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String createdAt;
  final bool? downloadable;
  final JsonObject? scope;
}

_AnthropicFilesResponse _decodeAnthropicFilesResponse(JsonValue json) {
  final root = json as JsonObject;
  final scope = root['scope'] as JsonObject?;
  return _AnthropicFilesResponse(
    id: root['id'] as String,
    filename: root['filename'] as String,
    mimeType: root['mime_type'] as String,
    sizeBytes: (root['size_bytes'] as num).toInt(),
    createdAt: root['created_at'] as String,
    downloadable: root['downloadable'] as bool?,
    scope: scope == null
        ? null
        : <String, Object?>{
            'type': scope['type'] as String,
            'id': scope['id'] as String,
          },
  );
}
