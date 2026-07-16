import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;

import '../internal/config.dart';
import '../internal/error.dart';
import '../internal/resource_utils.dart';

final JsonSchemaValidator _anthropicSkillsResponseValidator =
    JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'id': <String, Object?>{'type': 'string'},
      'type': <String, Object?>{'type': 'string'},
      'display_title': <String, Object?>{
        'type': <Object?>['string', 'null'],
      },
      'latest_version': <String, Object?>{
        'type': <Object?>['string', 'null'],
      },
      'source': <String, Object?>{'type': 'string'},
      'created_at': <String, Object?>{'type': 'string'},
      'updated_at': <String, Object?>{'type': 'string'},
      'name': <String, Object?>{
        'type': <Object?>['string', 'null'],
      },
      'description': <String, Object?>{
        'type': <Object?>['string', 'null'],
      },
    },
    'required': <Object?>['id', 'source', 'created_at', 'updated_at'],
  }),
);

final JsonSchemaValidator _anthropicSkillVersionResponseValidator =
    JsonSchemaValidator.fromContract(
  const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'type': <String, Object?>{'type': 'string'},
      'skill_id': <String, Object?>{'type': 'string'},
      'name': <String, Object?>{
        'type': <Object?>['string', 'null'],
      },
      'description': <String, Object?>{
        'type': <Object?>['string', 'null'],
      },
    },
    'required': <Object?>['type', 'skill_id'],
  }),
);

Future<T> _getJsonFromApi<T>({
  required Uri url,
  required Map<String, String> headers,
  required ResponseHandler<T> successHandler,
  required FailedResponseHandler failureHandler,
  http.Client? client,
}) async {
  final ownedClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    final request = http.Request('GET', url)..headers.addAll(headers);
    final http.StreamedResponse response;
    try {
      response = await httpClient.send(request);
    } on http.ClientException catch (error) {
      throw mapTransportError(error, url: url);
    } on TimeoutException catch (error) {
      throw mapTransportError(error, url: url);
    }
    final context = ResponseContext(url: url, response: response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        return await successHandler(context);
      } on http.ClientException catch (error) {
        throw mapTransportError(error, url: url);
      } on TimeoutException catch (error) {
        throw mapTransportError(error, url: url);
      }
    }
    throw await failureHandler(context);
  } finally {
    if (ownedClient) {
      httpClient.close();
    }
  }
}

/// Anthropic Skills(`/skills`)的 [Skills] 实现。
final class AnthropicSkills implements Skills {
  AnthropicSkills({required this.config});

  /// 共享的 provider 配置(baseUrl/headers/client)。
  final AnthropicConfig config;

  @override
  String get specificationVersion => skillsSpecVersion;

  @override
  String get provider =>
      anthropicResourceProviderName(config.providerName, 'skills');

  Uri get _requestUrl => Uri.parse('${config.baseUrl}/skills');

  @override
  Future<SkillsUploadResult> uploadSkill(SkillsUploadOptions options) async {
    final headers = anthropicResourceHeaders(
      config.headers(),
      const <String>['skills-2025-10-02'],
    );

    final response = await postMultipartToApi<_AnthropicSkillsResponse>(
      url: _requestUrl,
      headers: headers,
      build: (request) {
        final displayTitle = options.displayTitle;
        if (displayTitle != null) {
          request.fields['display_title'] = displayTitle;
        }
        for (final file in options.files) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'files[]',
              fileDataToBytes(file.data, argument: 'files'),
              filename: file.path,
            ),
          );
        }
      },
      successHandler: jsonResponseHandler<_AnthropicSkillsResponse>(
        validator: _anthropicSkillsResponseValidator,
        decode: _decodeAnthropicSkillsResponse,
      ),
      failureHandler: anthropicFailedResponseHandler(),
      client: config.client,
    );

    var name = response.name;
    var description = response.description;
    final latestVersion = response.latestVersion;
    final warnings = <Warning>[];
    if (latestVersion != null) {
      try {
        final version = await _getJsonFromApi<_AnthropicSkillVersionResponse>(
          url: Uri.parse(
            '${config.baseUrl}/skills/${response.id}/versions/$latestVersion',
          ),
          headers: anthropicResourceHeaders(
            config.headers(),
            const <String>['skills-2025-10-02'],
          ),
          successHandler: jsonResponseHandler<_AnthropicSkillVersionResponse>(
            validator: _anthropicSkillVersionResponseValidator,
            decode: _decodeAnthropicSkillVersionResponse,
          ),
          failureHandler: anthropicFailedResponseHandler(),
          client: config.client,
        );
        name = version.name ?? name;
        description = version.description ?? description;
      } on AiError {
        warnings.add(
          const OtherWarning(
            'Anthropic skill was created, but its latest version metadata could not be retrieved.',
          ),
        );
      }
    }

    return SkillsUploadResult(
      providerReference: <String, String>{'anthropic': response.id},
      displayTitle: response.displayTitle,
      name: name,
      description: description,
      latestVersion: latestVersion,
      providerMetadata: <String, JsonObject>{
        'anthropic': <String, Object?>{
          'source': response.source,
          'createdAt': response.createdAt,
          'updatedAt': response.updatedAt,
        },
      },
      warnings: warnings,
    );
  }
}

final class _AnthropicSkillVersionResponse {
  const _AnthropicSkillVersionResponse({
    this.name,
    this.description,
  });

  final String? name;
  final String? description;
}

_AnthropicSkillVersionResponse _decodeAnthropicSkillVersionResponse(
  JsonValue json,
) {
  final root = json as JsonObject;
  return _AnthropicSkillVersionResponse(
    name: root['name'] as String?,
    description: root['description'] as String?,
  );
}

final class _AnthropicSkillsResponse {
  const _AnthropicSkillsResponse({
    required this.id,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.displayTitle,
    this.latestVersion,
    this.name,
    this.description,
  });

  final String id;
  final String source;
  final String createdAt;
  final String updatedAt;
  final String? displayTitle;
  final String? latestVersion;
  final String? name;
  final String? description;
}

_AnthropicSkillsResponse _decodeAnthropicSkillsResponse(JsonValue json) {
  final root = json as JsonObject;
  return _AnthropicSkillsResponse(
    id: root['id'] as String,
    source: root['source'] as String,
    createdAt: root['created_at'] as String,
    updatedAt: root['updated_at'] as String,
    displayTitle: root['display_title'] as String?,
    latestVersion: root['latest_version'] as String?,
    name: root['name'] as String?,
    description: root['description'] as String?,
  );
}
