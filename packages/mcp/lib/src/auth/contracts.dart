import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'token.dart';

final class McpAuthorizationHttpRequest {
  McpAuthorizationHttpRequest({
    required this.method,
    required this.uri,
    Map<String, String> headers = const <String, String>{},
    List<int> body = const <int>[],
  })  : headers = Map<String, String>.unmodifiable(headers),
        body = List<int>.unmodifiable(body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;
}

final class McpAuthorizationHttpResponse {
  McpAuthorizationHttpResponse({
    required this.statusCode,
    Map<String, String> headers = const <String, String>{},
    List<int> body = const <int>[],
  })  : headers = Map<String, String>.unmodifiable(
          headers.map(
            (name, value) => MapEntry(name.toLowerCase(), value),
          ),
        ),
        body = List<int>.unmodifiable(body);

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;

  String? header(String name) => headers[name.toLowerCase()];
}

abstract interface class McpAuthorizationHttpClient {
  Future<McpAuthorizationHttpResponse> send(
    McpAuthorizationHttpRequest request,
  );
}

abstract interface class McpAuthorizationStore {
  Future<McpAccessToken?> load(Uri resource);
  Future<void> save(McpAccessToken token);
  Future<void> remove(Uri resource);
}

abstract interface class McpBrowserLauncher {
  Future<void> open(Uri authorizationUri);
}

abstract interface class McpRedirectReceiver {
  Future<Uri> receive(Uri redirectUri);
}

abstract interface class McpAuthorizationClock {
  DateTime now();
}

final class McpSystemAuthorizationClock implements McpAuthorizationClock {
  const McpSystemAuthorizationClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

abstract interface class McpSecureRandom {
  List<int> bytes(int length);
}

final class McpClientRegistration {
  McpClientRegistration({
    required this.clientId,
    this.clientSecret,
    required this.tokenEndpointAuthMethod,
    required Iterable<Uri> redirectUris,
  }) : redirectUris = List<Uri>.unmodifiable(redirectUris);

  final String clientId;
  final String? clientSecret;
  final String tokenEndpointAuthMethod;
  final List<Uri> redirectUris;

  JsonObject safeMetadata() => freezeJsonObject(
        <String, Object?>{
          'clientId': clientId,
          'tokenEndpointAuthMethod': tokenEndpointAuthMethod,
          'redirectUris':
              redirectUris.map((uri) => uri.toString()).toList(growable: false),
          'hasClientSecret': clientSecret != null,
        },
      );

  @override
  String toString() => 'McpClientRegistration(clientId: $clientId, '
      'authMethod: $tokenEndpointAuthMethod, '
      'hasSecret: ${clientSecret != null})';
}

abstract interface class McpClientRegistrationProvider {
  Future<McpClientRegistration?> preRegistered(Uri issuer);
  Uri? get clientMetadataDocument;
  JsonObject dynamicRegistrationMetadata(Uri redirectUri);
}
