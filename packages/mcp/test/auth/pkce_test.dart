import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('PKCE uses a 43-character verifier and SHA-256 challenge', () {
    final pair = createMcpPkce(FixedRandom());
    final expected = base64Url
        .encode(sha256.convert(ascii.encode(pair.verifier)).bytes)
        .replaceAll('=', '');

    expect(pair.verifier, hasLength(43));
    expect(pair.verifier, isNot(contains('=')));
    expect(pair.challenge, expected);
    expect(pair.toString(), isNot(contains(pair.verifier)));
  });

  test('OAuth state is high-entropy URL-safe data', () {
    final state = createMcpOAuthState(FixedRandom());
    expect(state, hasLength(43));
    expect(state, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
  });
}
