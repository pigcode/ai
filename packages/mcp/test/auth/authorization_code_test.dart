import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('authorization code flow validates state, PKCE, resource, and stores',
      () async {
    late Map<String, String> tokenForm;
    final http = _standardHttp(
      token: (request) {
        tokenForm = decodeForm(request.body);
        return authJson(
          const <String, Object?>{
            'access_token': 'access-secret',
            'refresh_token': 'refresh-secret',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'scope': 'tools:read',
          },
        );
      },
    );
    final browser = BrowserRedirect();
    final store = MemoryAuthorizationStore();
    final coordinator = _coordinator(
      http: http,
      browser: browser,
      store: store,
      provider: FixedRegistrationProvider(registration: registration()),
    );

    final token = await coordinator.authorize(redirectUri: redirect);
    final authorization = browser.opened!;
    expect(authorization.queryParameters['resource'], resource);
    expect(authorization.queryParameters['scope'], 'tools:read');
    expect(authorization.queryParameters['code_challenge_method'], 'S256');
    expect(authorization.queryParameters['state'], isNotEmpty);
    expect(tokenForm['grant_type'], 'authorization_code');
    expect(tokenForm['resource'], resource);
    expect(tokenForm['code_verifier'], isNotEmpty);
    expect(await store.load(Uri.parse(resource)), same(token));
    expect(
      await coordinator.headersFor(Uri.parse(resource)),
      <String, String>{'authorization': 'Bearer access-secret'},
    );
  });

  test('state mismatch aborts before token exchange', () async {
    var tokenRequests = 0;
    final http = _standardHttp(
      token: (_) {
        tokenRequests++;
        return authJson(const <String, Object?>{});
      },
    );
    final browser = BrowserRedirect()..overrideState = 'attacker-state';
    final coordinator = _coordinator(
      http: http,
      browser: browser,
      store: MemoryAuthorizationStore(),
      provider: FixedRegistrationProvider(registration: registration()),
    );

    await expectLater(
      coordinator.authorize(redirectUri: redirect),
      throwsA(
        isA<McpAuthorizationException>().having(
          (error) => error.code,
          'code',
          'mcp_oauth_state_mismatch',
        ),
      ),
    );
    expect(tokenRequests, 0);
  });

  test('registration priority is pre-registration, CIMD, then DCR', () async {
    for (final variant in <String>['pre', 'cimd', 'dcr']) {
      final seen = <String>[];
      final http = RecordingAuthorizationHttpClient(
        (request) {
          if (request.method == 'GET' &&
              request.uri.host == 'mcp.example.test') {
            return authJson(protectedMetadata());
          }
          if (request.method == 'GET') {
            return authJson(
              serverMetadata(
                cimd: variant != 'pre',
                dcr: variant == 'dcr',
              ),
            );
          }
          if (request.uri.path.endsWith('/register')) {
            seen.add('dcr');
            return authJson(
              const <String, Object?>{
                'client_id': 'dynamic-client',
                'token_endpoint_auth_method': 'none',
              },
              statusCode: 201,
            );
          }
          final form = decodeForm(request.body);
          seen.add(form['client_id']!);
          return authJson(
            const <String, Object?>{
              'access_token': 'secret',
              'token_type': 'Bearer',
            },
          );
        },
      );
      final provider = switch (variant) {
        'pre' => FixedRegistrationProvider(registration: registration()),
        'cimd' => FixedRegistrationProvider(
            clientMetadataDocument:
                Uri.parse('https://client.example.test/client.json'),
          ),
        _ => FixedRegistrationProvider(),
      };
      final coordinator = _coordinator(
        http: http,
        browser: BrowserRedirect(),
        store: MemoryAuthorizationStore(),
        provider: provider,
      );

      await coordinator.authorize(redirectUri: redirect);
      expect(
        seen.last,
        switch (variant) {
          'pre' => 'pigcode-client',
          'cimd' => 'https://client.example.test/client.json',
          _ => 'dynamic-client',
        },
      );
      expect(seen.contains('dcr'), variant == 'dcr');
    }
  });

  test('refresh keeps resource binding and supports token rotation', () async {
    var tokenRequests = 0;
    late Map<String, String> refreshForm;
    final http = _standardHttp(
      token: (request) {
        tokenRequests++;
        if (tokenRequests == 1) {
          return authJson(
            const <String, Object?>{
              'access_token': 'initial-access',
              'refresh_token': 'initial-refresh',
              'token_type': 'Bearer',
            },
          );
        }
        refreshForm = decodeForm(request.body);
        return authJson(
          const <String, Object?>{
            'access_token': 'rotated-access',
            'refresh_token': 'rotated-refresh',
            'token_type': 'Bearer',
          },
        );
      },
    );
    final browser = BrowserRedirect();
    final store = MemoryAuthorizationStore();
    final coordinator = _coordinator(
      http: http,
      browser: browser,
      store: store,
      provider: FixedRegistrationProvider(registration: registration()),
    );

    await coordinator.authorize(redirectUri: redirect);
    final refreshed = await coordinator.refresh(
      registrationRedirectUri: redirect,
    );
    expect(refreshForm['grant_type'], 'refresh_token');
    expect(refreshForm['refresh_token'], 'initial-refresh');
    expect(refreshForm['resource'], resource);
    expect(
      refreshed.authorizationHeaderFor(Uri.parse(resource)),
      'Bearer rotated-access',
    );
    expect(refreshed.refreshTokenFor(Uri.parse(resource)), 'rotated-refresh');
  });
}

RecordingAuthorizationHttpClient _standardHttp({
  required McpAuthorizationHttpResponse Function(
    McpAuthorizationHttpRequest request,
  ) token,
}) =>
    RecordingAuthorizationHttpClient(
      (request) {
        if (request.method == 'GET' && request.uri.host == 'mcp.example.test') {
          return authJson(protectedMetadata());
        }
        if (request.method == 'GET') {
          return authJson(serverMetadata());
        }
        expect(request.uri.path, '/tenant/token');
        expect(
          request.headers['content-type'],
          'application/x-www-form-urlencoded',
        );
        return token(request);
      },
    );

McpAuthorizationCoordinator _coordinator({
  required RecordingAuthorizationHttpClient http,
  required BrowserRedirect browser,
  required MemoryAuthorizationStore store,
  required FixedRegistrationProvider provider,
}) =>
    McpAuthorizationCoordinator(
      resource: Uri.parse(resource),
      httpClient: http,
      store: store,
      browser: browser,
      redirectReceiver: browser,
      registrationProvider: provider,
      random: FixedRandom(),
      clock: FixedClock(),
    );
