import 'dart:io';
import 'dart:typed_data';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'command_registry.dart';
import 'file_store_coordinator_protocol.dart';
import 'file_store_durability.dart';
import 'file_store_options.dart';
import 'identity_registry.dart';
import 'journal_frame_codec.dart';
import 'registry_manifest.dart';
import 'root_session_registry.dart';
import 'store_digest.dart';
import 'store_corruption.dart';
import 'store_compaction.dart';
import 'store_format.dart';
import 'store_garbage_collector.dart';
import 'store_generation.dart';
import 'store_layout.dart';
import 'store_lock.dart';
import 'store_manifest.dart';
import 'store_recovery.dart';
import 'store_retention.dart';
import 'store_snapshot_codec.dart';
import 'store_writer.dart';

const _storeMetadata = <String, Object?>{
  'digest': 'sha-256',
  'formatIdentity': 'pigcode-agent-store',
  'formatVersion': agentStoreFormatVersion,
  'journalFrameVersion': agentJournalFrameVersion,
  'manifestFormatVersion': agentManifestFormatVersion,
  'snapshotFormatVersion': agentSnapshotFormatVersion,
};

void _requireRootAccessPolicy(
  Directory root,
  FileStoreRootAccessPolicy policy,
) {
  if (policy == FileStoreRootAccessPolicy.explicitTestOnly) return;
  if (Platform.isWindows) {
    throw const AgentStoreException(
      AgentStoreErrorCode.insecureRoot,
      'Private Store root permissions cannot be proven on this platform.',
    );
  }
  final ownerPermissions = FileStat.statSync(root.path).mode & 0x1ff;
  if (ownerPermissions != 0x1c0) {
    throw const AgentStoreException(
      AgentStoreErrorCode.insecureRoot,
      'Production Store root must have owner-only read/write/execute access.',
    );
  }
}

/// VM-only immutable-generation implementation of [AgentStore].
final class FileAgentStore implements AgentStore {
  FileAgentStore._({
    required this.layout,
    required FileStoreCoordinatorClient coordinator,
    required this.options,
  })  : _coordinator = coordinator,
        _writer = StoreWriter(faults: options.faults),
        _journalCodec = JournalFrameCodec(limits: options.limits),
        _manifestCodec = RegistryManifestCodec(limits: options.limits),
        _storeManifestCodec = const StoreManifestCodec(),
        _snapshotCodec = const StoreSnapshotCodec(),
        _garbageCollector = StoreGarbageCollector(
          faults: options.garbageCollectionFaults,
        ),
        _identityCodec = IdentityRegistryCodec(limits: options.limits),
        _commandCodec = CommandRegistryCodec(limits: options.limits),
        _catalogCodec = RootSessionCatalogCodec(limits: options.limits),
        _rootCommandCodec =
            RootSessionCommandRegistryCodec(limits: options.limits);

  final StoreLayout layout;
  final FileStoreOptions options;
  final FileStoreCoordinatorClient _coordinator;
  final StoreWriter _writer;
  final JournalFrameCodec _journalCodec;
  late final StoreRecovery _recovery = StoreRecovery(codec: _journalCodec);
  final RegistryManifestCodec _manifestCodec;
  final StoreManifestCodec _storeManifestCodec;
  final StoreSnapshotCodec _snapshotCodec;
  final StoreGarbageCollector _garbageCollector;
  final IdentityRegistryCodec _identityCodec;
  final CommandRegistryCodec _commandCodec;
  final RootSessionCatalogCodec _catalogCodec;
  final RootSessionCommandRegistryCodec _rootCommandCodec;

  static Future<FileAgentStore> open({
    required Directory root,
    required FileStoreCoordinatorClient coordinator,
    FileStoreOptions options = const FileStoreOptions(),
  }) async {
    final layout = StoreLayout.open(root);
    if (coordinator.canonicalRoot != layout.root.path) {
      throw const AgentStoreException(
        AgentStoreErrorCode.coordinationRequired,
        'Coordinator capability is bound to a different Store root.',
      );
    }
    _requireRootAccessPolicy(layout.root, options.rootAccessPolicy);
    final store = FileAgentStore._(
      layout: layout,
      coordinator: coordinator,
      options: options,
    );
    await store._coordinated<void>(() async {
      final metadata = canonicalJsonBytes(_storeMetadata);
      if (layout.storeMetadata.existsSync()) {
        store._validateStoreMetadata(
          Uint8List.fromList(await layout.storeMetadata.readAsBytes()),
        );
      } else {
        await store._writer.writeImmutable(
          layout.storeMetadata,
          metadata,
          durability: AgentStoreDurability.processCrashFlush,
        );
      }
    });
    return store;
  }

  @override
  Future<AgentStoreRoot> loadRoot() => _coordinated<AgentStoreRoot>(() async {
        final state = await _recoverRoot();
        return AgentStoreRoot(
          head: state.head,
          sessionIds: state.sessionIds,
        );
      });

  @override
  Future<AgentStoreAcceptedCommand?> lookupCreateSessionCommand(
    CommandId commandId,
  ) =>
      _coordinated<AgentStoreAcceptedCommand?>(() async {
        final state = await _recoverRoot();
        return state.commands[commandId];
      });

