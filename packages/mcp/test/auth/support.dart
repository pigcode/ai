import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

typedef AuthorizationResponder = FutureOr<McpAuthorizationHttpResponse>
    Function(McpAuthorizationHttpRequest request);

final class RecordingAuthorizationHttpClient
    implements McpAuthorizationHttpClient {
  RecordingAuthorizationHttpClient(this.responder);

  final AuthorizationResponder responder;
  final List<McpAuthorizationHttpRequest> requests =
      <McpAuthorizationHttpRequest>[];

  @override
  Future<McpAuthorizationHttpResponse> send(
    McpAuthorizationHttpRequest request,
  ) async {
    requests.add(request);
    return responder(request);
  }
}

McpAuthorizationHttpResponse authJson(
  Object? value, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{},
}) =>
    McpAuthorizationHttpResponse(
      statusCode: statusCode,
      headers: <String, String>{
        'content-type': 'application/json',
        ...headers,
      },
      body: utf8.encode(jsonEncode(value)),
    );

final class MemoryAuthorizationStore implements McpAuthorizationStore {
  final Map<Uri, McpAccessToken> tokens = <Uri, McpAccessToken>{};

  @override
  Future<McpAccessToken?> load(Uri resource) async =>
      tokens[canonicalMcpResource(resource)];

  @override
  Future<void> remove(Uri resource) async {
    tokens.remove(canonicalMcpResource(resource));
  }

  @override
  Future<void> save(McpAccessToken token) async {
    tokens[canonicalMcpResource(token.resource)] = token;
  }
}

final class FixedRandom implements McpSecureRandom {
  var counter = 0;

  @override
  List<int> bytes(int length) => List<int>.generate(
        length,
        (index) => (counter++ + index) & 0xff,
      );
}

final class FixedClock implements McpAuthorizationClock {
  FixedClock([DateTime? value]) : value = value ?? DateTime.utc(2026, 7, 23);

  DateTime value;

  @override
  DateTime now() => value;
}

final class BrowserRedirect implements McpBrowserLauncher, McpRedirectReceiver {
  Uri? opened;
  String? overrideState;
  String? error;

  @override
  Future<void> open(Uri authorizationUri) async {
    opened = authorizationUri;
  }

  @override
  Future<Uri> receive(Uri redirectUri) async {
    final authorization = opened!;
    return redirectUri.replace(
      queryParameters: <String, String>{
        if (error == null) 'code': 'authorization-code',
        if (error != null) 'error': error!,
        'state': overrideState ?? authorization.queryParameters['state']!,
      },
    );
  }
}

final class FixedRegistrationProvider implements McpClientRegistrationProvider {
  FixedRegistrationProvider({
    this.registration,
    this.clientMetadataDocument,
  });

  final McpClientRegistration? registration;

  @override
  final Uri? clientMetadataDocument;

  @override
  JsonObject dynamicRegistrationMetadata(Uri redirectUri) => freezeJsonObject(
        const <String, Object?>{
          'client_name': 'Pigcode test client',
          'token_endpoint_auth_method': 'none',
        },
      );

  @override
  Future<McpClientRegistration?> preRegistered(Uri issuer) async =>
      registration;
}

McpClientRegistration registration({
  String authMethod = 'none',
  String? secret,
  Uri? redirectUri,
}) =>
    McpClientRegistration(
      clientId: 'pigcode-client',
      clientSecret: secret,
      tokenEndpointAuthMethod: authMethod,
      redirectUris: <Uri>[redirectUri ?? redirect],
    );

const resource = 'https://mcp.example.test/mcp';
const issuer = 'https://auth.example.test/tenant';
final redirect = Uri(
  scheme: 'http',
  host: '127.0.0.1',
  port: 4567,
  path: '/callback',
);

Map<String, Object?> protectedMetadata({
  List<String>? scopes = const <String>['tools:read'],
}) =>
    <String, Object?>{
      'resource': resource,
      'authorization_servers': <Object?>[issuer],
      if (scopes != null) 'scopes_supported': scopes,
    };

Map<String, Object?> serverMetadata({
  String authMethod = 'none',
  bool pkce = true,
  bool cimd = false,
  bool dcr = false,
}) =>
    <String, Object?>{
      'issuer': issuer,
      'authorization_endpoint': '$issuer/authorize',
      'token_endpoint': '$issuer/token',
      if (dcr) 'registration_endpoint': '$issuer/register',
      if (pkce) 'code_challenge_methods_supported': <Object?>['S256'],
      'token_endpoint_auth_methods_supported': <Object?>[authMethod],
      if (cimd) 'client_id_metadata_document_supported': true,
    };

Map<String, String> decodeForm(List<int> body) =>
    Uri.splitQueryString(utf8.decode(body));
