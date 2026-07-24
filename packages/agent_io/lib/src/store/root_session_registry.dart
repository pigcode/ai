import 'dart:typed_data';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'registry_manifest.dart';
import 'store_digest.dart';
import 'store_format.dart';
import 'store_limits.dart';

final class RootSessionCommandEntry {
  RootSessionCommandEntry({
    required this.commandId,
    required this.contentDigest,
    required this.sessionId,
    required Map<String, Object?> receipt,
  }) : receipt = DomainJson.freeze(receipt)! as Map<String, Object?>;

  final CommandId commandId;
  final String contentDigest;
  final SessionId sessionId;
  final Map<String, Object?> receipt;
}

final class RootSessionCatalogCodec {
  const RootSessionCatalogCodec({
    this.limits = const StoreLimits(),
  });

  final StoreLimits limits;

  RegistryChunkArtifact<SessionId> encodeChunk(Iterable<SessionId> entries) {
    final sorted = List<SessionId>.of(entries)
      ..sort((left, right) => left.value.compareTo(right.value));
    final shard = _validateCatalogEntries(sorted);
    final bytes = canonicalJsonBytes(<String, Object?>{
      'entries': <Object?>[
        for (final sessionId in sorted)
          <String, Object?>{'sessionId': sessionId.value},
      ],
      'formatVersion': agentManifestFormatVersion,
      'registryKind': RegistryKind.sessionCatalog.wireName,
      'shard': shard,
    });
    _validateLimits(limits, sorted.length, bytes.length);
    return _catalogArtifact(bytes, shard, sorted);
  }

  RegistryChunkArtifact<SessionId> decodeChunk(
    Uint8List bytes, {
    String? expectedShard,
  }) {
    _validateLimits(limits, 0, bytes.length);
    final object = decodeCanonicalRegistryObject(bytes);
    _validateChunkEnvelope(
      object,
      expectedKind: RegistryKind.sessionCatalog,
    );
    final shard = requireRegistryString(object, 'shard');
    _validateOpaqueShard(shard);
    if (expectedShard != null && shard != expectedShard) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Session catalog shard does not match its location.',
      );
    }
    final rawEntries = object['entries'];
    if (rawEntries is! List<Object?> || rawEntries.isEmpty) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Session catalog chunk must contain entries.',
      );
    }
    final entries = <SessionId>[];
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map<String, Object?>) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Session catalog entry must be an object.',
        );
      }
      requireExactRegistryKeys(rawEntry, const <String>{'sessionId'});
      try {
        entries.add(
          SessionId.parse(requireRegistryString(rawEntry, 'sessionId')),
        );
      } on FormatException {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Session catalog contains an invalid SessionId.',
        );
      }
    }
    final actualShard = _validateCatalogEntries(entries);
    if (actualShard != shard) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Session catalog entry is in the wrong shard.',
      );
    }
    _validateLimits(limits, entries.length, bytes.length);
    return _catalogArtifact(bytes, shard, entries);
  }

  RegistryChunkArtifact<SessionId> _catalogArtifact(
    Uint8List bytes,
    String shard,
    List<SessionId> entries,
  ) =>
      RegistryChunkArtifact<SessionId>(
        bytes: bytes,
        reference: RegistryChunkReference(
          shard: shard,
          firstKey: entries.first.value,
          lastKey: entries.last.value,
          entryCount: entries.length,
          byteLength: bytes.length,
          digest: storeHex(storeSha256(bytes)),
        ),
        entries: entries,
      );
}

final class RootSessionCommandRegistryCodec {
  const RootSessionCommandRegistryCodec({
    this.limits = const StoreLimits(),
  });

  final StoreLimits limits;

  RegistryChunkArtifact<RootSessionCommandEntry> encodeChunk(
    Iterable<RootSessionCommandEntry> entries,
  ) {
    final sorted = List<RootSessionCommandEntry>.of(entries)
      ..sort((left, right) =>
          left.commandId.value.compareTo(right.commandId.value));
    final shard = _validateCommandEntries(sorted);
    final bytes = canonicalJsonBytes(<String, Object?>{
      'entries': <Object?>[
        for (final entry in sorted)
          <String, Object?>{
            'commandId': entry.commandId.value,
            'contentDigest': entry.contentDigest,
            'receipt': entry.receipt,
            'sessionId': entry.sessionId.value,
          },
      ],
      'formatVersion': agentManifestFormatVersion,
      'registryKind': RegistryKind.createSessionCommand.wireName,
      'shard': shard,
    });
    _validateLimits(limits, sorted.length, bytes.length);
    return _commandArtifact(bytes, shard, sorted);
  }

