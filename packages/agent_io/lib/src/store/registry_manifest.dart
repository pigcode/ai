import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'store_digest.dart';
import 'store_format.dart';
import 'store_limits.dart';

enum RegistryKind {
  identity('identity'),
  command('command'),
  sessionCatalog('session-catalog'),
  createSessionCommand('create-session-command');

  const RegistryKind(this.wireName);

  final String wireName;

  static RegistryKind parse(String value) {
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    throw StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Unknown registry kind.',
    );
  }
}

final class RegistryChunkArtifact<T> {
  RegistryChunkArtifact({
    required Uint8List bytes,
    required this.reference,
    required List<T> entries,
  })  : bytes = Uint8List.fromList(bytes),
        entries = List<T>.unmodifiable(entries);

  final Uint8List bytes;
  final RegistryChunkReference reference;
  final List<T> entries;
}

final class RegistryChunkReference {
  const RegistryChunkReference({
    required this.shard,
    required this.firstKey,
    required this.lastKey,
    required this.entryCount,
    required this.byteLength,
    required this.digest,
  });

  final String shard;
  final String firstKey;
  final String lastKey;
  final int entryCount;
  final int byteLength;
  final String digest;

  Map<String, Object?> toJson() => <String, Object?>{
        'byteLength': byteLength,
        'digest': digest,
        'entryCount': entryCount,
        'firstKey': firstKey,
        'lastKey': lastKey,
        'shard': shard,
      };
}

final class RegistryManifest {
  RegistryManifest({
    required this.kind,
    required this.generation,
    required List<RegistryChunkReference> chunks,
    required this.entryCount,
    required this.totalBytes,
    required this.rootDigest,
  }) : chunks = List<RegistryChunkReference>.unmodifiable(chunks);

  final RegistryKind kind;
  final int generation;
  final List<RegistryChunkReference> chunks;
  final int entryCount;
  final int totalBytes;
  final String rootDigest;

  Map<String, Object?> toJson({bool includeRootDigest = true}) =>
      <String, Object?>{
        'chunks': <Object?>[for (final chunk in chunks) chunk.toJson()],
        'entryCount': entryCount,
        'formatVersion': agentManifestFormatVersion,
        'generation': generation,
        'registryKind': kind.wireName,
        if (includeRootDigest) 'rootDigest': rootDigest,
        'totalBytes': totalBytes,
      };
}

final class RegistryManifestCodec {
  const RegistryManifestCodec({
    this.limits = const StoreLimits(),
  });

  final StoreLimits limits;

