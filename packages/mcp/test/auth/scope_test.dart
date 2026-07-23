import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('challenge scopes override scopes_supported', () async {
    late Map<String, String> tokenForm;
    final http = _routingHttp((request) {
      tokenForm = decodeForm(request.body);
      return authJson(
        const <String, Object?>{
          'access_token': 'scope-token',
          'token_type': 'Bearer',
        },
      );
    });
    final browser = BrowserRedirect();
    final coordinator = _coordinator(http, browser);

    await coordinator.authorize(
      redirectUri: redirect,
      wwwAuthenticate: 'Bearer scope="files:write files:read", '
          'resource_metadata="https://mcp.example.test/'
          '.well-known/oauth-protected-resource/mcp"',
    );
    expect(tokenForm['resource'], resource);
    expect(
      browser.opened!.queryParameters['scope'],
      'files:read files:write',
    );
  });

  test('step-up retries are bounded', () async {
    var tokenRequests = 0;
    final http = _routingHttp((_) {
      tokenRequests++;
      return authJson(
        const <String, Object?>{
          'access_token': 'step-up-token',
          'token_type': 'Bearer',
        },
      );
    });
    final browser = BrowserRedirect();
    final coordinator = McpAuthorizationCoordinator(
      resource: Uri.parse(resource),
      httpClient: http,
      store: MemoryAuthorizationStore(),
      browser: browser,
      redirectReceiver: browser,
      registrationProvider:
          FixedRegistrationProvider(registration: registration()),
      random: FixedRandom(),
      clock: FixedClock(),
      maxScopeRetries: 1,
    );
    const challenge = 'Bearer error="insufficient_scope", scope="tools:write"';

    await coordinator.authorizeAfterChallenge(
      redirectUri: redirect,
      wwwAuthenticate: challenge,
    );
    await expectLater(
      () => coordinator.authorizeAfterChallenge(
        redirectUri: redirect,
        wwwAuthenticate: challenge,
      ),
      throwsA(
        isA<McpAuthorizationException>().having(
          (error) => error.code,
          'code',
          'mcp_oauth_scope_retry_limit',
        ),
      ),
    );
    expect(tokenRequests, 1);
  });
}

RecordingAuthorizationHttpClient _routingHttp(
  McpAuthorizationHttpResponse Function(
    McpAuthorizationHttpRequest request,
  ) token,
) =>
    RecordingAuthorizationHttpClient(
      (request) {
        if (request.method == 'GET' && request.uri.host == 'mcp.example.test') {
          return authJson(protectedMetadata());
        }
        if (request.method == 'GET') {
          return authJson(serverMetadata());
        }
        return token(request);
      },
    );

McpAuthorizationCoordinator _coordinator(
  RecordingAuthorizationHttpClient http,
  BrowserRedirect browser,
) =>
    McpAuthorizationCoordinator(
      resource: Uri.parse(resource),
      httpClient: http,
      store: MemoryAuthorizationStore(),
      browser: browser,
      redirectReceiver: browser,
      registrationProvider:
          FixedRegistrationProvider(registration: registration()),
      random: FixedRandom(),
      clock: FixedClock(),
    );