  @override
  Future<AgentStoreCreateSessionReceipt> createSession(
    AgentStoreCreateSessionTransaction transaction, {
    AgentStoreDurability requestedDurability =
        AgentStoreDurability.processCrashFlush,
  }) {
    final achieved = requireFileStoreDurability(
      requestedDurability,
      options,
    );
    return _coordinated<AgentStoreCreateSessionReceipt>(() async {
      final root = await _recoverRoot();
      final accepted = transaction.acceptedCommand;
      final previous = root.commands[accepted.commandId];
      if (previous != null) {
        _requireSameCommand(previous, accepted);
        return root.receipts[accepted.commandId]!;
      }
      _requireRootHead(root.head, transaction.expectedRootHead);
      if (root.sessionIds.contains(transaction.sessionId)) {
        throw const AgentStoreException(
          AgentStoreErrorCode.duplicateId,
          'SessionId was already allocated.',
        );
      }
      _validateCreateTransaction(transaction);

      final sessionGeneration = 1;
      final allocations =
          transaction.newIdAllocations.map((entry) => entry.id.value).toSet();
      _requireRegistryCapacity(allocations.length);
      final segment = await _writeSegment(
        transaction.sessionId,
        transaction.events,
        previousRecordDigest: Uint8List(32),
        metadata: _createMetadata(transaction),
        durability: achieved,
      );
      final sessionRoots = await _writeSessionRegistries(
        transaction.sessionId,
        generation: sessionGeneration,
        allocatedIds: allocations,
        commands: const <CommandId, AgentStoreAcceptedCommand>{},
        durability: achieved,
      );
      final sessionHead = AgentStoreHead.compose(
        sequence: transaction.events.last.sequence,
        journalHeadDigest: segment.finalRecordDigest,
        identityRegistryRootDigest: sessionRoots.identity.rootDigest,
        commandRegistryRootDigest: sessionRoots.command.rootDigest,
        generation: sessionGeneration,
        historyFloorSequence: 0,
      );
      final sessionState = _FileSessionState(
        sessionId: transaction.sessionId,
        head: sessionHead,
        segments: <_SegmentReference>[segment],
        allocatedIds: allocations,
        commands: <CommandId, AgentStoreAcceptedCommand>{},
        commandReceipts: <CommandId, AgentStoreAppendReceipt>{},
        compactionReceipts: <int, AgentStoreAppendReceipt>{},
        identityManifest: sessionRoots.identity,
        commandManifest: sessionRoots.command,
        retentionPolicy: StoreRetentionPolicy.retainAll,
        prefixCommitment: StorePrefixCommitment.empty,
      );
      await _writeSessionManifest(sessionState, durability: achieved);
      final verifiedSession = await _recoverSession(transaction.sessionId);
      if (verifiedSession.head != sessionHead) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Published Session generation did not reopen exactly.',
        );
      }

      final nextSessionIds = <SessionId>{
        ...root.sessionIds,
        transaction.sessionId,
      };
      final nextCommands = <CommandId, AgentStoreAcceptedCommand>{
        ...root.commands,
        accepted.commandId: accepted,
      };
      final rootGeneration = root.head.generation + 1;
      final rootRoots = await _writeRootRegistries(
        generation: rootGeneration,
        sessionIds: nextSessionIds,
        commands: nextCommands,
        commandSessions: <CommandId, SessionId>{
          for (final entry in root.receipts.entries)
            entry.key: entry.value.sessionId,
          accepted.commandId: transaction.sessionId,
        },
        durability: achieved,
      );
      final afterRootHead = AgentStoreRootHead.compose(
        sequence: root.head.sequence + 1,
        sessionCatalogRootDigest: rootRoots.catalog.rootDigest,
        createSessionCommandRegistryRootDigest: rootRoots.command.rootDigest,
        generation: rootGeneration,
      );
      final receipt = AgentStoreCreateSessionReceipt(
        beforeRootHead: root.head,
        afterRootHead: afterRootHead,
        sessionId: transaction.sessionId,
        sessionHead: sessionHead,
        eventIds: transaction.events.map((event) => event.eventId).toList(),
        requestedDurability: requestedDurability,
        achievedDurability: achieved,
      );
      final nextRoot = _FileRootState(
        head: afterRootHead,
        sessionIds: nextSessionIds,
        commands: nextCommands,
        receipts: <CommandId, AgentStoreCreateSessionReceipt>{
          ...root.receipts,
          accepted.commandId: receipt,
        },
        catalogManifest: rootRoots.catalog,
        commandManifest: rootRoots.command,
      );
      await _writeRootManifest(nextRoot, durability: achieved);
      final verifiedRoot = await _recoverRoot();
      if (verifiedRoot.head != afterRootHead) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Published root generation did not reopen exactly.',
        );
      }
      await options.commitFaults.check(StoreCommitPoint.createSession);
      return receipt;
    });
  }

  @override
  Future<AgentStoreSession> loadSession(SessionId sessionId) =>
      _coordinated<AgentStoreSession>(() async {
        final session = await _recoverVisibleSession(sessionId);
        return AgentStoreSession(
          sessionId: sessionId,
          head: session.head,
          snapshot: session.snapshot,
        );
      });

  @override
  Future<AgentStoreAcceptedCommand?> lookupAcceptedCommand(
    SessionId sessionId,
    CommandId commandId,
  ) =>
      _coordinated<AgentStoreAcceptedCommand?>(() async {
        final session = await _recoverVisibleSession(sessionId);
        return session.commands[commandId];
      });

  @override
  Future<AgentStoreEventPage> readEvents(
    SessionId sessionId, {
    AgentStoreCursor after = const AgentStoreCursor(0),
    int limit = 256,
  }) =>
      _coordinated<AgentStoreEventPage>(() async {
        final session = await _recoverVisibleSession(sessionId);
        if (limit <= 0) {
          throw const AgentStoreException(
            AgentStoreErrorCode.invalidTransaction,
            'Event page limit must be positive.',
          );
        }
        if (limit > options.limits.maximumReplayPageEvents) {
          throw const AgentStoreException(
            AgentStoreErrorCode.resourceLimit,
            'Event page limit exceeds the configured maximum.',
          );
        }
        if (after.sequence < session.head.historyFloorSequence) {
          throw const AgentStoreException(
            AgentStoreErrorCode.cursorCompacted,
            'Event cursor is below the retained history floor.',
          );
        }
        final events = session.events
            .where((event) => event.sequence > after.sequence)
            .take(limit)
            .toList();
        return AgentStoreEventPage(
          events: events,
          nextCursor: AgentStoreCursor(
            events.isEmpty ? after.sequence : events.last.sequence,
          ),
          head: session.head,
        );
      });

  @override
  Future<AgentStoreAppendReceipt> append(
    AgentStoreTransaction transaction, {
    AgentStoreDurability requestedDurability =
        AgentStoreDurability.processCrashFlush,
  }) {
    final achieved = requireFileStoreDurability(
      requestedDurability,
      options,
    );
    return _coordinated<AgentStoreAppendReceipt>(() async {
      final session = await _recoverVisibleSession(transaction.sessionId);
      final accepted = transaction.acceptedCommand;
      if (accepted != null) {
        final previous = session.commands[accepted.commandId];
        if (previous != null) {
          _requireSameCommand(previous, accepted);
          return session.commandReceipts[accepted.commandId]!;
        }
      }
      _requireHead(session.head, transaction.expectedHead);
      _validateAppendTransaction(session, transaction);

      final allocations = <String>{
        ...session.allocatedIds,
        ...transaction.newIdAllocations.map((entry) => entry.id.value),
      };
      _requireRegistryCapacity(allocations.length);
      if (session.segments.length >= options.limits.maximumSegmentCount) {
        throw const AgentStoreException(
          AgentStoreErrorCode.resourceLimit,
          'Journal segment count limit would be exceeded.',
        );
      }
      final segment = await _writeSegment(
        transaction.sessionId,
        transaction.events,
        previousRecordDigest:
            storeDigestFromHex(session.head.journalHeadDigest),
        metadata: _appendMetadata(transaction),
        durability: achieved,
      );
      final commands = <CommandId, AgentStoreAcceptedCommand>{
        ...session.commands,
        if (accepted != null) accepted.commandId: accepted,
      };
      final generation = session.head.generation + 1;
      final roots = await _writeSessionRegistries(
        transaction.sessionId,
        generation: generation,
        allocatedIds: allocations,
        commands: commands,
        durability: achieved,
      );
      final afterHead = AgentStoreHead.compose(
        sequence: transaction.events.last.sequence,
        journalHeadDigest: segment.finalRecordDigest,
        identityRegistryRootDigest: roots.identity.rootDigest,
        commandRegistryRootDigest: roots.command.rootDigest,
        generation: generation,
        historyFloorSequence: session.head.historyFloorSequence,
      );
      final receipt = AgentStoreAppendReceipt(
        beforeHead: session.head,
        afterHead: afterHead,
        eventIds: transaction.events.map((event) => event.eventId).toList(),
        requestedDurability: requestedDurability,
        achievedDurability: achieved,
      );
      await _writeSessionManifest(
        session.copyWith(
          head: afterHead,
          segments: <_SegmentReference>[...session.segments, segment],
          allocatedIds: allocations,
          commands: commands,
          commandReceipts: <CommandId, AgentStoreAppendReceipt>{
            ...session.commandReceipts,
            if (accepted != null) accepted.commandId: receipt,
          },
          identityManifest: roots.identity,
          commandManifest: roots.command,
        ),
        durability: achieved,
      );
      final verified = await _recoverSession(transaction.sessionId);
      if (verified.head != afterHead) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Published append generation did not reopen exactly.',
        );
      }
      await options.commitFaults.check(StoreCommitPoint.append);
      return receipt;
    });
  }

  @override
  Future<AgentStoreAppendReceipt> writeSnapshot(
    AgentStoreSnapshot snapshot, {
    required AgentStoreHead expectedHead,
    AgentStoreDurability requestedDurability =
        AgentStoreDurability.processCrashFlush,
  }) {
    final achieved = requireFileStoreDurability(
      requestedDurability,
      options,
    );
    return _coordinated<AgentStoreAppendReceipt>(() async {
      final session = await _recoverVisibleSession(snapshot.sessionId);
      _requireHead(session.head, expectedHead);
      if (session.allocatedIds.contains(snapshot.snapshotId.value)) {
        throw const AgentStoreException(
          AgentStoreErrorCode.duplicateId,
          'SnapshotId was already allocated.',
        );
      }
      _validateSnapshot(snapshot, session.head);
      final allocations = <String>{
        ...session.allocatedIds,
        snapshot.snapshotId.value,
      };
      _requireRegistryCapacity(allocations.length);
      final snapshotBytes = _snapshotCodec.encode(snapshot);
      if (snapshotBytes.length > options.limits.maximumSnapshotBytes) {
        throw const AgentStoreException(
          AgentStoreErrorCode.resourceLimit,
          'Snapshot exceeds the configured byte limit.',
        );
      }
      final snapshotDigest = storeHex(storeSha256(snapshotBytes));
      await _writer.writeImmutable(
        layout.snapshotFile(
          snapshot.sessionId,
          snapshotId: snapshot.snapshotId,
          digest: snapshotDigest,
        ),
        snapshotBytes,
        durability: achieved,
      );
      final generation = session.head.generation + 1;
      final roots = await _writeSessionRegistries(
        snapshot.sessionId,
        generation: generation,
        allocatedIds: allocations,
        commands: session.commands,
        durability: achieved,
      );
      final afterHead = AgentStoreHead.compose(
        sequence: session.head.sequence,
        journalHeadDigest: session.head.journalHeadDigest,
        identityRegistryRootDigest: roots.identity.rootDigest,
        commandRegistryRootDigest: roots.command.rootDigest,
        generation: generation,
        historyFloorSequence: session.head.historyFloorSequence,
      );
      final receipt = AgentStoreAppendReceipt(
        beforeHead: session.head,
        afterHead: afterHead,
        eventIds: const <EventId>[],
        requestedDurability: requestedDurability,
        achievedDurability: achieved,
      );
      await _writeSessionManifest(
        session.copyWith(
          head: afterHead,
          allocatedIds: allocations,
          snapshot: snapshot,
          snapshotDigest: snapshotDigest,
          identityManifest: roots.identity,
          commandManifest: roots.command,
        ),
        durability: achieved,
      );
      final verified = await _recoverSession(snapshot.sessionId);
      if (verified.head != afterHead ||
          verified.snapshot?.snapshotId != snapshot.snapshotId) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Published snapshot generation did not reopen exactly.',
        );
      }
      await options.commitFaults.check(StoreCommitPoint.snapshot);
      return receipt;
    });
  }

  @override
  Future<AgentStoreAppendReceipt> compact(
    SessionId sessionId, {
    required AgentStoreHead expectedHead,
    required int throughSequence,
    AgentStoreDurability requestedDurability =
        AgentStoreDurability.processCrashFlush,
  }) {
    final achieved = requireFileStoreDurability(
      requestedDurability,
      options,
    );
    return _coordinated<AgentStoreAppendReceipt>(() async {
      final session = await _recoverVisibleSession(sessionId);
      final previous = session.compactionReceipts[throughSequence];
      if (previous != null) return previous;
      _requireHead(session.head, expectedHead);
      final snapshot = session.snapshot;
      final policy =
          session.retentionPolicy == StoreRetentionPolicy.pruneThroughSnapshot
              ? session.retentionPolicy
              : options.retentionPolicy;
      if (throughSequence < session.head.historyFloorSequence ||
          throughSequence > session.head.sequence ||
          snapshot == null ||
          snapshot.sequence < throughSequence) {
        throw const AgentStoreException(
          AgentStoreErrorCode.invalidTransaction,
          'Compaction requires a covering snapshot and valid floor.',
        );
      }
      if (policy == StoreRetentionPolicy.pruneThroughSnapshot &&
          !snapshotProjectionIsSafeToPrune(
            snapshot.canonicalProjection,
          )) {
        throw const AgentStoreException(
          AgentStoreErrorCode.invalidTransaction,
          'Snapshot projection contains pending or unknown recovery state.',
        );
      }
      var prefixCommitment = session.prefixCommitment;
      var retainedSegments = List<_SegmentReference>.of(session.segments);
      if (policy == StoreRetentionPolicy.pruneThroughSnapshot) {
        var removeCount = 0;
        for (final segment in retainedSegments) {
          final end = segment.startSequence + segment.recordCount - 1;
          if (segment.startSequence <= throughSequence &&
              end > throughSequence) {
            throw const AgentStoreException(
              AgentStoreErrorCode.invalidTransaction,
              'Compaction floor must align with an atomic batch boundary.',
            );
          }
          if (end > throughSequence) break;
          final finalDigest = session.journalDigests[end];
          if (finalDigest == null) {
            throw const AgentStoreException(
              AgentStoreErrorCode.corruption,
              'Journal is missing a compaction prefix digest.',
            );
          }
          prefixCommitment = StorePrefixCommitment(
            throughSequence: end,
            finalRecordDigest: finalDigest,
          );
          removeCount++;
        }
        retainedSegments = retainedSegments.sublist(removeCount);
      }
      final generation = session.head.generation + 1;
      final roots = await _writeSessionRegistries(
        sessionId,
        generation: generation,
        allocatedIds: session.allocatedIds,
        commands: session.commands,
        durability: achieved,
      );
      final afterHead = AgentStoreHead.compose(
        sequence: session.head.sequence,
        journalHeadDigest: session.head.journalHeadDigest,
        identityRegistryRootDigest: roots.identity.rootDigest,
        commandRegistryRootDigest: roots.command.rootDigest,
        generation: generation,
        historyFloorSequence:
            policy == StoreRetentionPolicy.pruneThroughSnapshot
                ? throughSequence
                : session.head.historyFloorSequence,
      );
      final receipt = AgentStoreAppendReceipt(
        beforeHead: session.head,
        afterHead: afterHead,
        eventIds: const <EventId>[],
        requestedDurability: requestedDurability,
        achievedDurability: achieved,
      );
      await _writeSessionManifest(
        session.copyWith(
          head: afterHead,
          segments: retainedSegments,
          compactionReceipts: <int, AgentStoreAppendReceipt>{
            ...session.compactionReceipts,
            throughSequence: receipt,
          },
          identityManifest: roots.identity,
          commandManifest: roots.command,
          retentionPolicy: policy,
          prefixCommitment: prefixCommitment,
        ),
        durability: achieved,
      );
      final verified = await _recoverSession(sessionId);
      if (verified.head != afterHead) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Published compaction generation did not reopen exactly.',
        );
      }
      await options.commitFaults.check(StoreCommitPoint.compaction);
      return receipt;
    });
  }

  Future<StoreGarbageCollectionReport> garbageCollect(
    SessionId sessionId,
  ) =>
      _coordinated<StoreGarbageCollectionReport>(() async {
        await _recoverVisibleSession(sessionId);
        final protected = <String>{};
        final valid = <({
          StoreGenerationFile file,
          Map<String, Object?> object,
        })>[];
        for (final generation
            in _generationFiles(layout.manifests(sessionId)).reversed) {
          try {
            valid.add((
              file: generation,
              object: _decodeManifestFile(generation),
            ));
          } on StoreFormatException {
            continue;
          }
          if (valid.length == 2) break;
        }
        if (valid.isEmpty) {
          throw const AgentStoreException(
            AgentStoreErrorCode.corruption,
            'Session has no valid generation for garbage collection.',
          );
        }
        for (final selected in valid) {
          protected.add(selected.file.file.absolute.path);
          for (final raw in _requiredList(selected.object, 'segments')) {
            final segment = _SegmentReference.fromJson(
              _asObject(raw, 'Segment reference'),
            );
            protected.add(layout
                .journalSegmentFile(
                  sessionId,
                  startSequence: segment.startSequence,
                  digest: segment.artifactDigest,
                )
                .absolute
                .path);
          }
          final snapshot = selected.object['snapshot'];
          if (snapshot != null) {
            final reference = _asObject(snapshot, 'Snapshot reference');
            final snapshotId =
                SnapshotId.parse(_requiredString(reference, 'snapshotId'));
            final digest = _requiredDigest(reference, 'digest');
            final file = layout.snapshotFile(
              sessionId,
              snapshotId: snapshotId,
              digest: digest,
            );
            protected.add(file.absolute.path);
            if (file.existsSync()) {
              final decoded = _snapshotCodec.decode(
                Uint8List.fromList(await file.readAsBytes()),
              );
              await _protectRegistryRoot(
                sessionId,
                kind: RegistryKind.identity,
                rootDigest: decoded.identityRegistryRootDigest,
                protectedPaths: protected,
              );
              await _protectRegistryRoot(
                sessionId,
                kind: RegistryKind.command,
                rootDigest: decoded.commandRegistryRootDigest,
                protectedPaths: protected,
              );
            }
          }
          await _protectRegistryReference(
            sessionId,
            RegistryKind.identity,
            _requiredObject(selected.object, 'identityManifest'),
            protected,
          );
          await _protectRegistryReference(
            sessionId,
            RegistryKind.command,
            _requiredObject(selected.object, 'commandManifest'),
            protected,
          );
        }
        return _garbageCollector.collect(
          retiredDirectory: layout.retired(sessionId),
          artifactDirectories: <String, Directory>{
            'session-manifest': layout.manifests(sessionId),
            'identity-manifest': layout.identityManifests(sessionId),
            'command-manifest': layout.commandManifests(sessionId),
            'identity-chunk': layout.identityChunks(sessionId),
            'command-chunk': layout.commandChunks(sessionId),
            'segment': layout.segments(sessionId),
            'snapshot': layout.snapshots(sessionId),
          },
          protectedCanonicalPaths: protected,
        );
      });

  Future<T> _coordinated<T>(Future<T> Function() action) async {
    try {
      return await _coordinator.synchronized<T>(() async {
        final lock = await StoreLock.acquire(
          layout.storeLock,
          timeout: options.lockTimeout,
        );
        try {
          layout.validateExistingTree();
          if (layout.storeMetadata.existsSync()) {
            _validateStoreMetadata(
              Uint8List.fromList(
                await layout.storeMetadata.readAsBytes(),
              ),
            );
          }
          return await action();
        } finally {
          await lock.release();
        }
      }, timeout: options.coordinatorTimeout);
    } on AgentStoreException {
      rethrow;
    } on StoreFormatException catch (error) {
      if (error.code == StoreFormatErrorCode.resourceLimit) {
        throw const AgentStoreException(
          AgentStoreErrorCode.resourceLimit,
          'Store format resource limit was exceeded.',
        );
      }
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Store format validation failed.',
      );
    } on StoreLayoutException {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Store layout validation failed.',
      );
    } on StoreCorruptionException {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Store journal recovery failed.',
      );
    } on FileSystemException {
      throw const AgentStoreException(
        AgentStoreErrorCode.ioFailure,
        'Store filesystem operation failed.',
      );
    } on FormatException {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Store contains an invalid typed value.',
      );
    }
  }

  void _validateStoreMetadata(Uint8List bytes) {
    final expected = canonicalJsonBytes(_storeMetadata);
    if (!storeBytesEqual(bytes, expected)) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Store metadata does not match the Phase 3 format identity.',
      );
    }
  }

  Future<_FileRootState> _recoverRoot() async {
    if (!layout.rootManifests.existsSync()) return _FileRootState.empty();
    final rootManifestFiles = _generationFiles(layout.rootManifests);
    if (rootManifestFiles.isEmpty) return _FileRootState.empty();
    final selected = _latestDecodableManifest(
      layout.rootManifests,
      candidateFiles: rootManifestFiles,
    );
    if (selected == null) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Root has published manifests but none are valid.',
      );
    }
    final file = selected.file;
    final object = selected.object;
    _requireExactKeys(object, const <String>{
      'catalogManifest',
      'commandManifest',
      'createReceipts',
      'formatVersion',
      'generation',
      'head',
    });
    _requireManifestVersion(object);
    final generation = _requiredInt(object, 'generation');
    if (generation != file.generation) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Root manifest generation does not match its filename.',
      );
    }
    final head = _decodeRootHead(_requiredObject(object, 'head'));
    if (head.generation != generation) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Root head generation does not match its manifest.',
      );
    }
    final catalogManifest = await _readRegistryManifestReference(
      _requiredObject(object, 'catalogManifest'),
      RegistryKind.sessionCatalog,
    );
    final commandManifest = await _readRegistryManifestReference(
      _requiredObject(object, 'commandManifest'),
      RegistryKind.createSessionCommand,
    );
    if (head.sessionCatalogRootDigest != catalogManifest.rootDigest ||
        head.createSessionCommandRegistryRootDigest !=
            commandManifest.rootDigest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Root head does not bind the registry roots.',
      );
    }
    final sessionIds = await _readSessionCatalog(catalogManifest);
    final rootCommands = await _readRootCommands(commandManifest);
    final commands = rootCommands.commands;
    final receipts = <CommandId, AgentStoreCreateSessionReceipt>{};
    for (final raw in _requiredList(object, 'createReceipts')) {
      final entry = _asObject(raw, 'Root create receipt entry');
      _requireExactKeys(
        entry,
        const <String>{'commandId', 'receipt'},
      );
      final commandId = CommandId.parse(_requiredString(entry, 'commandId'));
      if (receipts.containsKey(commandId)) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Root manifest contains duplicate command receipts.',
        );
      }
      receipts[commandId] = _decodeCreateReceipt(
        _requiredObject(entry, 'receipt'),
      );
    }
    if (commands.keys.toSet().difference(receipts.keys.toSet()).isNotEmpty ||
        receipts.keys.toSet().difference(commands.keys.toSet()).isNotEmpty) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Root command registry and receipts are not exact.',
      );
    }
    for (final entry in receipts.entries) {
      if (rootCommands.sessions[entry.key] != entry.value.sessionId) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Root command Session binding does not match its receipt.',
        );
      }
    }
    return _FileRootState(
      head: head,
      sessionIds: sessionIds,
      commands: commands,
      receipts: receipts,
      catalogManifest: catalogManifest,
      commandManifest: commandManifest,
    );
  }

  Future<_FileSessionState> _recoverVisibleSession(
    SessionId sessionId,
  ) async {
    final root = await _recoverRoot();
    if (!root.sessionIds.contains(sessionId)) {
      throw const AgentStoreException(
        AgentStoreErrorCode.sessionNotFound,
        'Session does not exist.',
      );
    }
    return _recoverSession(sessionId);
  }

  Future<_FileSessionState> _recoverSession(SessionId sessionId) async {
    final directory = layout.manifests(sessionId);
    final selected = _latestDecodableManifest(directory);
    if (selected == null) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Registered Session has no valid manifest.',
      );
    }
    final file = selected.file;
    final object = selected.object;
    _requireExactKeys(object, const <String>{
      'commandManifest',
      'commandReceipts',
      'compactionReceipts',
      'formatVersion',
      'generation',
      'head',
      'identityManifest',
      'segments',
      'sessionId',
      'snapshot',
      'retention',
    });
    _requireManifestVersion(object);
    if (_requiredString(object, 'sessionId') != sessionId.value ||
        _requiredInt(object, 'generation') != file.generation) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Session manifest identity does not match its location.',
      );
    }
    final head = _decodeHead(_requiredObject(object, 'head'));
    if (head.generation != file.generation) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Session head generation does not match its manifest.',
      );
    }
    final retention = _requiredObject(object, 'retention');
    _requireExactKeys(
      retention,
      const <String>{'policy', 'prefixCommitment'},
    );
    late final StoreRetentionPolicy retentionPolicy;
    try {
      retentionPolicy = StoreRetentionPolicy.values.byName(
        _requiredString(retention, 'policy'),
      );
    } on ArgumentError {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Session manifest has an unknown retention policy.',
      );
    }
    final prefixCommitment = StorePrefixCommitment.fromJson(
      _requiredObject(retention, 'prefixCommitment'),
    );
    if ((retentionPolicy == StoreRetentionPolicy.retainAll &&
            (head.historyFloorSequence != 0 ||
                prefixCommitment.throughSequence != 0)) ||
        (retentionPolicy == StoreRetentionPolicy.pruneThroughSnapshot &&
            (head.historyFloorSequence != prefixCommitment.throughSequence ||
                head.historyFloorSequence > head.sequence))) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Session retention state is inconsistent with its head.',
      );
    }
    final identityManifest = await _readRegistryManifestReference(
      _requiredObject(object, 'identityManifest'),
      RegistryKind.identity,
      sessionId: sessionId,
    );
    final commandManifest = await _readRegistryManifestReference(
      _requiredObject(object, 'commandManifest'),
      RegistryKind.command,
      sessionId: sessionId,
    );
    if (head.identityRegistryRootDigest != identityManifest.rootDigest ||
        head.commandRegistryRootDigest != commandManifest.rootDigest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Session head does not bind the registry roots.',
      );
    }
    final allocatedIds = await _readIdentities(
      sessionId,
      identityManifest,
    );
    final commands = await _readCommands(sessionId, commandManifest);
    final commandReceipts = <CommandId, AgentStoreAppendReceipt>{};
    for (final raw in _requiredList(object, 'commandReceipts')) {
      final entry = _asObject(raw, 'Command receipt entry');
      _requireExactKeys(
        entry,
        const <String>{'commandId', 'receipt'},
      );
      final commandId = CommandId.parse(_requiredString(entry, 'commandId'));
      if (commandReceipts.containsKey(commandId)) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Session manifest contains duplicate command receipts.',
        );
      }
      commandReceipts[commandId] = _decodeAppendReceipt(
        _requiredObject(entry, 'receipt'),
      );
    }
    if (commands.keys
            .toSet()
            .difference(commandReceipts.keys.toSet())
            .isNotEmpty ||
        commandReceipts.keys
            .toSet()
            .difference(commands.keys.toSet())
            .isNotEmpty) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Session command registry and receipts are not exact.',
      );
    }
    final compactionReceipts = <int, AgentStoreAppendReceipt>{};
    for (final raw in _requiredList(object, 'compactionReceipts')) {
      final entry = _asObject(raw, 'Compaction receipt entry');
      _requireExactKeys(
        entry,
        const <String>{'receipt', 'throughSequence'},
      );
      final throughSequence = _requiredInt(entry, 'throughSequence');
      if (compactionReceipts.containsKey(throughSequence)) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Session manifest contains duplicate compaction receipts.',
        );
      }
      compactionReceipts[throughSequence] = _decodeAppendReceipt(
        _requiredObject(entry, 'receipt'),
      );
    }
    final segments = <_SegmentReference>[];
    final events = <AgentEvent>[];
    final journalDigests = <int, String>{
      if (prefixCommitment.throughSequence > 0)
        prefixCommitment.throughSequence: prefixCommitment.finalRecordDigest,
    };
    final rawSegments = _requiredList(object, 'segments');
    if (rawSegments.length > options.limits.maximumSegmentCount) {
      throw const AgentStoreException(
        AgentStoreErrorCode.resourceLimit,
        'Journal segment count exceeds the configured limit.',
      );
    }
    var recoveryBytes = 0;
    for (final raw in rawSegments) {
      final reference = _SegmentReference.fromJson(
        _asObject(raw, 'Segment reference'),
      );
      final segmentFile = layout.journalSegmentFile(
        sessionId,
        startSequence: reference.startSequence,
        digest: reference.artifactDigest,
      );
      layout.validateExistingArtifact(segmentFile);
      recoveryBytes += segmentFile.lengthSync();
      if (recoveryBytes > options.limits.maximumRecoveryBytes) {
        throw const AgentStoreException(
          AgentStoreErrorCode.resourceLimit,
          'Journal recovery byte budget was exceeded.',
        );
      }
      final previousDigest = segments.isEmpty
          ? prefixCommitment.finalRecordDigest
          : segments.last.finalRecordDigest;
      final decoded = await _recovery.recoverSealedSegmentFile(
        file: segmentFile,
        sessionId: sessionId,
        expectedStartSequence: segments.isEmpty
            ? prefixCommitment.throughSequence + 1
            : segments.last.startSequence + segments.last.recordCount,
        previousFinalRecordDigest: storeDigestFromHex(previousDigest),
        expectedArtifactDigest: reference.artifactDigest,
      );
      if (decoded.sessionId != sessionId ||
          decoded.startSequence != reference.startSequence ||
          decoded.recordCount != reference.recordCount ||
          storeHex(decoded.finalRecordDigest) != reference.finalRecordDigest) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Journal segment does not match its manifest reference.',
        );
      }
      for (final batch in decoded.batches) {
        for (var eventIndex = 0;
            eventIndex < batch.events.length;
            eventIndex++) {
          journalDigests[batch.events[eventIndex].sequence] =
              storeHex(batch.recordDigests[eventIndex]);
        }
      }
      segments.add(reference);
      events.addAll(decoded.events);
    }
    final recoveredJournalHead = segments.isEmpty
        ? prefixCommitment.finalRecordDigest
        : segments.last.finalRecordDigest;
    if ((events.isNotEmpty && events.last.sequence != head.sequence) ||
        (events.isEmpty && prefixCommitment.throughSequence != head.sequence) ||
        recoveredJournalHead != head.journalHeadDigest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Session journal does not match its head.',
      );
    }
    AgentStoreSnapshot? snapshot;
    String? snapshotDigest;
    final rawSnapshot = object['snapshot'];
    if (rawSnapshot != null) {
      final reference = _asObject(rawSnapshot, 'Snapshot reference');
      _requireExactKeys(
        reference,
        const <String>{'digest', 'snapshotId'},
      );
      final snapshotId =
          SnapshotId.parse(_requiredString(reference, 'snapshotId'));
      snapshotDigest = _requiredDigest(reference, 'digest');
      final snapshotFile = layout.snapshotFile(
        sessionId,
        snapshotId: snapshotId,
        digest: snapshotDigest,
      );
      layout.validateExistingArtifact(snapshotFile);
      final snapshotLength = snapshotFile.lengthSync();
      recoveryBytes += snapshotLength;
      if (snapshotLength > options.limits.maximumSnapshotBytes ||
          recoveryBytes > options.limits.maximumRecoveryBytes) {
        throw const AgentStoreException(
          AgentStoreErrorCode.resourceLimit,
          'Snapshot or recovery byte budget was exceeded.',
        );
      }
      final bytes = Uint8List.fromList(await snapshotFile.readAsBytes());
      if (storeHex(storeSha256(bytes)) != snapshotDigest) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Snapshot artifact digest does not match.',
        );
      }
      snapshot = _snapshotCodec.decode(bytes);
      if (snapshot.sessionId != sessionId ||
          snapshot.snapshotId != snapshotId ||
          !allocatedIds.contains(snapshotId.value) ||
          snapshot.sequence > head.sequence ||
          snapshot.historyFloorSequence > head.historyFloorSequence ||
          journalDigests[snapshot.sequence] != snapshot.journalHeadDigest ||
          !await _registryRootExists(
            sessionId,
            kind: RegistryKind.identity,
            throughGeneration: head.generation,
            rootDigest: snapshot.identityRegistryRootDigest,
          ) ||
          !await _registryRootExists(
            sessionId,
            kind: RegistryKind.command,
            throughGeneration: head.generation,
            rootDigest: snapshot.commandRegistryRootDigest,
          )) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Snapshot binding does not match retained journal and registries.',
        );
      }
    }
    return _FileSessionState(
      sessionId: sessionId,
      head: head,
      segments: segments,
      events: events,
      allocatedIds: allocatedIds,
      commands: commands,
      commandReceipts: commandReceipts,
      compactionReceipts: compactionReceipts,
      identityManifest: identityManifest,
      commandManifest: commandManifest,
      snapshot: snapshot,
      snapshotDigest: snapshotDigest,
      retentionPolicy: retentionPolicy,
      prefixCommitment: prefixCommitment,
      journalDigests: journalDigests,
    );
  }

  Future<_SegmentReference> _writeSegment(
    SessionId sessionId,
    List<AgentEvent> events, {
    required Uint8List previousRecordDigest,
    required Map<String, Object?> metadata,
    required AgentStoreDurability durability,
  }) async {
    final bytes = _journalCodec.encodeSegment(
      sessionId: sessionId,
      startSequence: events.first.sequence,
      previousSegmentFinalDigest: previousRecordDigest,
      batches: <JournalBatch>[
        JournalBatch(
          transactionMetadata: metadata,
          events: events,
        ),
      ],
      seal: true,
    );
    final decoded = _journalCodec.decodeSegment(
      bytes,
      requireSealed: true,
      expectedPreviousSegmentFinalDigest: previousRecordDigest,
    );
    final artifactDigest = storeHex(storeSha256(bytes));
    final reference = _SegmentReference(
      startSequence: events.first.sequence,
      recordCount: events.length,
      artifactDigest: artifactDigest,
      finalRecordDigest: storeHex(decoded.finalRecordDigest),
    );
    await _writer.writeImmutable(
      layout.journalSegmentFile(
        sessionId,
        startSequence: reference.startSequence,
        digest: artifactDigest,
      ),
      bytes,
      durability: durability,
    );
    return reference;
  }

  Future<_SessionRegistryRoots> _writeSessionRegistries(
    SessionId sessionId, {
    required int generation,
    required Set<String> allocatedIds,
    required Map<CommandId, AgentStoreAcceptedCommand> commands,
    required AgentStoreDurability durability,
  }) async {
    final identityGroups = <AgentIdentityKind, List<IdentityRegistryEntry>>{};
    for (final value in allocatedIds) {
      final entry = IdentityRegistryEntry(parseAgentOpaqueId(value));
      identityGroups
          .putIfAbsent(entry.kind, () => <IdentityRegistryEntry>[])
          .add(entry);
    }
    final identityReferences = <RegistryChunkReference>[];
    for (final kind in AgentIdentityKind.values) {
      final entries = identityGroups[kind];
      if (entries == null) continue;
      final chunk = _identityCodec.encodeChunk(kind, entries);
      await _writer.writeImmutable(
        layout.identityChunkFile(sessionId, chunk.reference.digest),
        chunk.bytes,
        durability: durability,
      );
      identityReferences.add(chunk.reference);
    }
    final identityManifest = await _writeRegistryManifest(
      kind: RegistryKind.identity,
      generation: generation,
      chunks: identityReferences,
      sessionId: sessionId,
      durability: durability,
    );

    final commandGroups = <String, List<AgentStoreAcceptedCommand>>{};
    for (final command in commands.values) {
      commandGroups
          .putIfAbsent(
            commandRegistryShard(command.commandId),
            () => <AgentStoreAcceptedCommand>[],
          )
          .add(command);
    }
    final commandReferences = <RegistryChunkReference>[];
    final shards = commandGroups.keys.toList()..sort();
    for (final shard in shards) {
      final chunk = _commandCodec.encodeChunk(commandGroups[shard]!);
      await _writer.writeImmutable(
        layout.commandChunkFile(sessionId, chunk.reference.digest),
        chunk.bytes,
        durability: durability,
      );
      commandReferences.add(chunk.reference);
    }
    final commandManifest = await _writeRegistryManifest(
      kind: RegistryKind.command,
      generation: generation,
      chunks: commandReferences,
      sessionId: sessionId,
      durability: durability,
    );
    return _SessionRegistryRoots(
      identity: identityManifest,
      command: commandManifest,
    );
  }

  Future<_RootRegistryRoots> _writeRootRegistries({
    required int generation,
    required Set<SessionId> sessionIds,
    required Map<CommandId, AgentStoreAcceptedCommand> commands,
    required Map<CommandId, SessionId> commandSessions,
    required AgentStoreDurability durability,
  }) async {
    final sessionGroups = <String, List<SessionId>>{};
    for (final sessionId in sessionIds) {
      sessionGroups
          .putIfAbsent(
            sessionRegistryShard(sessionId),
            () => <SessionId>[],
          )
          .add(sessionId);
    }
    final catalogReferences = <RegistryChunkReference>[];
    final sessionShards = sessionGroups.keys.toList()..sort();
    for (final shard in sessionShards) {
      final chunk = _catalogCodec.encodeChunk(sessionGroups[shard]!);
      await _writer.writeImmutable(
        layout.sessionCatalogChunkFile(chunk.reference.digest),
        chunk.bytes,
        durability: durability,
      );
      catalogReferences.add(chunk.reference);
    }
    final catalogManifest = await _writeRegistryManifest(
      kind: RegistryKind.sessionCatalog,
      generation: generation,
      chunks: catalogReferences,
      durability: durability,
    );

    final commandGroups = <String, List<RootSessionCommandEntry>>{};
    for (final command in commands.values) {
      final sessionId = commandSessions[command.commandId];
      if (sessionId == null) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Root command is missing its allocated Session binding.',
        );
      }
      final entry = RootSessionCommandEntry(
        commandId: command.commandId,
        contentDigest: command.contentDigest,
        sessionId: sessionId,
        receipt: command.receipt,
      );
      commandGroups
          .putIfAbsent(
            commandRootRegistryShard(command.commandId),
            () => <RootSessionCommandEntry>[],
          )
          .add(entry);
    }
    final commandReferences = <RegistryChunkReference>[];
    final commandShards = commandGroups.keys.toList()..sort();
    for (final shard in commandShards) {
      final chunk = _rootCommandCodec.encodeChunk(commandGroups[shard]!);
      await _writer.writeImmutable(
        layout.createSessionCommandChunkFile(chunk.reference.digest),
        chunk.bytes,
        durability: durability,
      );
      commandReferences.add(chunk.reference);
    }
    final commandManifest = await _writeRegistryManifest(
      kind: RegistryKind.createSessionCommand,
      generation: generation,
      chunks: commandReferences,
      durability: durability,
    );
    return _RootRegistryRoots(
      catalog: catalogManifest,
      command: commandManifest,
    );
  }

  Future<RegistryManifest> _writeRegistryManifest({
    required RegistryKind kind,
    required int generation,
    required List<RegistryChunkReference> chunks,
    required AgentStoreDurability durability,
    SessionId? sessionId,
  }) async {
    final bytes = _manifestCodec.encode(
      kind: kind,
      generation: generation,
      chunks: chunks,
    );
    final manifest = _manifestCodec.decode(bytes, expectedKind: kind);
    final digest = storeHex(storeSha256(bytes));
    final file = switch (kind) {
      RegistryKind.identity => layout.identityManifestFile(
          sessionId!,
          generation: generation,
          digest: digest,
        ),
      RegistryKind.command => layout.commandManifestFile(
          sessionId!,
          generation: generation,
          digest: digest,
        ),
      RegistryKind.sessionCatalog => layout.rootRegistryManifestFile(
          kind: kind,
          generation: generation,
          digest: digest,
        ),
      RegistryKind.createSessionCommand => layout.rootRegistryManifestFile(
          kind: kind,
          generation: generation,
          digest: digest,
        ),
    };
    await _writer.writeImmutable(file, bytes, durability: durability);
    return manifest;
  }

  Future<void> _writeSessionManifest(
    _FileSessionState state, {
    required AgentStoreDurability durability,
  }) async {
    final object = <String, Object?>{
      'commandManifest': _registryManifestReference(state.commandManifest),
      'commandReceipts': <Object?>[
        for (final commandId in _sortedCommandIds(
          state.commandReceipts.keys,
        ))
          <String, Object?>{
            'commandId': commandId.value,
            'receipt': _appendReceiptJson(
              state.commandReceipts[commandId]!,
            ),
          },
      ],
      'compactionReceipts': <Object?>[
        for (final sequence in (state.compactionReceipts.keys.toList()..sort()))
          <String, Object?>{
            'receipt': _appendReceiptJson(
              state.compactionReceipts[sequence]!,
            ),
            'throughSequence': sequence,
          },
      ],
      'formatVersion': agentManifestFormatVersion,
      'generation': state.head.generation,
      'head': state.head.toJson(),
      'identityManifest': _registryManifestReference(
        state.identityManifest,
      ),
      'segments': <Object?>[
        for (final segment in state.segments) segment.toJson(),
      ],
      'retention': <String, Object?>{
        'policy': state.retentionPolicy.name,
        'prefixCommitment': state.prefixCommitment.toJson(),
      },
      'sessionId': state.sessionId.value,
      'snapshot': state.snapshot == null
          ? null
          : <String, Object?>{
              'digest': state.snapshotDigest,
              'snapshotId': state.snapshot!.snapshotId.value,
            },
    };
    final encoded = _storeManifestCodec.encode(object);
    final file = layout.sessionManifestFile(
      state.sessionId,
      generation: state.head.generation,
      digest: encoded.digest,
    );
    await _writer.writeImmutable(
      file,
      encoded.bytes,
      durability: durability,
    );
    _storeManifestCodec.decodeGeneration(
      StoreGenerationFile(
        file: file,
        generation: encoded.generation,
        digest: encoded.digest,
      ),
      Uint8List.fromList(await file.readAsBytes()),
    );
  }

  Future<void> _writeRootManifest(
    _FileRootState state, {
    required AgentStoreDurability durability,
  }) async {
    final encoded = _storeManifestCodec.encode(<String, Object?>{
      'catalogManifest': _registryManifestReference(
        state.catalogManifest!,
      ),
      'commandManifest': _registryManifestReference(
        state.commandManifest!,
      ),
      'createReceipts': <Object?>[
        for (final commandId in _sortedCommandIds(state.receipts.keys))
          <String, Object?>{
            'commandId': commandId.value,
            'receipt': _createReceiptJson(state.receipts[commandId]!),
          },
      ],
      'formatVersion': agentManifestFormatVersion,
      'generation': state.head.generation,
      'head': state.head.toJson(),
    });
    final file = layout.rootManifestFile(
      generation: state.head.generation,
      digest: encoded.digest,
    );
    await _writer.writeImmutable(
      file,
      encoded.bytes,
      durability: durability,
    );
    _storeManifestCodec.decodeGeneration(
      StoreGenerationFile(
        file: file,
        generation: encoded.generation,
        digest: encoded.digest,
      ),
      Uint8List.fromList(await file.readAsBytes()),
    );
  }

  Future<RegistryManifest> _readRegistryManifestReference(
    Map<String, Object?> reference,
    RegistryKind kind, {
    SessionId? sessionId,
  }) async {
    _requireExactKeys(
      reference,
      const <String>{'digest', 'generation', 'rootDigest'},
    );
    final digest = _requiredDigest(reference, 'digest');
    final generation = _requiredInt(reference, 'generation');
    final expectedRootDigest = _requiredDigest(reference, 'rootDigest');
    final file = switch (kind) {
      RegistryKind.identity => layout.identityManifestFile(
          sessionId!,
          generation: generation,
          digest: digest,
        ),
      RegistryKind.command => layout.commandManifestFile(
          sessionId!,
          generation: generation,
          digest: digest,
        ),
      RegistryKind.sessionCatalog => layout.rootRegistryManifestFile(
          kind: kind,
          generation: generation,
          digest: digest,
        ),
      RegistryKind.createSessionCommand => layout.rootRegistryManifestFile(
          kind: kind,
          generation: generation,
          digest: digest,
        ),
    };
    layout.validateExistingArtifact(file);
    final bytes = Uint8List.fromList(await file.readAsBytes());
    if (storeHex(storeSha256(bytes)) != digest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Registry manifest artifact digest does not match.',
      );
    }
    final manifest = _manifestCodec.decode(bytes, expectedKind: kind);
    if (manifest.generation != generation ||
        manifest.rootDigest != expectedRootDigest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Registry manifest reference does not match.',
      );
    }
    return manifest;
  }

  Future<Set<String>> _readIdentities(
    SessionId sessionId,
    RegistryManifest manifest,
  ) async {
    final values = <String>{};
    final artifacts = <String, Uint8List>{};
    for (final reference in manifest.chunks) {
      final file = layout.identityChunkFile(sessionId, reference.digest);
      layout.validateExistingArtifact(file);
      final bytes = Uint8List.fromList(await file.readAsBytes());
      artifacts[reference.digest] = bytes;
      final decoded = _identityCodec.decodeChunk(
        bytes,
        expectedKind: AgentIdentityKind.parse(reference.shard),
      );
      if (decoded.reference.firstKey != reference.firstKey ||
          decoded.reference.lastKey != reference.lastKey ||
          decoded.reference.entryCount != reference.entryCount) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Identity chunk does not match its manifest.',
        );
      }
      for (final entry in decoded.entries) {
        if (!values.add(entry.id.value)) {
          throw const AgentStoreException(
            AgentStoreErrorCode.corruption,
            'Identity registry contains a duplicate allocation.',
          );
        }
      }
    }
    _manifestCodec.verifyChunks(manifest, artifacts);
    return values;
  }

  Future<Map<CommandId, AgentStoreAcceptedCommand>> _readCommands(
    SessionId sessionId,
    RegistryManifest manifest,
  ) async {
    final values = <CommandId, AgentStoreAcceptedCommand>{};
    final artifacts = <String, Uint8List>{};
    for (final reference in manifest.chunks) {
      final file = layout.commandChunkFile(sessionId, reference.digest);
      layout.validateExistingArtifact(file);
      final bytes = Uint8List.fromList(await file.readAsBytes());
      artifacts[reference.digest] = bytes;
      final decoded = _commandCodec.decodeChunk(
        bytes,
        expectedShard: reference.shard,
      );
      for (final entry in decoded.entries) {
        if (values.containsKey(entry.commandId)) {
          throw const AgentStoreException(
            AgentStoreErrorCode.corruption,
            'Command registry contains a duplicate CommandId.',
          );
        }
        values[entry.commandId] = entry;
      }
    }
    _manifestCodec.verifyChunks(manifest, artifacts);
    return values;
  }

  Future<bool> _registryRootExists(
    SessionId sessionId, {
    required RegistryKind kind,
    required int throughGeneration,
    required String rootDigest,
  }) async {
    final directory = switch (kind) {
      RegistryKind.identity => layout.identityManifests(sessionId),
      RegistryKind.command => layout.commandManifests(sessionId),
      RegistryKind.sessionCatalog ||
      RegistryKind.createSessionCommand =>
        throw ArgumentError.value(kind, 'kind', 'must be Session-scoped'),
    };
    for (final generation in _generationFiles(directory).reversed) {
      if (generation.generation > throughGeneration) continue;
      try {
        final bytes = Uint8List.fromList(await generation.file.readAsBytes());
        final manifest = _manifestCodec.decode(bytes, expectedKind: kind);
        if (storeHex(storeSha256(bytes)) != generation.digest ||
            manifest.generation != generation.generation ||
            manifest.rootDigest != rootDigest) {
          continue;
        }
        if (kind == RegistryKind.identity) {
          await _readIdentities(sessionId, manifest);
        } else {
          await _readCommands(sessionId, manifest);
        }
        return true;
      } on StoreFormatException {
        continue;
      }
    }
    return false;
  }

  Future<void> _protectRegistryReference(
    SessionId sessionId,
    RegistryKind kind,
    Map<String, Object?> reference,
    Set<String> protectedPaths,
  ) async {
    final digest = _requiredDigest(reference, 'digest');
    final generation = _requiredInt(reference, 'generation');
    final file = kind == RegistryKind.identity
        ? layout.identityManifestFile(
            sessionId,
            generation: generation,
            digest: digest,
          )
        : layout.commandManifestFile(
            sessionId,
            generation: generation,
            digest: digest,
          );
    protectedPaths.add(file.absolute.path);
    if (!file.existsSync()) return;
    final manifest = _manifestCodec.decode(
      Uint8List.fromList(await file.readAsBytes()),
      expectedKind: kind,
    );
    for (final chunk in manifest.chunks) {
      final chunkFile = kind == RegistryKind.identity
          ? layout.identityChunkFile(sessionId, chunk.digest)
          : layout.commandChunkFile(sessionId, chunk.digest);
      protectedPaths.add(chunkFile.absolute.path);
    }
  }

  Future<void> _protectRegistryRoot(
    SessionId sessionId, {
    required RegistryKind kind,
    required String rootDigest,
    required Set<String> protectedPaths,
  }) async {
    final directory = kind == RegistryKind.identity
        ? layout.identityManifests(sessionId)
        : layout.commandManifests(sessionId);
    for (final generation in _generationFiles(directory)) {
      try {
        final bytes = Uint8List.fromList(await generation.file.readAsBytes());
        final manifest = _manifestCodec.decode(bytes, expectedKind: kind);
        if (storeHex(storeSha256(bytes)) != generation.digest ||
            manifest.rootDigest != rootDigest) {
          continue;
        }
        await _protectRegistryReference(
          sessionId,
          kind,
          <String, Object?>{
            'digest': generation.digest,
            'generation': generation.generation,
            'rootDigest': rootDigest,
          },
          protectedPaths,
        );
        return;
      } on StoreFormatException {
        continue;
      }
    }
    throw const AgentStoreException(
      AgentStoreErrorCode.corruption,
      'Snapshot registry root has no valid generation.',
    );
  }

  Future<Set<SessionId>> _readSessionCatalog(
    RegistryManifest manifest,
  ) async {
    final values = <SessionId>{};
    final artifacts = <String, Uint8List>{};
    for (final reference in manifest.chunks) {
      final file = layout.sessionCatalogChunkFile(reference.digest);
      layout.validateExistingArtifact(file);
      final bytes = Uint8List.fromList(await file.readAsBytes());
      artifacts[reference.digest] = bytes;
      final decoded = _catalogCodec.decodeChunk(
        bytes,
        expectedShard: reference.shard,
      );
      for (final sessionId in decoded.entries) {
        if (!values.add(sessionId)) {
          throw const AgentStoreException(
            AgentStoreErrorCode.corruption,
            'Session catalog contains a duplicate SessionId.',
          );
        }
      }
    }
    _manifestCodec.verifyChunks(manifest, artifacts);
    return values;
  }

  Future<_DecodedRootCommands> _readRootCommands(
    RegistryManifest manifest,
  ) async {
    final values = <CommandId, AgentStoreAcceptedCommand>{};
    final sessions = <CommandId, SessionId>{};
    final artifacts = <String, Uint8List>{};
    for (final reference in manifest.chunks) {
      final file = layout.createSessionCommandChunkFile(reference.digest);
      layout.validateExistingArtifact(file);
      final bytes = Uint8List.fromList(await file.readAsBytes());
      artifacts[reference.digest] = bytes;
      final decoded = _rootCommandCodec.decodeChunk(
        bytes,
        expectedShard: reference.shard,
      );
      for (final entry in decoded.entries) {
        if (values.containsKey(entry.commandId)) {
          throw const AgentStoreException(
            AgentStoreErrorCode.corruption,
            'Root command registry contains a duplicate CommandId.',
          );
        }
        values[entry.commandId] = AgentStoreAcceptedCommand(
          commandId: entry.commandId,
          contentDigest: entry.contentDigest,
          receipt: entry.receipt,
        );
        sessions[entry.commandId] = entry.sessionId;
      }
    }
    _manifestCodec.verifyChunks(manifest, artifacts);
    return _DecodedRootCommands(
      commands: values,
      sessions: sessions,
    );
  }

  List<StoreGenerationFile> _generationFiles(Directory directory) {
    if (!directory.existsSync()) return const <StoreGenerationFile>[];
    final result = <StoreGenerationFile>[];
    for (final entity in directory.listSync(followLinks: false)) {
      if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Manifest directory contains a non-regular entity.',
        );
      }
      final generation = StoreGenerationFile.tryParse(File(entity.path));
      if (generation != null) result.add(generation);
    }
    result.sort((left, right) {
      final generation = left.generation.compareTo(right.generation);
      return generation != 0 ? generation : left.digest.compareTo(right.digest);
    });
    return result;
  }

  ({
    StoreGenerationFile file,
    Map<String, Object?> object,
  })? _latestDecodableManifest(
    Directory directory, {
    List<StoreGenerationFile>? candidateFiles,
  }) {
    final files = candidateFiles ?? _generationFiles(directory);
    for (var index = files.length - 1; index >= 0;) {
      final generation = files[index].generation;
      final valid = <({
        StoreGenerationFile file,
        Map<String, Object?> object,
      })>[];
      while (index >= 0 && files[index].generation == generation) {
        final file = files[index--];
        try {
          valid.add((file: file, object: _decodeManifestFile(file)));
        } on StoreFormatException catch (error) {
          if (error.code == StoreFormatErrorCode.unsupportedVersion) {
            rethrow;
          }
        }
      }
      if (valid.length > 1) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Manifest generation has conflicting valid artifacts.',
        );
      }
      if (valid.isNotEmpty) return valid.single;
    }
    return null;
  }

  Map<String, Object?> _decodeManifestFile(StoreGenerationFile file) {
    layout.validateExistingArtifact(file.file);
    if (file.file.lengthSync() > options.limits.maximumRecoveryBytes) {
      throw const AgentStoreException(
        AgentStoreErrorCode.resourceLimit,
        'Manifest exceeds the configured recovery byte budget.',
      );
    }
    final bytes = Uint8List.fromList(file.file.readAsBytesSync());
    return _storeManifestCodec.decodeGeneration(file, bytes);
  }

  void _requireRootHead(
    AgentStoreRootHead current,
    AgentStoreRootHead expected,
  ) {
    if (current.sequence != expected.sequence) {
      throw const AgentStoreException(
        AgentStoreErrorCode.rootSequenceConflict,
        'Root sequence does not match.',
      );
    }
    if (current.stateDigest != expected.stateDigest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.rootStateDigestConflict,
        'Root state digest does not match.',
      );
    }
  }

  void _requireHead(AgentStoreHead current, AgentStoreHead expected) {
    if (current.sequence != expected.sequence) {
      throw const AgentStoreException(
        AgentStoreErrorCode.sequenceConflict,
        'Session sequence does not match.',
      );
    }
    if (current.stateDigest != expected.stateDigest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.stateDigestConflict,
        'Session state digest does not match.',
      );
    }
  }

  void _requireSameCommand(
    AgentStoreAcceptedCommand previous,
    AgentStoreAcceptedCommand proposed,
  ) {
    if (previous.contentDigest != proposed.contentDigest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.commandContentMismatch,
        'CommandId was already accepted with different content.',
      );
    }
  }

  void _validateCreateTransaction(
    AgentStoreCreateSessionTransaction transaction,
  ) {
    if (transaction.events.isEmpty ||
        transaction.events.first.type != AgentEventType.sessionCreated ||
        transaction.events.first.sequence != 1 ||
        transaction.events.any(
          (event) => event.sessionId != transaction.sessionId,
        )) {
      throw const AgentStoreException(
        AgentStoreErrorCode.invalidTransaction,
        'Create transaction must contain Session genesis.',
      );
    }
    _validateCommandDigest(transaction.acceptedCommand);
    _validateSequences(transaction.events, 1);
    _validateAllocations(
      transaction.newIdAllocations,
      requiredIds: <OpaqueId>[
        transaction.sessionId,
        transaction.acceptedCommand.commandId,
        ...transaction.events.map((event) => event.eventId),
      ],
      referencedIds: _transactionReferences(
        transaction.events,
        commandId: transaction.acceptedCommand.commandId,
        sessionId: transaction.sessionId,
      ),
    );
  }

  void _validateAppendTransaction(
    _FileSessionState session,
    AgentStoreTransaction transaction,
  ) {
    if (transaction.events.isEmpty ||
        transaction.events.any(
          (event) => event.sessionId != transaction.sessionId,
        )) {
      throw const AgentStoreException(
        AgentStoreErrorCode.invalidTransaction,
        'Append requires a non-empty same-Session batch.',
      );
    }
    if (transaction.acceptedCommand != null) {
      _validateCommandDigest(transaction.acceptedCommand!);
    }
    _validateSequences(transaction.events, session.head.sequence + 1);
    _validateAllocations(
      transaction.newIdAllocations,
      requiredIds: <OpaqueId>[
        if (transaction.acceptedCommand != null)
          transaction.acceptedCommand!.commandId,
        ...transaction.events.map((event) => event.eventId),
      ],
      referencedIds: _transactionReferences(
        transaction.events,
        commandId: transaction.acceptedCommand?.commandId,
      ),
      existingIds: session.allocatedIds,
    );
  }

  void _validateSequences(List<AgentEvent> events, int firstSequence) {
    for (var index = 0; index < events.length; index++) {
      if (events[index].sequence != firstSequence + index) {
        throw const AgentStoreException(
          AgentStoreErrorCode.invalidTransaction,
          'Event batch sequence is not contiguous.',
        );
      }
    }
  }

  void _validateCommandDigest(AgentStoreAcceptedCommand command) {
    if (!isStoreDigest(command.contentDigest)) {
      throw const AgentStoreException(
        AgentStoreErrorCode.invalidTransaction,
        'Accepted command content digest must be lowercase SHA-256.',
      );
    }
  }

  void _requireRegistryCapacity(int entryCount) {
    if (entryCount > options.limits.maximumRegistryEntries) {
      throw const AgentStoreException(
        AgentStoreErrorCode.resourceLimit,
        'Identity registry entry limit would be exceeded.',
      );
    }
  }

  void _validateAllocations(
    List<AgentStoreIdAllocation> allocations, {
    required List<OpaqueId> requiredIds,
    required Set<String> referencedIds,
    Set<String> existingIds = const <String>{},
  }) {
    final values = <String>{};
    for (final allocation in allocations) {
      if (existingIds.contains(allocation.id.value) ||
          !values.add(allocation.id.value)) {
        throw const AgentStoreException(
          AgentStoreErrorCode.duplicateId,
          'Logical ID was already allocated.',
        );
      }
      if (!referencedIds.contains(allocation.id.value)) {
        throw const AgentStoreException(
          AgentStoreErrorCode.invalidTransaction,
          'Transaction allocates an unreferenced logical ID.',
        );
      }
    }
    if (requiredIds.any((id) => !values.contains(id.value))) {
      throw const AgentStoreException(
        AgentStoreErrorCode.invalidTransaction,
        'Transaction omits a required logical ID allocation.',
      );
    }
  }

  Set<String> _transactionReferences(
    List<AgentEvent> events, {
    CommandId? commandId,
    SessionId? sessionId,
  }) {
    final result = <String>{
      if (commandId != null) commandId.value,
      if (sessionId != null) sessionId.value,
    };
    void collect(Object? value) {
      if (value is String) {
        try {
          result.add(parseAgentOpaqueId(value).value);
        } on FormatException {
          // Non-ID strings are ordinary domain values.
        }
      } else if (value is List<Object?>) {
        for (final item in value) {
          collect(item);
        }
      } else if (value is Map<String, Object?>) {
        for (final item in value.values) {
          collect(item);
        }
      }
    }

    for (final event in events) {
      result
        ..add(event.eventId.value)
        ..add(event.sessionId.value)
        ..add(event.causationId.value);
      if (event.runId != null) result.add(event.runId!.value);
      if (event.attemptId != null) result.add(event.attemptId!.value);
      if (event.workItemId != null) result.add(event.workItemId!.value);
      collect(event.payload);
    }
    return result;
  }

  void _validateSnapshot(
    AgentStoreSnapshot snapshot,
    AgentStoreHead head,
  ) {
    try {
      _snapshotCodec.validateHeadBinding(snapshot, head);
    } on StoreFormatException {
      throw const AgentStoreException(
        AgentStoreErrorCode.snapshotConflict,
        'Snapshot does not bind the current Session head.',
      );
    }
  }

  Map<String, Object?> _createMetadata(
    AgentStoreCreateSessionTransaction transaction,
  ) =>
      <String, Object?>{
        'acceptedCommand': _acceptedCommandJson(
          transaction.acceptedCommand,
        ),
        'allocatedSessionId': transaction.sessionId.value,
        'newIdAllocations':
            transaction.newIdAllocations.map((entry) => entry.id.value).toList()
              ..sort(),
        'schemaVersion': 1,
        'transactionKind': 'createSession',
      };

  Map<String, Object?> _appendMetadata(
    AgentStoreTransaction transaction,
  ) =>
      <String, Object?>{
        if (transaction.acceptedCommand != null)
          'acceptedCommand': _acceptedCommandJson(
            transaction.acceptedCommand!,
          ),
        'newIdAllocations':
            transaction.newIdAllocations.map((entry) => entry.id.value).toList()
              ..sort(),
        'schemaVersion': 1,
        'transactionKind': 'append',
      };
}

