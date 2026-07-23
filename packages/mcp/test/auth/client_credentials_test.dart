import 'dart:convert';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  for (final method in <String>[
    'client_secret_basic',
    'client_secret_post',
    'none',
  ]) {
    test('client credentials supports $method and resource binding', () async {
      late McpAuthorizationHttpRequest tokenRequest;
      final http = RecordingAuthorizationHttpClient(
        (request) {
          if (request.method == 'GET' &&
              request.uri.host == 'mcp.example.test') {
            return authJson(protectedMetadata(scopes: null));
          }
          if (request.method == 'GET') {
            return authJson(serverMetadata(authMethod: method, pkce: false));
          }
          tokenRequest = request;
          return authJson(
            const <String, Object?>{
              'access_token': 'client-token',
              'token_type': 'Bearer',
            },
          );
        },
      );
      final store = MemoryAuthorizationStore();
      final browser = BrowserRedirect();
      final coordinator = McpAuthorizationCoordinator(
        resource: Uri.parse(resource),
        httpClient: http,
        store: store,
        browser: browser,
        redirectReceiver: browser,
        registrationProvider: FixedRegistrationProvider(
          registration: registration(
            authMethod: method,
            secret: method == 'none' ? null : 'client-secret',
          ),
        ),
        random: FixedRandom(),
        clock: FixedClock(),
      );

      final token = await coordinator.clientCredentials(
        registrationRedirectUri: redirect,
      );
      final form = decodeForm(tokenRequest.body);
      expect(form['grant_type'], 'client_credentials');
      expect(form['resource'], resource);
      expect(form, isNot(contains('scope')));
      switch (method) {
        case 'client_secret_basic':
          expect(tokenRequest.headers['authorization'], startsWith('Basic '));
          expect(
            utf8.decode(
              base64.decode(
                tokenRequest.headers['authorization']!.substring(6),
              ),
            ),
            contains('client-secret'),
          );
          expect(form, isNot(contains('client_secret')));
        case 'client_secret_post':
          expect(form['client_id'], 'pigcode-client');
          expect(form['client_secret'], 'client-secret');
          expect(tokenRequest.headers, isNot(contains('authorization')));
        case 'none':
          expect(form['client_id'], 'pigcode-client');
          expect(form, isNot(contains('client_secret')));
      }
      expect(
        token.authorizationHeaderFor(Uri.parse(resource)),
        'Bearer client-token',
      );
    });
  }
}
