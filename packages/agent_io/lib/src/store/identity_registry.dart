import 'dart:typed_data';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'registry_manifest.dart';
import 'store_digest.dart';
import 'store_format.dart';
import 'store_limits.dart';

enum AgentIdentityKind {
  session('ses'),
  run('run'),
  event('evt'),
  command('cmd'),
  workItem('wrk'),
  attempt('att'),
  approval('apr'),
  deferredOperation('dop'),
  runtimeResource('res'),
  snapshot('snp');

  const AgentIdentityKind(this.prefix);

  final String prefix;

  static AgentIdentityKind forId(OpaqueId id) {
    final prefix = id.value.substring(0, 3);
    for (final kind in values) {
      if (kind.prefix == prefix) return kind;
    }
    throw const StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Unsupported identity kind.',
    );
  }

  static AgentIdentityKind parse(String value) {
    for (final kind in values) {
      if (kind.prefix == value) return kind;
    }
    throw const StoreFormatException(
      StoreFormatErrorCode.registryViolation,
      'Unknown identity kind.',
    );
  }
}

final class IdentityRegistryEntry {
  const IdentityRegistryEntry(this.id);

  final OpaqueId id;

  AgentIdentityKind get kind => AgentIdentityKind.forId(id);

  String get key => id.value;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'kind': kind.prefix,
      };
}

final class IdentityRegistryCodec {
  const IdentityRegistryCodec({
    this.limits = const StoreLimits(),
  });

  final StoreLimits limits;

  RegistryChunkArtifact<IdentityRegistryEntry> encodeChunk(
    AgentIdentityKind kind,
    Iterable<IdentityRegistryEntry> entries,
  ) {
    final sorted = List<IdentityRegistryEntry>.of(entries)
      ..sort((left, right) => left.key.compareTo(right.key));
    _validateEntries(kind, sorted);
    final bytes = canonicalJsonBytes(<String, Object?>{
      'entries': <Object?>[for (final entry in sorted) entry.toJson()],
      'formatVersion': agentManifestFormatVersion,
      'registryKind': RegistryKind.identity.wireName,
      'shard': kind.prefix,
    });
    _validateLimits(sorted.length, bytes.length);
    return RegistryChunkArtifact<IdentityRegistryEntry>(
      bytes: bytes,
      reference: RegistryChunkReference(
        shard: kind.prefix,
        firstKey: sorted.first.key,
        lastKey: sorted.last.key,
        entryCount: sorted.length,
        byteLength: bytes.length,
        digest: storeHex(storeSha256(bytes)),
      ),
      entries: sorted,
    );
  }

  RegistryChunkArtifact<IdentityRegistryEntry> decodeChunk(
    Uint8List bytes, {
    AgentIdentityKind? expectedKind,
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
            RegistryKind.identity.wireName) {
      throw const StoreFormatException(
        StoreFormatErrorCode.unsupportedVersion,
        'Unsupported identity registry chunk.',
      );
    }
    final kind = AgentIdentityKind.parse(
      requireRegistryString(object, 'shard'),
    );
    if (expectedKind != null && kind != expectedKind) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Identity registry shard does not match its location.',
      );
    }
    final rawEntries = object['entries'];
    if (rawEntries is! List<Object?> || rawEntries.isEmpty) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Identity registry chunk must contain entries.',
      );
    }
    final entries = <IdentityRegistryEntry>[];
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map<String, Object?>) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Identity registry entry must be an object.',
        );
      }
      requireExactRegistryKeys(rawEntry, const <String>{'id', 'kind'});
      final entryKind = AgentIdentityKind.parse(
        requireRegistryString(rawEntry, 'kind'),
      );
      if (entryKind != kind) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Identity registry entry is in the wrong shard.',
        );
      }
      late final OpaqueId id;
      try {
        id = parseAgentOpaqueId(requireRegistryString(rawEntry, 'id'));
      } on FormatException {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Identity registry contains an invalid typed ID.',
        );
      }
      entries.add(IdentityRegistryEntry(id));
    }
    _validateEntries(kind, entries);
    _validateLimits(entries.length, bytes.length);
    return RegistryChunkArtifact<IdentityRegistryEntry>(
      bytes: bytes,
      reference: RegistryChunkReference(
        shard: kind.prefix,
        firstKey: entries.first.key,
        lastKey: entries.last.key,
        entryCount: entries.length,
        byteLength: bytes.length,
        digest: storeHex(storeSha256(bytes)),
      ),
      entries: entries,
    );
  }

  void _validateEntries(
    AgentIdentityKind kind,
    List<IdentityRegistryEntry> entries,
  ) {
    if (entries.isEmpty) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Identity registry chunk cannot be empty.',
      );
    }
    String? previous;
    for (final entry in entries) {
      if (entry.kind != kind ||
          (previous != null && previous.compareTo(entry.key) >= 0)) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Identity registry entries must be unique and strictly sorted.',
        );
      }
      previous = entry.key;
    }
  }

  void _validateLimits(int entryCount, int byteLength) {
    if (entryCount > limits.maximumRegistryEntries ||
        byteLength > limits.maximumRegistryBytes ||
        byteLength > StoreLimits.hardMaximumRegistryBytes) {
      throw const StoreFormatException(
        StoreFormatErrorCode.resourceLimit,
        'Identity registry exceeds configured limits.',
      );
    }
  }
}

OpaqueId parseAgentOpaqueId(String value) {
  if (value.startsWith('ses_')) return SessionId.parse(value);
  if (value.startsWith('run_')) return RunId.parse(value);
  if (value.startsWith('evt_')) return EventId.parse(value);
  if (value.startsWith('cmd_')) return CommandId.parse(value);
  if (value.startsWith('wrk_')) return WorkItemId.parse(value);
  if (value.startsWith('att_')) return AttemptId.parse(value);
  if (value.startsWith('apr_')) return ApprovalId.parse(value);
  if (value.startsWith('dop_')) return DeferredOperationId.parse(value);
  if (value.startsWith('res_')) return RuntimeResourceId.parse(value);
  if (value.startsWith('snp_')) return SnapshotId.parse(value);
  throw FormatException('Unknown opaque identifier kind.', value);
}