final class _FileRootState {
  _FileRootState({
    required this.head,
    required Set<SessionId> sessionIds,
    required Map<CommandId, AgentStoreAcceptedCommand> commands,
    required Map<CommandId, AgentStoreCreateSessionReceipt> receipts,
    required this.catalogManifest,
    required this.commandManifest,
  })  : sessionIds = Set<SessionId>.unmodifiable(sessionIds),
        commands =
            Map<CommandId, AgentStoreAcceptedCommand>.unmodifiable(commands),
        receipts = Map<CommandId, AgentStoreCreateSessionReceipt>.unmodifiable(
          receipts,
        );

  factory _FileRootState.empty() => _FileRootState(
        head: AgentStoreRootHead.empty,
        sessionIds: const <SessionId>{},
        commands: const <CommandId, AgentStoreAcceptedCommand>{},
        receipts: const <CommandId, AgentStoreCreateSessionReceipt>{},
        catalogManifest: null,
        commandManifest: null,
      );

  final AgentStoreRootHead head;
  final Set<SessionId> sessionIds;
  final Map<CommandId, AgentStoreAcceptedCommand> commands;
  final Map<CommandId, AgentStoreCreateSessionReceipt> receipts;
  final RegistryManifest? catalogManifest;
  final RegistryManifest? commandManifest;
}

