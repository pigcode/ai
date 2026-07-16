import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;

import '../internal/config.dart';
import '../internal/error.dart';
import '../internal/provider_options.dart';

/// OpenAI Skills(`/skills`)的 [Skills] 实现。
final class OpenAiSkills implements Skills {
  OpenAiSkills({required this.config});

  /// 共享的 provider 配置(baseUrl/headers/client)。
  final OpenAiConfig config;

  @override
  String get specificationVersion => skillsSpecVersion;

  @override
  String get provider => '${config.providerName}.skills';

  Uri get _requestUrl => Uri.parse('${config.baseUrl}/skills');

  @override
  Future<SkillsUploadResult> uploadSkill(SkillsUploadOptions options) async {
    final warnings = <Warning>[
      if (options.displayTitle != null)
        const UnsupportedWarning('displayTitle'),
    ];

    final response = await postMultipartToApi<_OpenAiSkillsResponse>(
      url: _requestUrl,
      headers: combineHeaders([config.headers()]),
      build: (request) {
        for (final file in options.files) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'files[]',
              fileDataToBytes(file.data, argument: 'files'),
              filename: _openAiSkillBundlePath(file.path),
            ),
          );
        }
      },
      successHandler: jsonResponseHandler<_OpenAiSkillsResponse>(
        decode: _decodeOpenAiSkillsResponse,
      ),
      failureHandler: openAiFailedResponseHandler(),
      client: config.client,
    );

    final metadataKey = resolveOpenAiProviderOptionsName(config.providerName);
    return SkillsUploadResult(
      providerReference: {metadataKey: response.id},
      name: response.name,
      description: response.description,
      latestVersion: response.latestVersion,
      providerMetadata: {
        metadataKey: {
          if (response.defaultVersion != null)
            'defaultVersion': response.defaultVersion,
          if (response.createdAt != null) 'createdAt': response.createdAt,
          if (response.updatedAt != null) 'updatedAt': response.updatedAt,
        },
      },
      warnings: warnings,
    );
  }
}

String _openAiSkillBundlePath(String path) => 'skill/$path';

final class _OpenAiSkillsResponse {
  const _OpenAiSkillsResponse({
    required this.id,
    this.name,
    this.description,
    this.latestVersion,
    this.defaultVersion,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? name;
  final String? description;
  final String? latestVersion;
  final String? defaultVersion;
  final int? createdAt;
  final int? updatedAt;
}

_OpenAiSkillsResponse _decodeOpenAiSkillsResponse(JsonValue json) {
  if (json case final JsonObject root) {
    final id = root['id'];
    if (id is! String) {
      throw InvalidResponseDataError(data: json);
    }
    return _OpenAiSkillsResponse(
      id: id,
      name: _optionalString(root, 'name'),
      description: _optionalString(root, 'description'),
      latestVersion: _optionalString(root, 'latest_version'),
      defaultVersion: _optionalString(root, 'default_version'),
      createdAt: _optionalInt(root, 'created_at'),
      updatedAt: _optionalInt(root, 'updated_at'),
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