  RegistryChunkArtifact<RootSessionCommandEntry> decodeChunk(
    Uint8List bytes, {
    String? expectedShard,
  }) {
    _validateLimits(limits, 0, bytes.length);
    final object = decodeCanonicalRegistryObject(bytes);
    _validateChunkEnvelope(
      object,
      expectedKind: RegistryKind.createSessionCommand,
    );
    final shard = requireRegistryString(object, 'shard');
    _validateOpaqueShard(shard);
    if (expectedShard != null && shard != expectedShard) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Root command registry shard does not match its location.',
      );
    }
    final rawEntries = object['entries'];
    if (rawEntries is! List<Object?> || rawEntries.isEmpty) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Root command registry chunk must contain entries.',
      );
    }
    final entries = <RootSessionCommandEntry>[];
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map<String, Object?>) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Root command registry entry must be an object.',
        );
      }
      requireExactRegistryKeys(
        rawEntry,
        const <String>{
          'commandId',
          'contentDigest',
          'receipt',
          'sessionId',
        },
      );
      final receipt = rawEntry['receipt'];
      if (receipt is! Map<String, Object?>) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Root command receipt must be an object.',
        );
      }
      try {
        entries.add(RootSessionCommandEntry(
          commandId:
              CommandId.parse(requireRegistryString(rawEntry, 'commandId')),
          contentDigest: requireRegistryDigest(rawEntry, 'contentDigest'),
          sessionId:
              SessionId.parse(requireRegistryString(rawEntry, 'sessionId')),
          receipt: receipt,
        ));
      } on FormatException {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Root command registry contains an invalid typed ID.',
        );
      }
    }
    final actualShard = _validateCommandEntries(entries);
    if (actualShard != shard) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Root command entry is in the wrong shard.',
      );
    }
    _validateLimits(limits, entries.length, bytes.length);
    return _commandArtifact(bytes, shard, entries);
  }

  RegistryChunkArtifact<RootSessionCommandEntry> _commandArtifact(
    Uint8List bytes,
    String shard,
    List<RootSessionCommandEntry> entries,
  ) =>
      RegistryChunkArtifact<RootSessionCommandEntry>(
        bytes: bytes,
        reference: RegistryChunkReference(
          shard: shard,
          firstKey: entries.first.commandId.value,
          lastKey: entries.last.commandId.value,
          entryCount: entries.length,
          byteLength: bytes.length,
          digest: storeHex(storeSha256(bytes)),
        ),
        entries: entries,
      );
}

String _validateCatalogEntries(List<SessionId> entries) {
  if (entries.isEmpty) {
    throw const StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Session catalog chunk cannot be empty.',
    );
  }
  final shard = sessionRegistryShard(entries.first);
  String? previous;
  for (final entry in entries) {
    if (sessionRegistryShard(entry) != shard ||
        (previous != null && previous.compareTo(entry.value) >= 0)) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Session catalog entries must be unique and sorted.',
      );
    }
    previous = entry.value;
  }
  return shard;
}

String _validateCommandEntries(List<RootSessionCommandEntry> entries) {
  if (entries.isEmpty) {
    throw const StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Root command registry chunk cannot be empty.',
    );
  }
  final shard = commandRootRegistryShard(entries.first.commandId);
  String? previous;
  for (final entry in entries) {
    if (commandRootRegistryShard(entry.commandId) != shard ||
        !isStoreDigest(entry.contentDigest) ||
        (previous != null && previous.compareTo(entry.commandId.value) >= 0)) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Root command entries must be valid, unique, and sorted.',
      );
    }
    previous = entry.commandId.value;
  }
  return shard;
}

void _validateChunkEnvelope(
  Map<String, Object?> value, {
  required RegistryKind expectedKind,
}) {
  requireExactRegistryKeys(
    value,
    const <String>{
      'entries',
      'formatVersion',
      'registryKind',
      'shard',
    },
  );
  if (requireRegistryInt(value, 'formatVersion') !=
          agentManifestFormatVersion ||
      requireRegistryString(value, 'registryKind') != expectedKind.wireName) {
    throw const StoreFormatException(
      StoreFormatErrorCode.unsupportedVersion,
      'Unsupported root registry chunk.',
    );
  }
}

void _validateLimits(StoreLimits limits, int entryCount, int byteLength) {
  if (entryCount > limits.maximumRegistryEntries ||
      byteLength > limits.maximumRegistryBytes ||
      byteLength > StoreLimits.hardMaximumRegistryBytes) {
    throw const StoreFormatException(
      StoreFormatErrorCode.resourceLimit,
      'Root registry exceeds configured limits.',
    );
  }
}

void _validateOpaqueShard(String value) {
  if (!RegExp(r'^[0-9abcdefghjkmnpqrstvwxyz]{2}$').hasMatch(value)) {
    throw const StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Root registry shard is invalid.',
    );
  }
}

String sessionRegistryShard(SessionId sessionId) =>
    sessionId.value.substring(4, 6);

String commandRootRegistryShard(CommandId commandId) =>
    commandId.value.substring(4, 6);