final class _FileSessionState {
  _FileSessionState({
    required this.sessionId,
    required this.head,
    required List<_SegmentReference> segments,
    List<AgentEvent> events = const <AgentEvent>[],
    required Set<String> allocatedIds,
    required Map<CommandId, AgentStoreAcceptedCommand> commands,
    required Map<CommandId, AgentStoreAppendReceipt> commandReceipts,
    required Map<int, AgentStoreAppendReceipt> compactionReceipts,
    required this.identityManifest,
    required this.commandManifest,
    required this.retentionPolicy,
    required this.prefixCommitment,
    Map<int, String> journalDigests = const <int, String>{},
    this.snapshot,
    this.snapshotDigest,
  })  : segments = List<_SegmentReference>.unmodifiable(segments),
        events = List<AgentEvent>.unmodifiable(events),
        allocatedIds = Set<String>.unmodifiable(allocatedIds),
        commands =
            Map<CommandId, AgentStoreAcceptedCommand>.unmodifiable(commands),
        commandReceipts = Map<CommandId, AgentStoreAppendReceipt>.unmodifiable(
          commandReceipts,
        ),
        compactionReceipts = Map<int, AgentStoreAppendReceipt>.unmodifiable(
          compactionReceipts,
        ),
        journalDigests = Map<int, String>.unmodifiable(journalDigests);

