import 'dart:typed_data';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'registry_manifest.dart';
import 'store_digest.dart';
import 'store_format.dart';
import 'store_limits.dart';

final class CommandRegistryCodec {
  const CommandRegistryCodec({
    this.limits = const StoreLimits(),
  });

  final StoreLimits limits;

  RegistryChunkArtifact<AgentStoreAcceptedCommand> encodeChunk(
    Iterable<AgentStoreAcceptedCommand> entries,
  ) {
    final sorted = List<AgentStoreAcceptedCommand>.of(entries)
      ..sort((left, right) =>
          left.commandId.value.compareTo(right.commandId.value));
    final shard = _validateEntries(sorted);
    final bytes = canonicalJsonBytes(<String, Object?>{
      'entries': <Object?>[
        for (final entry in sorted)
          <String, Object?>{
            'commandId': entry.commandId.value,
            'contentDigest': entry.contentDigest,
            'receipt': entry.receipt,
          },
      ],
      'formatVersion': agentManifestFormatVersion,
      'registryKind': RegistryKind.command.wireName,
      'shard': shard,
    });
    _validateLimits(sorted.length, bytes.length);
    return _artifact(bytes, shard, sorted);
  }

  RegistryChunkArtifact<AgentStoreAcceptedCommand> decodeChunk(
    Uint8List bytes, {
    String? expectedShard,
  }) {
    _validateLimits(0, bytes.length);
    final object = decodeCanonicalRegistryObject(bytes);
    requireExactRegistryKeys(
      object,
      const <String>{
        'entries',
        'formatVersion',
        'registryKind',
        'shard',
      },
    );
    if (requireRegistryInt(object, 'formatVersion') !=
            agentManifestFormatVersion ||
        requireRegistryString(object, 'registryKind') !=
            RegistryKind.command.wireName) {
      throw const StoreFormatException(
        StoreFormatErrorCode.unsupportedVersion,
        'Unsupported command registry chunk.',
      );
    }
    final shard = requireRegistryString(object, 'shard');
    _validateShard(shard);
    if (expectedShard != null && shard != expectedShard) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Command registry shard does not match its location.',
      );
    }
    final rawEntries = object['entries'];
    if (rawEntries is! List<Object?> || rawEntries.isEmpty) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Command registry chunk must contain entries.',
      );
    }
    final entries = <AgentStoreAcceptedCommand>[];
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map<String, Object?>) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Command registry entry must be an object.',
        );
      }
      requireExactRegistryKeys(
        rawEntry,
        const <String>{'commandId', 'contentDigest', 'receipt'},
      );
      late final CommandId commandId;
      try {
        commandId = CommandId.parse(
          requireRegistryString(rawEntry, 'commandId'),
        );
      } on FormatException {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Command registry contains an invalid CommandId.',
        );
      }
      final contentDigest = requireRegistryDigest(rawEntry, 'contentDigest');
      final receipt = rawEntry['receipt'];
      if (receipt is! Map<String, Object?>) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Command registry receipt must be an object.',
        );
      }
      entries.add(AgentStoreAcceptedCommand(
        commandId: commandId,
        contentDigest: contentDigest,
        receipt: receipt,
      ));
    }
    final actualShard = _validateEntries(entries);
    if (actualShard != shard) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Command registry entry is in the wrong shard.',
      );
    }
    _validateLimits(entries.length, bytes.length);
    return _artifact(bytes, shard, entries);
  }

  RegistryChunkArtifact<AgentStoreAcceptedCommand> _artifact(
    Uint8List bytes,
    String shard,
    List<AgentStoreAcceptedCommand> entries,
  ) =>
      RegistryChunkArtifact<AgentStoreAcceptedCommand>(
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

  String _validateEntries(List<AgentStoreAcceptedCommand> entries) {
    if (entries.isEmpty) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Command registry chunk cannot be empty.',
      );
    }
    final shard = commandRegistryShard(entries.first.commandId);
    String? previous;
    for (final entry in entries) {
      final key = entry.commandId.value;
      if (commandRegistryShard(entry.commandId) != shard ||
          !isStoreDigest(entry.contentDigest) ||
          (previous != null && previous.compareTo(key) >= 0)) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Command registry entries must be valid, unique, and sorted.',
        );
      }
      previous = key;
    }
    return shard;
  }

  void _validateLimits(int entryCount, int byteLength) {
    if (entryCount > limits.maximumRegistryEntries ||
        byteLength > limits.maximumRegistryBytes ||
        byteLength > StoreLimits.hardMaximumRegistryBytes) {
      throw const StoreFormatException(
        StoreFormatErrorCode.resourceLimit,
        'Command registry exceeds configured limits.',
      );
    }
  }
}

String commandRegistryShard(CommandId commandId) =>
    commandId.value.substring(4, 6);

void _validateShard(String value) {
  if (!RegExp(r'^[0-9abcdefghjkmnpqrstvwxyz]{2}$').hasMatch(value)) {
    throw const StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Command registry shard is invalid.',
    );
  }
}
