import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'contracts.dart';
import 'token.dart';

final class McpProtectedResourceMetadata {
  McpProtectedResourceMetadata.fromJson(JsonObject json)
      : resource = canonicalMcpResource(
          Uri.parse(json['resource']! as String),
        ),
        authorizationServers = List<Uri>.unmodifiable(
          (json['authorization_servers']! as List<Object?>)
              .cast<String>()
              .map(Uri.parse),
        ),
        scopesSupported = Set<String>.unmodifiable(
          ((json['scopes_supported'] as List<Object?>?) ?? const <Object?>[])
              .cast<String>(),
        ) {
    if (authorizationServers.isEmpty ||
        authorizationServers.any(
          (issuer) => !_isSecureOAuthEndpoint(issuer),
        )) {
      throw const FormatException(
        'Protected resource metadata has no valid secure authorization server.',
      );
    }
  }

  final Uri resource;
  final List<Uri> authorizationServers;
  final Set<String> scopesSupported;
}

final class McpAuthorizationServerMetadata {
  McpAuthorizationServerMetadata.fromJson(JsonObject json)
      : issuer = Uri.parse(json['issuer']! as String),
        authorizationEndpoint = Uri.parse(
          json['authorization_endpoint']! as String,
        ),
        tokenEndpoint = Uri.parse(json['token_endpoint']! as String),
        registrationEndpoint = json['registration_endpoint'] is String
            ? Uri.parse(json['registration_endpoint']! as String)
            : null,
        codeChallengeMethods = Set<String>.unmodifiable(
          ((json['code_challenge_methods_supported'] as List<Object?>?) ??
                  const <Object?>[])
              .cast<String>(),
        ),
        tokenEndpointAuthMethods = Set<String>.unmodifiable(
          ((json['token_endpoint_auth_methods_supported'] as List<Object?>?) ??
                  const <Object?>['none'])
              .cast<String>(),
        ),
        clientIdMetadataDocumentSupported =
            json['client_id_metadata_document_supported'] == true {
    for (final endpoint in <Uri>[
      issuer,
      authorizationEndpoint,
      tokenEndpoint,
      if (registrationEndpoint != null) registrationEndpoint!,
    ]) {
      if (!_isSecureOAuthEndpoint(endpoint)) {
        throw const FormatException(
          'OAuth authorization server endpoints must use HTTPS or loopback '
          'HTTP.',
        );
      }
    }
  }

  final Uri issuer;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri? registrationEndpoint;
  final Set<String> codeChallengeMethods;
  final Set<String> tokenEndpointAuthMethods;
  final bool clientIdMetadataDocumentSupported;
}

final class McpBearerChallenge {
  const McpBearerChallenge({
    this.resourceMetadata,
    required this.scopes,
    this.error,
  });

  final Uri? resourceMetadata;
  final Set<String> scopes;
  final String? error;
}

McpBearerChallenge? parseMcpBearerChallenge(String? header) {
  if (header == null || !header.trimLeft().toLowerCase().startsWith('bearer')) {
    return null;
  }
  final values = <String, String>{};
  final expression = RegExp(r'([A-Za-z_][A-Za-z0-9_-]*)="([^"]*)"');
  for (final match in expression.allMatches(header)) {
    values[match.group(1)!.toLowerCase()] = match.group(2)!;
  }
  return McpBearerChallenge(
    resourceMetadata: values['resource_metadata'] == null
        ? null
        : Uri.parse(values['resource_metadata']!),
    scopes: Set<String>.unmodifiable(
      (values['scope'] ?? '')
          .split(RegExp(r'\s+'))
          .where((value) => value.isNotEmpty),
    ),
    error: values['error'],
  );
}

final class McpAuthorizationMetadataDiscovery {
  McpAuthorizationMetadataDiscovery({
    required this.httpClient,
    this.maxBodyBytes = 1024 * 1024,
  });

  final McpAuthorizationHttpClient httpClient;
  final int maxBodyBytes;

  Future<McpProtectedResourceMetadata> discoverResource(
    Uri resource, {
    String? wwwAuthenticate,
  }) async {
    final canonical = canonicalMcpResource(resource);
    final challenge = parseMcpBearerChallenge(wwwAuthenticate);
    final candidates = <Uri>[
      if (challenge?.resourceMetadata != null) challenge!.resourceMetadata!,
      ..._resourceMetadataCandidates(canonical),
    ];
    final json = await _firstMetadata(candidates);
    final metadata = McpProtectedResourceMetadata.fromJson(json);
    final origin = canonical.replace(path: '');
    if (metadata.resource != canonical && metadata.resource != origin) {
      throw const FormatException(
        'Protected resource metadata resource does not match the target.',
      );
    }
    return metadata;
  }

  Future<McpAuthorizationServerMetadata> discoverAuthorizationServer(
    Uri issuer,
  ) async {
    final json = await _firstMetadata(_authorizationMetadataCandidates(issuer));
    final metadata = McpAuthorizationServerMetadata.fromJson(json);
    if (metadata.issuer != issuer) {
      throw const FormatException(
        'Authorization server metadata issuer mismatch.',
      );
    }
    return metadata;
  }

  Future<JsonObject> _firstMetadata(Iterable<Uri> candidates) async {
    Object? lastError;
    for (final uri in candidates.toSet()) {
      try {
        final response = await httpClient.send(
          McpAuthorizationHttpRequest(
            method: 'GET',
            uri: uri,
            headers: const <String, String>{
              'accept': 'application/json',
            },
          ),
        );
        if (response.statusCode == 404) {
          continue;
        }
        if (response.statusCode != 200) {
          lastError = StateError(
            'OAuth metadata endpoint returned ${response.statusCode}.',
          );
          continue;
        }
        if (response.body.length > maxBodyBytes) {
          throw const FormatException('OAuth metadata body is too large.');
        }
        final decoded = jsonDecode(
          utf8.decode(response.body, allowMalformed: false),
        );
        return freezeJsonValue(decoded)! as JsonObject;
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw StateError(
      'OAuth metadata discovery failed: ${lastError.runtimeType}.',
    );
  }
}

List<Uri> _resourceMetadataCandidates(Uri resource) {
  final origin = resource.replace(path: '', query: null, fragment: null);
  final suffix = resource.path == '/' ? '' : resource.path;
  return <Uri>[
    origin.replace(path: '/.well-known/oauth-protected-resource$suffix'),
    origin.replace(path: '/.well-known/oauth-protected-resource'),
  ];
}

List<Uri> _authorizationMetadataCandidates(Uri issuer) {
  if (!_isSecureOAuthEndpoint(issuer)) {
    throw ArgumentError.value(
      issuer,
      'issuer',
      'Authorization issuer must use HTTPS or loopback HTTP.',
    );
  }
  final origin = issuer.replace(path: '', query: null, fragment: null);
  final suffix = issuer.path == '/' ? '' : issuer.path;
  return <Uri>[
    origin.replace(path: '/.well-known/oauth-authorization-server$suffix'),
    origin.replace(path: '/.well-known/openid-configuration$suffix'),
    issuer.replace(
      path: '${issuer.path.replaceFirst(RegExp(r'/$'), '')}/'
          '.well-known/openid-configuration',
    ),
  ];
}

bool _isSecureOAuthEndpoint(Uri uri) {
  if (uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.hasQuery) {
    return false;
  }
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}