  final SessionId sessionId;
  final AgentStoreHead head;
  final List<_SegmentReference> segments;
  final List<AgentEvent> events;
  final Set<String> allocatedIds;
  final Map<CommandId, AgentStoreAcceptedCommand> commands;
  final Map<CommandId, AgentStoreAppendReceipt> commandReceipts;
  final Map<int, AgentStoreAppendReceipt> compactionReceipts;
  final RegistryManifest identityManifest;
  final RegistryManifest commandManifest;
  final StoreRetentionPolicy retentionPolicy;
  final StorePrefixCommitment prefixCommitment;
  final Map<int, String> journalDigests;
  final AgentStoreSnapshot? snapshot;
  final String? snapshotDigest;

  _FileSessionState copyWith({
    AgentStoreHead? head,
    List<_SegmentReference>? segments,
    Set<String>? allocatedIds,
    Map<CommandId, AgentStoreAcceptedCommand>? commands,
    Map<CommandId, AgentStoreAppendReceipt>? commandReceipts,
    Map<int, AgentStoreAppendReceipt>? compactionReceipts,
    RegistryManifest? identityManifest,
    RegistryManifest? commandManifest,
    StoreRetentionPolicy? retentionPolicy,
    StorePrefixCommitment? prefixCommitment,
    Map<int, String>? journalDigests,
    AgentStoreSnapshot? snapshot,
    String? snapshotDigest,
  }) =>
      _FileSessionState(
        sessionId: sessionId,
        head: head ?? this.head,
        segments: segments ?? this.segments,
        events: events,
        allocatedIds: allocatedIds ?? this.allocatedIds,
        commands: commands ?? this.commands,
        commandReceipts: commandReceipts ?? this.commandReceipts,
        compactionReceipts: compactionReceipts ?? this.compactionReceipts,
        identityManifest: identityManifest ?? this.identityManifest,
        commandManifest: commandManifest ?? this.commandManifest,
        retentionPolicy: retentionPolicy ?? this.retentionPolicy,
        prefixCommitment: prefixCommitment ?? this.prefixCommitment,
        journalDigests: journalDigests ?? this.journalDigests,
        snapshot: snapshot ?? this.snapshot,
        snapshotDigest: snapshotDigest ?? this.snapshotDigest,
      );
}

