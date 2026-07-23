import 'dart:convert';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('token strings and safe JSON metadata never contain secrets', () {
    final token = McpAccessToken(
      accessToken: 'access-super-secret',
      refreshToken: 'refresh-super-secret',
      resource: Uri.parse(resource),
      scopes: const <String>{'tools:read'},
      issuedAt: DateTime.utc(2026, 7, 23),
      expiresAt: DateTime.utc(2026, 7, 23, 1),
    );
    final registration = McpClientRegistration(
      clientId: 'client',
      clientSecret: 'registration-super-secret',
      tokenEndpointAuthMethod: 'client_secret_post',
      redirectUris: <Uri>[redirect],
    );

    for (final rendered in <String>[
      token.toString(),
      jsonEncode(token.safeMetadata()),
      registration.toString(),
      jsonEncode(registration.safeMetadata()),
    ]) {
      expect(rendered, isNot(contains('access-super-secret')));
      expect(rendered, isNot(contains('refresh-super-secret')));
      expect(rendered, isNot(contains('registration-super-secret')));
    }
    expect(
      () => freezeJsonValue(token),
      throwsA(isA<JsonValueException>()),
    );
  });

  test('audience mismatch is rejected and expired tokens are not sent',
      () async {
    final clock = FixedClock(DateTime.utc(2026, 7, 23, 2));
    final store = MemoryAuthorizationStore();
    final token = McpAccessToken(
      accessToken: 'bound-secret',
      resource: Uri.parse(resource),
      scopes: const <String>{},
      issuedAt: DateTime.utc(2026, 7, 23),
      expiresAt: DateTime.utc(2026, 7, 23, 1),
    );
    await store.save(token);
    expect(
      () => token.authorizationHeaderFor(
        Uri.parse('https://other.example.test/mcp'),
      ),
      throwsStateError,
    );

    final browser = BrowserRedirect();
    final coordinator = McpAuthorizationCoordinator(
      resource: Uri.parse(resource),
      httpClient: RecordingAuthorizationHttpClient(
        (_) => throw StateError('HTTP must not be called.'),
      ),
      store: store,
      browser: browser,
      redirectReceiver: browser,
      registrationProvider: FixedRegistrationProvider(),
      random: FixedRandom(),
      clock: clock,
    );
    expect(
      await coordinator.headersFor(Uri.parse(resource)),
      isEmpty,
    );
    await expectLater(
      coordinator.headersFor(Uri.parse('https://other.example.test/mcp')),
      throwsA(
        isA<McpAuthorizationException>().having(
          (error) => error.code,
          'code',
          'mcp_oauth_token_target_mismatch',
        ),
      ),
    );
  });

  test('stores are caller-owned and isolated per coordinator', () async {
    final first = MemoryAuthorizationStore();
    final second = MemoryAuthorizationStore();
    await first.save(
      McpAccessToken(
        accessToken: 'only-first',
        resource: Uri.parse(resource),
        scopes: const <String>{},
        issuedAt: DateTime.utc(2026, 7, 23),
      ),
    );

    expect(await first.load(Uri.parse(resource)), isNotNull);
    expect(await second.load(Uri.parse(resource)), isNull);
  });
}
