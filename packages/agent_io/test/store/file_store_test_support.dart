import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

final fileTestSessionId =
    SessionId.parse('ses_00000000000000000000000000000000');
final fileTestCreateCommandId =
    CommandId.parse('cmd_00000000000000000000000000000000');

final class FileStoreFixture {
  FileStoreFixture._({
    required this.temporary,
    required this.root,
    required this.coordinator,
    required this.store,
  });

  final Directory temporary;
  final Directory root;
  final FileStoreCoordinator coordinator;
  final FileAgentStore store;

  static Future<FileStoreFixture> create({
    FileStoreOptions options = const FileStoreOptions(
      rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
    ),
  }) async {
    final temporary = Directory.systemTemp.createTempSync(
      'pigcode-file-store-',
    );
    final root = Directory.fromUri(temporary.uri.resolve('store/'))
      ..createSync();
    final coordinator = await FileStoreCoordinator.start(
      StoreLayout.open(root),
    );
    final store = await FileAgentStore.open(
      root: root,
      coordinator: coordinator.client,
      options: options,
    );
    return FileStoreFixture._(
      temporary: temporary,
      root: root,
      coordinator: coordinator,
      store: store,
    );
  }

  Future<FileAgentStore> open({
    FileStoreOptions options = const FileStoreOptions(
      rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
    ),
  }) =>
      FileAgentStore.open(
        root: root,
        coordinator: coordinator.client,
        options: options,
      );

  Future<AgentStoreCreateSessionReceipt> createSession({
    FileAgentStore? using,
  }) async {
    final target = using ?? store;
    final rootState = await target.loadRoot();
    return target.createSession(
      fileCreateTransaction(rootState.head),
    );
  }

  Future<void> dispose() async {
    await coordinator.close();
    temporary.deleteSync(recursive: true);
  }
}

AgentStoreCreateSessionTransaction fileCreateTransaction(
  AgentStoreRootHead expectedHead,
) =>
    AgentStoreCreateSessionTransaction(
      expectedRootHead: expectedHead,
      sessionId: fileTestSessionId,
      acceptedCommand: AgentStoreAcceptedCommand(
        commandId: fileTestCreateCommandId,
        contentDigest: canonicalJsonSha256('create'),
        receipt: <String, Object?>{
          'kind': 'createSession',
          'sessionId': fileTestSessionId.value,
        },
      ),
      newIdAllocations: <AgentStoreIdAllocation>[
        AgentStoreIdAllocation(fileTestSessionId),
        AgentStoreIdAllocation(fileTestCreateCommandId),
        AgentStoreIdAllocation(fileEventId(1)),
      ],
      events: <AgentEvent>[
        fileEvent(
          1,
          commandId: fileTestCreateCommandId,
          type: AgentEventType.sessionCreated,
        ),
      ],
    );

AgentStoreTransaction fileAppendTransaction(
  AgentStoreHead expectedHead, {
  int variant = 1,
}) {
  final commandId = fileCommandId(variant);
  final eventId = fileEventId(expectedHead.sequence + 1, variant: variant);
  return AgentStoreTransaction(
    sessionId: fileTestSessionId,
    expectedHead: expectedHead,
    acceptedCommand: AgentStoreAcceptedCommand(
      commandId: commandId,
      contentDigest: canonicalJsonSha256('append-$variant'),
      receipt: <String, Object?>{
        'kind': 'append',
        'variant': variant,
      },
    ),
    newIdAllocations: <AgentStoreIdAllocation>[
      AgentStoreIdAllocation(commandId),
      AgentStoreIdAllocation(eventId),
    ],
    events: <AgentEvent>[
      fileEvent(
        expectedHead.sequence + 1,
        commandId: commandId,
        eventId: eventId,
        type: AgentEventType.sessionCapabilitiesPinned,
      ),
    ],
  );
}

AgentEvent fileEvent(
  int sequence, {
  required CommandId commandId,
  required AgentEventType type,
  EventId? eventId,
}) =>
    AgentEvent(
      eventId: eventId ?? fileEventId(sequence),
      schemaVersion: 1,
      sessionId: fileTestSessionId,
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 7, 24),
      type: type,
      causationId: commandId,
      payload: const <String, Object?>{},
      metadata: AgentEventMetadata.empty(),
    );

CommandId fileCommandId(int variant) => CommandId.parse(
      'cmd_${variant.toString().padLeft(32, '0')}',
    );

EventId fileEventId(int sequence, {int variant = 0}) => EventId.parse(
      'evt_${(sequence * 10 + variant).toString().padLeft(32, '0')}',
    );

AgentStoreSnapshot fileSnapshot(
  AgentStoreHead head, {
  int variant = 0,
  bool safeToPrune = true,
}) {
  final projection = <String, Object?>{
    'approvals': <String, Object?>{},
    'currentRunId': safeToPrune ? null : 'run_00000000000000000000000000000000',
    'deferredOperations': <String, Object?>{},
    'journalSequence': head.sequence,
    'resources': <String, Object?>{},
    'workItems': <String, Object?>{},
  };
  return AgentStoreSnapshot(
    sessionId: fileTestSessionId,
    snapshotId: SnapshotId.parse(
      'snp_${variant.toString().padLeft(32, '0')}',
    ),
    sequence: head.sequence,
    journalHeadDigest: head.journalHeadDigest,
    historyFloorSequence: head.historyFloorSequence,
    identityRegistryRootDigest: head.identityRegistryRootDigest,
    commandRegistryRootDigest: head.commandRegistryRootDigest,
    canonicalProjection: projection,
    projectionDigest: canonicalJsonSha256(projection),
  );
}

Matcher storeError(AgentStoreErrorCode code) => throwsA(
      isA<AgentStoreException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    );