final class _SegmentReference {
  const _SegmentReference({
    required this.startSequence,
    required this.recordCount,
    required this.artifactDigest,
    required this.finalRecordDigest,
  });

  factory _SegmentReference.fromJson(Map<String, Object?> value) {
    _requireExactKeys(value, const <String>{
      'artifactDigest',
      'finalRecordDigest',
      'recordCount',
      'startSequence',
    });
    return _SegmentReference(
      startSequence: _requiredInt(value, 'startSequence'),
      recordCount: _requiredInt(value, 'recordCount'),
      artifactDigest: _requiredDigest(value, 'artifactDigest'),
      finalRecordDigest: _requiredDigest(value, 'finalRecordDigest'),
    );
  }

  final int startSequence;
  final int recordCount;
  final String artifactDigest;
  final String finalRecordDigest;

  Map<String, Object?> toJson() => <String, Object?>{
        'artifactDigest': artifactDigest,
        'finalRecordDigest': finalRecordDigest,
        'recordCount': recordCount,
        'startSequence': startSequence,
      };
}

final class _SessionRegistryRoots {
  const _SessionRegistryRoots({
    required this.identity,
    required this.command,
  });

  final RegistryManifest identity;
  final RegistryManifest command;
}

final class _RootRegistryRoots {
  const _RootRegistryRoots({
    required this.catalog,
    required this.command,
  });

