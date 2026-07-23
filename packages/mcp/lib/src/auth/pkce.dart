import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'contracts.dart';

final class McpPkcePair {
  const McpPkcePair({
    required this.verifier,
    required this.challenge,
  });

  final String verifier;
  final String challenge;

  @override
  String toString() => 'McpPkcePair(S256)';
}

McpPkcePair createMcpPkce(McpSecureRandom random) {
  final verifier = _base64Url(random.bytes(32));
  if (verifier.length < 43 || verifier.length > 128) {
    throw StateError('Generated PKCE verifier has an invalid length.');
  }
  return McpPkcePair(
    verifier: verifier,
    challenge: _base64Url(sha256.convert(ascii.encode(verifier)).bytes),
  );
}

String createMcpOAuthState(McpSecureRandom random) =>
    _base64Url(random.bytes(32));

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