  Uint8List encode({
    required RegistryKind kind,
    required int generation,
    required List<RegistryChunkReference> chunks,
  }) {
    final normalized = List<RegistryChunkReference>.of(chunks)
      ..sort(_compareChunk);
    _validateChunks(normalized);
    final entryCount = normalized.fold<int>(
      0,
      (total, chunk) => total + chunk.entryCount,
    );
    final totalBytes = normalized.fold<int>(
      0,
      (total, chunk) => total + chunk.byteLength,
    );
    _validateLimits(entryCount, totalBytes);
    if (generation <= 0) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Registry manifest generation must be positive.',
      );
    }
    final unsigned = RegistryManifest(
      kind: kind,
      generation: generation,
      chunks: normalized,
      entryCount: entryCount,
      totalBytes: totalBytes,
      rootDigest: '',
    );
    final rootDigest = _rootDigest(unsigned);
    final manifest = RegistryManifest(
      kind: kind,
      generation: generation,
      chunks: normalized,
      entryCount: entryCount,
      totalBytes: totalBytes,
      rootDigest: rootDigest,
    );
    final bytes = canonicalJsonBytes(manifest.toJson());
    _validateManifestByteLength(bytes.length);
    return bytes;
  }

  RegistryManifest decode(
    Uint8List bytes, {
    RegistryKind? expectedKind,
  }) {
    _validateManifestByteLength(bytes.length);
    final object = decodeCanonicalRegistryObject(bytes);
    requireExactRegistryKeys(
      object,
      const <String>{
        'chunks',
        'entryCount',
        'formatVersion',
        'generation',
        'registryKind',
        'rootDigest',
        'totalBytes',
      },
    );
    final version = requireRegistryInt(object, 'formatVersion');
    if (version != agentManifestFormatVersion) {
      throw const StoreFormatException(
        StoreFormatErrorCode.unsupportedVersion,
        'Unsupported registry manifest version.',
      );
    }
    final kind = RegistryKind.parse(requireRegistryString(
      object,
      'registryKind',
    ));
    if (expectedKind != null && kind != expectedKind) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Registry manifest kind does not match its location.',
      );
    }
    final rawChunks = object['chunks'];
    if (rawChunks is! List<Object?>) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Registry manifest chunks must be a list.',
      );
    }
    final chunks = <RegistryChunkReference>[];
    for (final rawChunk in rawChunks) {
      if (rawChunk is! Map<String, Object?>) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Registry chunk reference must be an object.',
        );
      }
      requireExactRegistryKeys(
        rawChunk,
        const <String>{
          'byteLength',
          'digest',
          'entryCount',
          'firstKey',
          'lastKey',
          'shard',
        },
      );
      chunks.add(RegistryChunkReference(
        shard: requireRegistryString(rawChunk, 'shard'),
        firstKey: requireRegistryString(rawChunk, 'firstKey'),
        lastKey: requireRegistryString(rawChunk, 'lastKey'),
        entryCount: requireRegistryInt(rawChunk, 'entryCount'),
        byteLength: requireRegistryInt(rawChunk, 'byteLength'),
        digest: requireRegistryDigest(rawChunk, 'digest'),
      ));
    }
    _validateChunks(chunks);
    final entryCount = requireRegistryInt(object, 'entryCount');
    final totalBytes = requireRegistryInt(object, 'totalBytes');
    final calculatedEntryCount = chunks.fold<int>(
      0,
      (total, chunk) => total + chunk.entryCount,
    );
    final calculatedTotalBytes = chunks.fold<int>(
      0,
      (total, chunk) => total + chunk.byteLength,
    );
    if (entryCount != calculatedEntryCount ||
        totalBytes != calculatedTotalBytes) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Registry manifest totals do not match its chunks.',
      );
    }
    _validateLimits(entryCount, totalBytes);
    final manifest = RegistryManifest(
      kind: kind,
      generation: requirePositiveRegistryInt(object, 'generation'),
      chunks: chunks,
      entryCount: entryCount,
      totalBytes: totalBytes,
      rootDigest: requireRegistryDigest(object, 'rootDigest'),
    );
    if (manifest.rootDigest != _rootDigest(manifest)) {
      throw const StoreFormatException(
        StoreFormatErrorCode.digestMismatch,
        'Registry manifest root digest does not match.',
      );
    }
    return manifest;
  }

  void verifyChunks(
    RegistryManifest manifest,
    Map<String, Uint8List> chunksByDigest,
  ) {
    if (chunksByDigest.length != manifest.chunks.length) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Registry chunk set is not exact.',
      );
    }
    for (final reference in manifest.chunks) {
      final bytes = chunksByDigest[reference.digest];
      if (bytes == null ||
          bytes.length != reference.byteLength ||
          storeHex(storeSha256(bytes)) != reference.digest) {
        throw const StoreFormatException(
          StoreFormatErrorCode.digestMismatch,
          'Registry chunk does not match its manifest reference.',
        );
      }
    }
  }

  String _rootDigest(RegistryManifest manifest) => storeHex(storeDomainDigest(
        'pigcode-agent-registry-root-v1',
        <List<int>>[
          canonicalJsonBytes(<String, Object?>{
            'chunks': <Object?>[
              for (final chunk in manifest.chunks) chunk.toJson(),
            ],
            'entryCount': manifest.entryCount,
            'formatVersion': agentManifestFormatVersion,
            'registryKind': manifest.kind.wireName,
            'totalBytes': manifest.totalBytes,
          }),
        ],
      ));

  void _validateChunks(List<RegistryChunkReference> chunks) {
    RegistryChunkReference? previous;
    for (final chunk in chunks) {
      if (!RegExp(r'^[a-z0-9-]{1,32}$').hasMatch(chunk.shard) ||
          chunk.firstKey.isEmpty ||
          chunk.lastKey.isEmpty ||
          chunk.firstKey.compareTo(chunk.lastKey) > 0 ||
          chunk.entryCount <= 0 ||
          chunk.byteLength <= 0 ||
          !isStoreDigest(chunk.digest)) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Registry chunk reference is invalid.',
        );
      }
      if (previous != null) {
        final order = _compareChunk(previous, chunk);
        if (order >= 0 ||
            (previous.shard == chunk.shard &&
                previous.lastKey.compareTo(chunk.firstKey) >= 0)) {
          throw const StoreFormatException(
            StoreFormatErrorCode.registryViolation,
            'Registry chunks overlap or are not strictly sorted.',
          );
        }
      }
      previous = chunk;
    }
  }

  void _validateLimits(int entryCount, int totalBytes) {
    if (entryCount > limits.maximumRegistryEntries ||
        totalBytes > limits.maximumRegistryBytes ||
        totalBytes > StoreLimits.hardMaximumRegistryBytes) {
      throw const StoreFormatException(
        StoreFormatErrorCode.resourceLimit,
        'Registry exceeds configured resource limits.',
      );
    }
  }

  void _validateManifestByteLength(int byteLength) {
    if (byteLength > limits.maximumRegistryBytes ||
        byteLength > StoreLimits.hardMaximumRegistryBytes) {
      throw const StoreFormatException(
        StoreFormatErrorCode.resourceLimit,
        'Registry manifest exceeds configured resource limits.',
      );
    }
  }
}