  final RegistryManifest catalog;
  final RegistryManifest command;
}

final class _DecodedRootCommands {
  _DecodedRootCommands({
    required Map<CommandId, AgentStoreAcceptedCommand> commands,
    required Map<CommandId, SessionId> sessions,
  })  : commands =
            Map<CommandId, AgentStoreAcceptedCommand>.unmodifiable(commands),
        sessions = Map<CommandId, SessionId>.unmodifiable(sessions);

  final Map<CommandId, AgentStoreAcceptedCommand> commands;
  final Map<CommandId, SessionId> sessions;
}

Map<String, Object?> _registryManifestReference(
  RegistryManifest manifest,
) =>
    <String, Object?>{
      'digest': storeHex(
        storeSha256(canonicalJsonBytes(manifest.toJson())),
      ),
      'generation': manifest.generation,
      'rootDigest': manifest.rootDigest,
    };

Map<String, Object?> _acceptedCommandJson(
  AgentStoreAcceptedCommand command,
) =>
    <String, Object?>{
      'commandId': command.commandId.value,
      'contentDigest': command.contentDigest,
      'receipt': command.receipt,
    };

Map<String, Object?> _appendReceiptJson(AgentStoreAppendReceipt receipt) =>
    <String, Object?>{
      'achievedDurability': receipt.achievedDurability.name,
      'afterHead': receipt.afterHead.toJson(),
      'beforeHead': receipt.beforeHead.toJson(),
      'eventIds': <Object?>[
        for (final eventId in receipt.eventIds) eventId.value,
      ],
      'requestedDurability': receipt.requestedDurability.name,
    };

