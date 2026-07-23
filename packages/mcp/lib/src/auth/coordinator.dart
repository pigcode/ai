import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../http/contracts.dart';
import 'contracts.dart';
import 'metadata.dart';
import 'pkce.dart';
import 'token.dart';

final class McpAuthorizationException extends ProtocolException {
  const McpAuthorizationException(super.code, super.message);

  @override
  String toString() => 'McpAuthorizationException($code): $message';
}

/// Portable MCP OAuth coordinator with caller-owned ports and storage.
final class McpAuthorizationCoordinator
    implements McpHttpAuthorizationProvider {
  McpAuthorizationCoordinator({
    required Uri resource,
    required this.httpClient,
    required this.store,
    required this.browser,
    required this.redirectReceiver,
    required this.registrationProvider,
    required this.random,
    this.clock = const McpSystemAuthorizationClock(),
    this.maxScopeRetries = 2,
    int maxMetadataBodyBytes = 1024 * 1024,
    this.maxResponseBodyBytes = 1024 * 1024,
  })  : resource = canonicalMcpResource(resource),
        discovery = McpAuthorizationMetadataDiscovery(
          httpClient: httpClient,
          maxBodyBytes: maxMetadataBodyBytes,
        ) {
    if (maxScopeRetries < 0 || maxScopeRetries > 8) {
      throw ArgumentError.value(
        maxScopeRetries,
        'maxScopeRetries',
        'Must be between 0 and 8.',
      );
    }
    if (maxResponseBodyBytes <= 0) {
      throw ArgumentError.value(
        maxResponseBodyBytes,
        'maxResponseBodyBytes',
        'Must be positive.',
      );
    }
  }

  final Uri resource;
  final McpAuthorizationHttpClient httpClient;
  final McpAuthorizationStore store;
  final McpBrowserLauncher browser;
  final McpRedirectReceiver redirectReceiver;
  final McpClientRegistrationProvider registrationProvider;
  final McpSecureRandom random;
  final McpAuthorizationClock clock;
  final int maxScopeRetries;
  final int maxResponseBodyBytes;
  final McpAuthorizationMetadataDiscovery discovery;
  var _scopeAttempts = 0;

  Future<McpAccessToken> authorize({
    required Uri redirectUri,
    String? wwwAuthenticate,
  }) async {
    _validateRedirectUri(redirectUri);
    final protected = await discovery.discoverResource(
      resource,
      wwwAuthenticate: wwwAuthenticate,
    );
    final server = await discovery.discoverAuthorizationServer(
      protected.authorizationServers.first,
    );
    if (!server.codeChallengeMethods.contains('S256')) {
      throw const McpAuthorizationException(
        'mcp_oauth_pkce_unsupported',
        'Authorization server does not advertise PKCE S256.',
      );
    }
    final registration = await _resolveRegistration(server, redirectUri);
    _requireRedirect(registration, redirectUri);
    final challenge = parseMcpBearerChallenge(wwwAuthenticate);
    final scopes = challenge?.scopes.isNotEmpty ?? false
        ? challenge!.scopes
        : protected.scopesSupported;
    final pkce = createMcpPkce(random);
    final state = createMcpOAuthState(random);
    final authorizationUri = server.authorizationEndpoint.replace(
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': registration.clientId,
        'redirect_uri': redirectUri.toString(),
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'resource': resource.toString(),
        if (scopes.isNotEmpty) 'scope': (scopes.toList()..sort()).join(' '),
      },
    );
    await browser.open(authorizationUri);
    final redirected = await redirectReceiver.receive(redirectUri);
    if (!_sameRedirect(redirectUri, redirected)) {
      throw const McpAuthorizationException(
        'mcp_oauth_redirect_mismatch',
        'OAuth redirect URI did not match the registered redirect.',
      );
    }
    final parameters = redirected.queryParameters;
    if (parameters['state'] != state) {
      throw const McpAuthorizationException(
        'mcp_oauth_state_mismatch',
        'OAuth redirect state did not match.',
      );
    }
    if (parameters['error'] != null) {
      throw const McpAuthorizationException(
        'mcp_oauth_authorization_error',
        'Authorization server returned an authorization error.',
      );
    }
    final code = parameters['code'];
    if (code == null || code.isEmpty) {
      throw const McpAuthorizationException(
        'mcp_oauth_missing_code',
        'OAuth redirect did not contain an authorization code.',
      );
    }
    final token = await _requestToken(
      server,
      registration,
      <String, String>{
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri.toString(),
        'code_verifier': pkce.verifier,
        'resource': resource.toString(),
      },
      fallbackScopes: scopes,
    );
    await store.save(token);
    return token;
  }

  Future<McpAccessToken> clientCredentials({
    required Uri registrationRedirectUri,
    String? wwwAuthenticate,
  }) async {
    final protected = await discovery.discoverResource(
      resource,
      wwwAuthenticate: wwwAuthenticate,
    );
    final server = await discovery.discoverAuthorizationServer(
      protected.authorizationServers.first,
    );
    final registration =
        await _resolveRegistration(server, registrationRedirectUri);
    final challenge = parseMcpBearerChallenge(wwwAuthenticate);
    final scopes = challenge?.scopes.isNotEmpty ?? false
        ? challenge!.scopes
        : protected.scopesSupported;
    final token = await _requestToken(
      server,
      registration,
      <String, String>{
        'grant_type': 'client_credentials',
        'resource': resource.toString(),
        if (scopes.isNotEmpty) 'scope': (scopes.toList()..sort()).join(' '),
      },
      fallbackScopes: scopes,
    );
    await store.save(token);
    return token;
  }

  Future<McpAccessToken> refresh({
    required Uri registrationRedirectUri,
  }) async {
    final current = await store.load(resource);
    final refreshToken = current?.refreshTokenFor(resource);
    if (refreshToken == null) {
      throw const McpAuthorizationException(
        'mcp_oauth_refresh_unavailable',
        'No audience-bound refresh token is available.',
      );
    }
    final protected = await discovery.discoverResource(resource);
    final server = await discovery.discoverAuthorizationServer(
      protected.authorizationServers.first,
    );
    final registration =
        await _resolveRegistration(server, registrationRedirectUri);
    final token = await _requestToken(
      server,
      registration,
      <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'resource': resource.toString(),
      },
      fallbackScopes: current!.scopes,
      fallbackRefreshToken: refreshToken,
    );
    await store.save(token);
    return token;
  }

  Future<McpAccessToken> authorizeAfterChallenge({
    required Uri redirectUri,
    required String wwwAuthenticate,
  }) {
    final challenge = parseMcpBearerChallenge(wwwAuthenticate);
    if (challenge == null ||
        (challenge.error != 'insufficient_scope' && challenge.scopes.isEmpty)) {
      throw const McpAuthorizationException(
        'mcp_oauth_invalid_scope_challenge',
        'Response does not contain an OAuth scope challenge.',
      );
    }
    if (_scopeAttempts >= maxScopeRetries) {
      throw const McpAuthorizationException(
        'mcp_oauth_scope_retry_limit',
        'OAuth scope step-up retry limit reached.',
      );
    }
    _scopeAttempts++;
    return authorize(
      redirectUri: redirectUri,
      wwwAuthenticate: wwwAuthenticate,
    );
  }

  void resetScopeAttempts() {
    _scopeAttempts = 0;
  }

  @override
  Future<Map<String, String>> headersFor(Uri target) async {
    if (canonicalMcpResource(target) != resource) {
      throw const McpAuthorizationException(
        'mcp_oauth_token_target_mismatch',
        'Refused to send an OAuth token to a different resource.',
      );
    }
    final token = await store.load(resource);
    if (token == null || token.isExpired(clock.now())) {
      return const <String, String>{};
    }
    return <String, String>{
      'authorization': token.authorizationHeaderFor(resource),
    };
  }

  Future<McpClientRegistration> _resolveRegistration(
    McpAuthorizationServerMetadata server,
    Uri redirectUri,
  ) async {
    final preRegistered =
        await registrationProvider.preRegistered(server.issuer);
    if (preRegistered != null) {
      return preRegistered;
    }
    final metadataDocument = registrationProvider.clientMetadataDocument;
    if (server.clientIdMetadataDocumentSupported && metadataDocument != null) {
      if (metadataDocument.scheme != 'https' ||
          metadataDocument.host.isEmpty ||
          metadataDocument.path.isEmpty ||
          metadataDocument.path == '/') {
        throw const McpAuthorizationException(
          'mcp_oauth_invalid_cimd',
          'Client ID metadata document must be a path-bearing HTTPS URL.',
        );
      }
      return McpClientRegistration(
        clientId: metadataDocument.toString(),
        tokenEndpointAuthMethod: 'none',
        redirectUris: <Uri>[redirectUri],
      );
    }
    final registrationEndpoint = server.registrationEndpoint;
    if (registrationEndpoint == null) {
      throw const McpAuthorizationException(
        'mcp_oauth_registration_unavailable',
        'No supported OAuth client registration mechanism is available.',
      );
    }
    final metadata = <String, Object?>{
      ...registrationProvider.dynamicRegistrationMetadata(redirectUri),
      'redirect_uris': <Object?>[redirectUri.toString()],
    };
    final response = await httpClient.send(
      McpAuthorizationHttpRequest(
        method: 'POST',
        uri: registrationEndpoint,
        headers: const <String, String>{
          'accept': 'application/json',
          'content-type': 'application/json',
        },
        body: utf8.encode(jsonEncode(metadata)),
      ),
    );
    final json =
        _decodeJsonResponse(response, expectedStatuses: const {200, 201});
    final clientId = json['client_id'];
    if (clientId is! String || clientId.isEmpty) {
      throw const McpAuthorizationException(
        'mcp_oauth_invalid_registration',
        'Dynamic registration response has no client_id.',
      );
    }
    return McpClientRegistration(
      clientId: clientId,
      clientSecret: json['client_secret'] is String
          ? json['client_secret']! as String
          : null,
      tokenEndpointAuthMethod: json['token_endpoint_auth_method'] is String
          ? json['token_endpoint_auth_method']! as String
          : 'none',
      redirectUris: <Uri>[redirectUri],
    );
  }

  Future<McpAccessToken> _requestToken(
    McpAuthorizationServerMetadata server,
    McpClientRegistration registration,
    Map<String, String> parameters, {
    required Set<String> fallbackScopes,
    String? fallbackRefreshToken,
  }) async {
    final method = registration.tokenEndpointAuthMethod;
    if (!server.tokenEndpointAuthMethods.contains(method)) {
      throw const McpAuthorizationException(
        'mcp_oauth_token_auth_unsupported',
        'Client token endpoint authentication method is not supported.',
      );
    }
    final form = <String, String>{...parameters};
    final headers = <String, String>{
      'accept': 'application/json',
      'content-type': 'application/x-www-form-urlencoded',
    };
    switch (method) {
      case 'client_secret_basic':
        final secret = registration.clientSecret;
        if (secret == null) {
          throw const McpAuthorizationException(
            'mcp_oauth_missing_client_secret',
            'client_secret_basic requires a client secret.',
          );
        }
        final credentials =
            '${Uri.encodeQueryComponent(registration.clientId)}:'
            '${Uri.encodeQueryComponent(secret)}';
        headers['authorization'] =
            'Basic ${base64.encode(utf8.encode(credentials))}';
      case 'client_secret_post':
        final secret = registration.clientSecret;
        if (secret == null) {
          throw const McpAuthorizationException(
            'mcp_oauth_missing_client_secret',
            'client_secret_post requires a client secret.',
          );
        }
        form['client_id'] = registration.clientId;
        form['client_secret'] = secret;
      case 'none':
        form['client_id'] = registration.clientId;
      default:
        throw const McpAuthorizationException(
          'mcp_oauth_token_auth_unsupported',
          'Unsupported token endpoint authentication method.',
        );
    }
    final response = await httpClient.send(
      McpAuthorizationHttpRequest(
        method: 'POST',
        uri: server.tokenEndpoint,
        headers: headers,
        body: utf8.encode(_encodeForm(form)),
      ),
    );
    final json = _decodeJsonResponse(response, expectedStatuses: const {200});
    final accessToken = json['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const McpAuthorizationException(
        'mcp_oauth_invalid_token_response',
        'OAuth token response has no access token.',
      );
    }
    final issuedAt = clock.now().toUtc();
    final expiresIn = json['expires_in'];
    final scope = json['scope'];
    return McpAccessToken(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] is String
          ? json['refresh_token']! as String
          : fallbackRefreshToken,
      resource: resource,
      scopes: scope is String
          ? scope.split(RegExp(r'\s+')).where((value) => value.isNotEmpty)
          : fallbackScopes,
      issuedAt: issuedAt,
      expiresAt: expiresIn is num
          ? issuedAt.add(Duration(seconds: expiresIn.toInt()))
          : null,
      tokenType: json['token_type'] is String
          ? json['token_type']! as String
          : 'Bearer',
    );
  }

  JsonObject _decodeJsonResponse(
    McpAuthorizationHttpResponse response, {
    required Set<int> expectedStatuses,
  }) {
    if (!expectedStatuses.contains(response.statusCode)) {
      throw McpAuthorizationException(
        'mcp_oauth_http_error',
        'OAuth endpoint returned status ${response.statusCode}.',
      );
    }
    if (response.body.length > maxResponseBodyBytes) {
      throw const McpAuthorizationException(
        'mcp_oauth_response_too_large',
        'OAuth endpoint response exceeded the configured byte limit.',
      );
    }
    try {
      return freezeJsonValue(
        jsonDecode(utf8.decode(response.body, allowMalformed: false)),
      )! as JsonObject;
    } on Object {
      throw const McpAuthorizationException(
        'mcp_oauth_invalid_json',
        'OAuth endpoint returned invalid JSON.',
      );
    }
  }
}

String _encodeForm(Map<String, String> values) => values.entries
    .map(
      (entry) => '${Uri.encodeQueryComponent(entry.key)}='
          '${Uri.encodeQueryComponent(entry.value)}',
    )
    .join('&');

void _validateRedirectUri(Uri uri) {
  final localhost = uri.scheme == 'http' &&
      (uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1');
  if ((!localhost && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.hasFragment) {
    throw ArgumentError.value(
      uri,
      'redirectUri',
      'Redirect must use HTTPS or loopback HTTP and have no fragment.',
    );
  }
}

void _requireRedirect(McpClientRegistration registration, Uri redirectUri) {
  if (!registration.redirectUris.contains(redirectUri)) {
    throw const McpAuthorizationException(
      'mcp_oauth_unregistered_redirect',
      'OAuth redirect URI is not registered for this client.',
    );
  }
}

bool _sameRedirect(Uri expected, Uri actual) =>
    expected.scheme == actual.scheme &&
    expected.host == actual.host &&
    expected.port == actual.port &&
    expected.path == actual.path;
