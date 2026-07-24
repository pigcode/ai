import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

final fixtureSessionId =
    SessionId.parse('ses_00000000000000000000000000000000');
final fixtureCreateCommandId =
    CommandId.parse('cmd_00000000000000000000000000000000');

AgentStoreCreateSessionTransaction fixtureCreateTransaction(
  AgentStoreRootHead expectedHead,
) =>
    AgentStoreCreateSessionTransaction(
      expectedRootHead: expectedHead,
      sessionId: fixtureSessionId,
      acceptedCommand: AgentStoreAcceptedCommand(
        commandId: fixtureCreateCommandId,
        contentDigest: canonicalJsonSha256('create'),
        receipt: <String, Object?>{
          'kind': 'createSession',
          'sessionId': fixtureSessionId.value,
        },
      ),
      newIdAllocations: <AgentStoreIdAllocation>[
        AgentStoreIdAllocation(fixtureSessionId),
        AgentStoreIdAllocation(fixtureCreateCommandId),
        AgentStoreIdAllocation(fixtureEventId(1)),
      ],
      events: <AgentEvent>[
        fixtureEvent(
          1,
          commandId: fixtureCreateCommandId,
          eventId: fixtureEventId(1),
          type: AgentEventType.sessionCreated,
        ),
      ],
    );

AgentStoreTransaction fixtureAppendTransaction(
  AgentStoreHead expectedHead,
  int variant,
) {
  final commandId = CommandId.parse(
    'cmd_${variant.toString().padLeft(32, '0')}',
  );
  final eventId = fixtureEventId(
    expectedHead.sequence + 1,
    variant: variant,
  );
  return AgentStoreTransaction(
    sessionId: fixtureSessionId,
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
      fixtureEvent(
        expectedHead.sequence + 1,
        commandId: commandId,
        eventId: eventId,
        type: AgentEventType.sessionCapabilitiesPinned,
      ),
    ],
  );
}

AgentStoreTransaction fixtureMultiEventAppendTransaction(
  AgentStoreHead expectedHead,
  int variant,
) {
  final commandId = CommandId.parse(
    'cmd_${variant.toString().padLeft(32, '0')}',
  );
  final firstSequence = expectedHead.sequence + 1;
  final firstEventId = fixtureEventId(firstSequence, variant: variant);
  final secondEventId = fixtureEventId(firstSequence + 1, variant: variant);
  return AgentStoreTransaction(
    sessionId: fixtureSessionId,
    expectedHead: expectedHead,
    acceptedCommand: AgentStoreAcceptedCommand(
      commandId: commandId,
      contentDigest: canonicalJsonSha256('multi-append-$variant'),
      receipt: <String, Object?>{
        'kind': 'multiAppend',
        'variant': variant,
      },
    ),
    newIdAllocations: <AgentStoreIdAllocation>[
      AgentStoreIdAllocation(commandId),
      AgentStoreIdAllocation(firstEventId),
      AgentStoreIdAllocation(secondEventId),
    ],
    events: <AgentEvent>[
      fixtureEvent(
        firstSequence,
        commandId: commandId,
        eventId: firstEventId,
        type: AgentEventType.sessionCapabilitiesPinned,
      ),
      fixtureEvent(
        firstSequence + 1,
        commandId: commandId,
        eventId: secondEventId,
        type: AgentEventType.sessionAttachmentChanged,
      ),
    ],
  );
}

AgentStoreSnapshot fixtureSnapshot(
  AgentStoreHead head, {
  int variant = 8,
}) {
  final projection = <String, Object?>{
    'approvals': <String, Object?>{},
    'currentRunId': null,
    'deferredOperations': <String, Object?>{},
    'journalSequence': head.sequence,
    'resources': <String, Object?>{},
    'workItems': <String, Object?>{},
  };
  return AgentStoreSnapshot(
    sessionId: fixtureSessionId,
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

AgentEvent fixtureEvent(
  int sequence, {
  required CommandId commandId,
  required EventId eventId,
  required AgentEventType type,
}) =>
    AgentEvent(
      eventId: eventId,
      schemaVersion: 1,
      sessionId: fixtureSessionId,
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 7, 24),
      type: type,
      causationId: commandId,
      payload: const <String, Object?>{},
      metadata: AgentEventMetadata.empty(),
    );

EventId fixtureEventId(int sequence, {int variant = 0}) => EventId.parse(
      'evt_${(sequence * 10 + variant).toString().padLeft(32, '0')}',
    );
