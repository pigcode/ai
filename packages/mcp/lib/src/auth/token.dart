import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// Audience-bound OAuth token. Secret values are never included in
/// [toString] or [safeMetadata].
final class McpAccessToken {
  McpAccessToken({
    required String accessToken,
    required this.resource,
    required Iterable<String> scopes,
    required this.issuedAt,
    this.expiresAt,
    String? refreshToken,
    this.tokenType = 'Bearer',
  })  : _accessToken = _validateSecret(accessToken, 'accessToken'),
        _refreshToken = refreshToken == null
            ? null
            : _validateSecret(refreshToken, 'refreshToken'),
        scopes = Set<String>.unmodifiable(scopes) {
    if (tokenType.toLowerCase() != 'bearer') {
      throw ArgumentError.value(
        tokenType,
        'tokenType',
        'Only Bearer access tokens are supported.',
      );
    }
  }

  final String _accessToken;
  final String? _refreshToken;
  final Uri resource;
  final Set<String> scopes;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final String tokenType;

  bool isExpired(DateTime now) =>
      expiresAt != null && !now.isBefore(expiresAt!);

  String authorizationHeaderFor(Uri target) {
    _requireTarget(target);
    return 'Bearer $_accessToken';
  }

  String? refreshTokenFor(Uri target) {
    _requireTarget(target);
    return _refreshToken;
  }

  JsonObject safeMetadata() => freezeJsonObject(
        <String, Object?>{
          'resource': resource.toString(),
          'scopes': scopes.toList()..sort(),
          'issuedAt': issuedAt.toUtc().toIso8601String(),
          if (expiresAt != null)
            'expiresAt': expiresAt!.toUtc().toIso8601String(),
          'tokenType': tokenType,
          'hasRefreshToken': _refreshToken != null,
        },
      );

  void _requireTarget(Uri target) {
    if (canonicalMcpResource(target) != canonicalMcpResource(resource)) {
      throw StateError(
        'OAuth token is bound to a different MCP resource.',
      );
    }
  }

  @override
  String toString() =>
      'McpAccessToken(resource: $resource, scopes: ${scopes.length}, '
      'expiresAt: $expiresAt, hasRefreshToken: ${_refreshToken != null})';
}

Uri canonicalMcpResource(Uri resource) {
  if ((resource.scheme != 'https' && resource.scheme != 'http') ||
      resource.host.isEmpty ||
      resource.userInfo.isNotEmpty ||
      resource.hasFragment ||
      resource.hasQuery) {
    throw ArgumentError.value(
      resource,
      'resource',
      'MCP OAuth resource must be an absolute HTTP(S) URI without '
          'credentials, query, or fragment.',
    );
  }
  final path = resource.path == '/' ? '' : resource.path;
  return resource.replace(
    scheme: resource.scheme.toLowerCase(),
    host: resource.host.toLowerCase(),
    path: path,
    query: null,
    fragment: null,
  );
}

String _validateSecret(String value, String name) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
  return value;
}