int _compareChunk(
  RegistryChunkReference left,
  RegistryChunkReference right,
) {
  final shardOrder = left.shard.compareTo(right.shard);
  return shardOrder != 0 ? shardOrder : left.firstKey.compareTo(right.firstKey);
}

Map<String, Object?> decodeCanonicalRegistryObject(Uint8List bytes) {
  late final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const StoreFormatException(
      StoreFormatErrorCode.nonCanonicalJson,
      'Registry artifact is not valid UTF-8 JSON.',
    );
  }
  if (decoded is! Map<String, Object?> ||
      !storeBytesEqual(canonicalJsonBytes(decoded), bytes)) {
    throw const StoreFormatException(
      StoreFormatErrorCode.nonCanonicalJson,
      'Registry artifact is not canonical JSON.',
    );
  }
  return decoded;
}

void requireExactRegistryKeys(
  Map<String, Object?> value,
  Set<String> expected,
) {
  if (value.keys.toSet().length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    throw const StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Registry artifact has missing or unknown fields.',
    );
  }
}

String requireRegistryString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) {
    throw StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Registry field $key must be a string.',
    );
  }
  return field;
}

int requireRegistryInt(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int || field < 0) {
    throw StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Registry field $key must be a non-negative integer.',
    );
  }
  return field;
}

int requirePositiveRegistryInt(Map<String, Object?> value, String key) {
  final field = requireRegistryInt(value, key);
  if (field == 0) {
    throw StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Registry field $key must be positive.',
    );
  }
  return field;
}

String requireRegistryDigest(Map<String, Object?> value, String key) {
  final field = requireRegistryString(value, key);
  if (!isStoreDigest(field)) {
    throw StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Registry field $key must be a lowercase SHA-256 digest.',
    );
  }
  return field;
}

bool isStoreDigest(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
