import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

final _sessionId = SessionId.parse('ses_00000000000000000000000000000000');
final _createCommandId =
    CommandId.parse('cmd_00000000000000000000000000000000');
final _appendCommandId =
    CommandId.parse('cmd_10000000000000000000000000000000');
final _createdEventId = EventId.parse('evt_00000000000000000000000000000000');
final _appendedEventId = EventId.parse('evt_10000000000000000000000000000000');

Future<void> main() async {
  // The caller owns this private temporary root. No home or workspace path is
  // used. Directory.systemTemp.createTemp creates an owner-only root on the
  // supported POSIX reference platforms.
  final root = Directory.systemTemp.createTempSync('pigcode-store-example-');
  final coordinator = await FileStoreCoordinator.start(StoreLayout.open(root));
  try {
    var store = await FileAgentStore.open(
      root: root,
      coordinator: coordinator.client,
    );
    final empty = await store.loadRoot();
    await store.createSession(_createTransaction(empty.head));

    final created = await store.loadSession(_sessionId);
    await store.append(_appendTransaction(created.head));
    final appended = await store.loadSession(_sessionId);
    await store.writeSnapshot(
      _snapshot(appended.head),
      expectedHead: appended.head,
    );

    store = await FileAgentStore.open(
      root: root,
      coordinator: coordinator.client,
    );
    final reopened = await store.loadSession(_sessionId);
    final events = await store.readEvents(_sessionId);
    print(
      'reopened sequence=${reopened.head.sequence} '
      'events=${events.events.length}',
    );
  } finally {
    await coordinator.close();
    root.deleteSync(recursive: true);
  }
}

AgentStoreCreateSessionTransaction _createTransaction(
  AgentStoreRootHead expected,
) =>
    AgentStoreCreateSessionTransaction(
      expectedRootHead: expected,
      sessionId: _sessionId,
      acceptedCommand: AgentStoreAcceptedCommand(
        commandId: _createCommandId,
        contentDigest: canonicalJsonSha256('example-create'),
        receipt: <String, Object?>{
          'kind': 'createSession',
          'sessionId': _sessionId.value,
        },
      ),
      newIdAllocations: <AgentStoreIdAllocation>[
        AgentStoreIdAllocation(_sessionId),
        AgentStoreIdAllocation(_createCommandId),
        AgentStoreIdAllocation(_createdEventId),
      ],
      events: <AgentEvent>[
        _event(
          sequence: 1,
          eventId: _createdEventId,
          commandId: _createCommandId,
          type: AgentEventType.sessionCreated,
        ),
      ],
    );

AgentStoreTransaction _appendTransaction(AgentStoreHead expected) =>
    AgentStoreTransaction(
      sessionId: _sessionId,
      expectedHead: expected,
      acceptedCommand: AgentStoreAcceptedCommand(
        commandId: _appendCommandId,
        contentDigest: canonicalJsonSha256('example-append'),
        receipt: const <String, Object?>{'kind': 'append'},
      ),
      newIdAllocations: <AgentStoreIdAllocation>[
        AgentStoreIdAllocation(_appendCommandId),
        AgentStoreIdAllocation(_appendedEventId),
      ],
      events: <AgentEvent>[
        _event(
          sequence: 2,
          eventId: _appendedEventId,
          commandId: _appendCommandId,
          type: AgentEventType.sessionCapabilitiesPinned,
        ),
      ],
    );

AgentEvent _event({
  required int sequence,
  required EventId eventId,
  required CommandId commandId,
  required AgentEventType type,
}) =>
    AgentEvent(
      eventId: eventId,
      schemaVersion: 1,
      sessionId: _sessionId,
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 7, 24),
      type: type,
      causationId: commandId,
      payload: const <String, Object?>{},
      metadata: AgentEventMetadata.empty(),
    );

AgentStoreSnapshot _snapshot(AgentStoreHead head) {
  final projection = <String, Object?>{
    'approvals': <String, Object?>{},
    'capabilitySnapshot': <String, Object?>{},
    'conversationAvailability': 'available',
    'controlAttachment': 'attached',
    'currentRunId': null,
    'deferredOperations': <String, Object?>{},
    'journalSequence': head.sequence,
    'resources': <String, Object?>{},
    'resumeStateAvailability': 'none',
    'runHistory': <Object?>[],
    'runs': <String, Object?>{},
    'runtimeLiveness': 'unknown',
    'sessionId': _sessionId.value,
    'workItems': <String, Object?>{},
  };
  return AgentStoreSnapshot(
    sessionId: _sessionId,
    snapshotId: SnapshotId.parse(
      'snp_00000000000000000000000000000000',
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