Map<String, Object?> _createReceiptJson(
  AgentStoreCreateSessionReceipt receipt,
) =>
    <String, Object?>{
      'achievedDurability': receipt.achievedDurability.name,
      'afterRootHead': receipt.afterRootHead.toJson(),
      'beforeRootHead': receipt.beforeRootHead.toJson(),
      'eventIds': <Object?>[
        for (final eventId in receipt.eventIds) eventId.value,
      ],
      'requestedDurability': receipt.requestedDurability.name,
      'sessionHead': receipt.sessionHead.toJson(),
      'sessionId': receipt.sessionId.value,
    };

AgentStoreAppendReceipt _decodeAppendReceipt(
  Map<String, Object?> value,
) {
  _requireExactKeys(value, const <String>{
    'achievedDurability',
    'afterHead',
    'beforeHead',
    'eventIds',
    'requestedDurability',
  });
  return AgentStoreAppendReceipt(
    beforeHead: _decodeHead(_requiredObject(value, 'beforeHead')),
    afterHead: _decodeHead(_requiredObject(value, 'afterHead')),
    eventIds: <EventId>[
      for (final raw in _requiredList(value, 'eventIds'))
        EventId.parse(_asString(raw, 'Receipt EventId')),
    ],
    requestedDurability: _decodeDurability(
      _requiredString(value, 'requestedDurability'),
    ),
    achievedDurability: _decodeDurability(
      _requiredString(value, 'achievedDurability'),
    ),
  );
}

AgentStoreCreateSessionReceipt _decodeCreateReceipt(
  Map<String, Object?> value,
) {
  _requireExactKeys(value, const <String>{
    'achievedDurability',
    'afterRootHead',
    'beforeRootHead',
    'eventIds',
    'requestedDurability',
    'sessionHead',
    'sessionId',
  });
  return AgentStoreCreateSessionReceipt(
    beforeRootHead: _decodeRootHead(
      _requiredObject(value, 'beforeRootHead'),
    ),
    afterRootHead: _decodeRootHead(
      _requiredObject(value, 'afterRootHead'),
    ),
    sessionId: SessionId.parse(_requiredString(value, 'sessionId')),
    sessionHead: _decodeHead(_requiredObject(value, 'sessionHead')),
    eventIds: <EventId>[
      for (final raw in _requiredList(value, 'eventIds'))
        EventId.parse(_asString(raw, 'Receipt EventId')),
    ],
    requestedDurability: _decodeDurability(
      _requiredString(value, 'requestedDurability'),
    ),
    achievedDurability: _decodeDurability(
      _requiredString(value, 'achievedDurability'),
    ),
  );
}

AgentStoreHead _decodeHead(Map<String, Object?> value) {
  _requireExactKeys(value, const <String>{
    'commandRegistryRootDigest',
    'generation',
    'historyFloorSequence',
    'identityRegistryRootDigest',
    'journalHeadDigest',
    'sequence',
    'stateDigest',
  });
  final head = AgentStoreHead.compose(
    sequence: _requiredInt(value, 'sequence'),
    journalHeadDigest: _requiredDigest(value, 'journalHeadDigest'),
    identityRegistryRootDigest:
        _requiredDigest(value, 'identityRegistryRootDigest'),
    commandRegistryRootDigest:
        _requiredDigest(value, 'commandRegistryRootDigest'),
    generation: _requiredInt(value, 'generation'),
    historyFloorSequence: _requiredInt(value, 'historyFloorSequence'),
  );
  if (head.stateDigest != _requiredDigest(value, 'stateDigest')) {
    throw const AgentStoreException(
      AgentStoreErrorCode.corruption,
      'Session state digest does not match its fields.',
    );
  }
  return head;
}

AgentStoreRootHead _decodeRootHead(Map<String, Object?> value) {
  _requireExactKeys(value, const <String>{
    'createSessionCommandRegistryRootDigest',
    'generation',
    'sequence',
    'sessionCatalogRootDigest',
    'stateDigest',
  });
  final head = AgentStoreRootHead.compose(
    sequence: _requiredInt(value, 'sequence'),
    sessionCatalogRootDigest:
        _requiredDigest(value, 'sessionCatalogRootDigest'),
    createSessionCommandRegistryRootDigest:
        _requiredDigest(value, 'createSessionCommandRegistryRootDigest'),
    generation: _requiredInt(value, 'generation'),
  );
  if (head.stateDigest != _requiredDigest(value, 'stateDigest')) {
    throw const AgentStoreException(
      AgentStoreErrorCode.corruption,
      'Root state digest does not match its fields.',
    );
  }
  return head;
}

AgentStoreDurability _decodeDurability(String value) {
  for (final durability in AgentStoreDurability.values) {
    if (durability.name == value) return durability;
  }
  throw const AgentStoreException(
    AgentStoreErrorCode.corruption,
    'Receipt contains an unknown durability level.',
  );
}

List<CommandId> _sortedCommandIds(Iterable<CommandId> ids) =>
    List<CommandId>.of(ids)
      ..sort((left, right) => left.value.compareTo(right.value));

void _requireManifestVersion(Map<String, Object?> value) {
  if (_requiredInt(value, 'formatVersion') != agentManifestFormatVersion) {
    throw const StoreFormatException(
      StoreFormatErrorCode.unsupportedVersion,
      'Unsupported Store manifest version.',
    );
  }
}

void _requireExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
) {
  if (value.keys.toSet().length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    throw const AgentStoreException(
      AgentStoreErrorCode.corruption,
      'Store object has missing or unknown fields.',
    );
  }
}

Map<String, Object?> _requiredObject(
  Map<String, Object?> value,
  String key,
) =>
    _asObject(value[key], 'Store field $key');

Map<String, Object?> _asObject(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw AgentStoreException(
      AgentStoreErrorCode.corruption,
      '$label must be an object.',
    );
  }
  return value;
}

List<Object?> _requiredList(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) {
    throw AgentStoreException(
      AgentStoreErrorCode.corruption,
      'Store field $key must be a list.',
    );
  }
  return field;
}

String _requiredString(Map<String, Object?> value, String key) =>
    _asString(value[key], 'Store field $key');

String _asString(Object? value, String label) {
  if (value is! String) {
    throw AgentStoreException(
      AgentStoreErrorCode.corruption,
      '$label must be a string.',
    );
  }
  return value;
}

int _requiredInt(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int || field < 0) {
    throw AgentStoreException(
      AgentStoreErrorCode.corruption,
      'Store field $key must be a non-negative integer.',
    );
  }
  return field;
}

String _requiredDigest(Map<String, Object?> value, String key) {
  final field = _requiredString(value, key);
  if (!isStoreDigest(field)) {
    throw AgentStoreException(
      AgentStoreErrorCode.corruption,
      'Store field $key must be a lowercase SHA-256 digest.',
    );
  }
  return field;
}
