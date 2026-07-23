import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('WWW-Authenticate metadata URL and scope are authoritative', () async {
    final http = RecordingAuthorizationHttpClient(
      (request) {
        expect(
          request.uri,
          Uri.parse('https://metadata.example.test/protected'),
        );
        return authJson(protectedMetadata());
      },
    );
    final discovery = McpAuthorizationMetadataDiscovery(httpClient: http);
    final metadata = await discovery.discoverResource(
      Uri.parse(resource),
      wwwAuthenticate:
          'Bearer resource_metadata="https://metadata.example.test/protected", '
          'scope="files:read files:write"',
    );
    final challenge = parseMcpBearerChallenge(
      'Bearer resource_metadata="https://metadata.example.test/protected", '
      'scope="files:read files:write"',
    )!;

    expect(metadata.resource, Uri.parse(resource));
    expect(challenge.scopes, <String>{'files:read', 'files:write'});
    expect(http.requests, hasLength(1));
  });

  test('resource discovery falls back path-first then root', () async {
    final http = RecordingAuthorizationHttpClient(
      (request) {
        if (request.uri.path == '/.well-known/oauth-protected-resource/mcp') {
          return authJson(const <String, Object?>{}, statusCode: 404);
        }
        expect(
          request.uri.path,
          '/.well-known/oauth-protected-resource',
        );
        return authJson(<String, Object?>{
          ...protectedMetadata(),
          'resource': 'https://mcp.example.test',
        });
      },
    );
    final metadata = await McpAuthorizationMetadataDiscovery(
      httpClient: http,
    ).discoverResource(Uri.parse(resource));

    expect(metadata.authorizationServers.single, Uri.parse(issuer));
    expect(http.requests, hasLength(2));
  });

  test('resource discovery rejects unrelated same-origin paths', () async {
    final discovery = McpAuthorizationMetadataDiscovery(
      httpClient: RecordingAuthorizationHttpClient(
        (_) => authJson(<String, Object?>{
          ...protectedMetadata(),
          'resource': 'https://mcp.example.test/other',
        }),
      ),
    );

    await expectLater(
      discovery.discoverResource(
        Uri.parse(resource),
        wwwAuthenticate:
            'Bearer resource_metadata="https://metadata.example.test/prm"',
      ),
      throwsFormatException,
    );
  });

  test('authorization discovery tries OAuth then OIDC path variants', () async {
    final http = RecordingAuthorizationHttpClient(
      (request) {
        if (request.uri.path ==
            '/.well-known/oauth-authorization-server/tenant') {
          return authJson(const <String, Object?>{}, statusCode: 404);
        }
        expect(
          request.uri.path,
          '/.well-known/openid-configuration/tenant',
        );
        return authJson(serverMetadata());
      },
    );
    final metadata = await McpAuthorizationMetadataDiscovery(
      httpClient: http,
    ).discoverAuthorizationServer(Uri.parse(issuer));

    expect(metadata.issuer, Uri.parse(issuer));
    expect(metadata.codeChallengeMethods, contains('S256'));
    expect(http.requests, hasLength(2));
  });
}
