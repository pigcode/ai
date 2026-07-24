import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

String composeStoreHeadDigest({
  required int sequence,
  required String journalHeadDigest,
  required String identityRegistryRootDigest,
  required String commandRegistryRootDigest,
  required int generation,
}) =>
    _domainDigest(
      'pigcode-agent-store-head-v1',
      <List<int>>[
        _u64(sequence),
        _digestBytes(journalHeadDigest),
        _digestBytes(identityRegistryRootDigest),
        _digestBytes(commandRegistryRootDigest),
        _u64(generation),
      ],
    );

String composeStoreRootHeadDigest({
  required int sequence,
  required String sessionCatalogRootDigest,
  required String createSessionCommandRegistryRootDigest,
  required int generation,
}) =>
    _domainDigest(
      'pigcode-agent-store-root-head-v1',
      <List<int>>[
        _u64(sequence),
        _digestBytes(sessionCatalogRootDigest),
        _digestBytes(createSessionCommandRegistryRootDigest),
        _u64(generation),
      ],
    );

String _domainDigest(String domain, List<List<int>> parts) {
  final bytes = BytesBuilder(copy: false)
    ..add(utf8.encode(domain))
    ..addByte(0);
  for (final part in parts) {
    bytes.add(part);
  }
  return sha256.convert(bytes.takeBytes()).toString();
}

Uint8List _u64(int value) {
  if (value < 0) {
    throw ArgumentError.value(value, 'value', 'must be non-negative');
  }
  final bytes = ByteData(8)..setUint64(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}

Uint8List _digestBytes(String value) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'value',
      'must be a lowercase SHA-256 digest',
    );
  }
  return Uint8List.fromList(<int>[
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ]);
}
