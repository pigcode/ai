import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';

void main() {
  final marker = <String>['sk', '-', 'abcdefghijklmnopqrstuvwx'].join();

  test('P3-TM-INFO-01 rejects secrets from command persistence', () async {
    final fixture = KernelFixture();
    final (created, _) = await fixture.createSession();
    final command = StartRunCommand(
      commandId: startCommandId,
      handle: created.sessionHandle!,
      input: <String, Object?>{'prompt': marker},
    );

    await expectLater(
      fixture.kernel.startRun(command),
      throwsA(_secretRejectedWithoutMarker(marker)),
    );
    expect(
      (await fixture.store.readEvents(created.sessionId)).events,
      hasLength(1),
    );
  });

  test('P3-TM-INFO-02 rejects secrets from events and Driver proposals', () {
    expect(
      () => AgentEvent(
        eventId: EventId.parse('evt_00000000000000000000000000000000'),
        schemaVersion: 1,
        sessionId: SessionId.parse('ses_00000000000000000000000000000000'),
        sequence: 1,
        recordedAt: DateTime.utc(2026, 7, 24),
        type: AgentEventType.sessionCreated,
        causationId: CommandId.parse('cmd_00000000000000000000000000000000'),
        payload: <String, Object?>{'value': marker},
        metadata: AgentEventMetadata.empty(),
      ),
      throwsA(_secretRejectedWithoutMarker(marker)),
    );
    expect(
      () => DriverEvent(
        driverId: 'driver:test',
        sessionId: SessionId.parse('ses_00000000000000000000000000000000'),
        runId: RunId.parse('run_00000000000000000000000000000000'),
        attemptId: AttemptId.parse('att_00000000000000000000000000000000'),
        executionEpoch: 1,
        connectionEpoch: 1,
        sourceId: 'source:test',
        sourceOrdinal: 1,
        kind: DriverEventKind.runStarted,
        payload: <String, Object?>{'value': marker},
      ),
      throwsA(_secretRejectedWithoutMarker(marker)),
    );
  });

  test('P3-TM-INFO-03 rejects secrets from errors and snapshots', () {
    expect(
      () => AgentError(
        code: AgentErrorCode.internal,
        scope: AgentErrorScope.session,
        phase: AgentErrorPhase.recovery,
        source: AgentErrorSource.kernel,
        retryDisposition: AgentRetryDisposition.never,
        effect: AgentEffect.none,
        safeMessage: marker,
        namespacedDetails: AgentEventMetadata.empty(),
      ),
      throwsA(_secretRejectedWithoutMarker(marker)),
    );
    expect(
      () => AgentStoreSnapshot(
        sessionId: SessionId.parse('ses_00000000000000000000000000000000'),
        snapshotId: SnapshotId.parse('snp_00000000000000000000000000000000'),
        sequence: 1,
        journalHeadDigest: ''.padLeft(64, 'a'),
        historyFloorSequence: 0,
        identityRegistryRootDigest: ''.padLeft(64, 'b'),
        commandRegistryRootDigest: ''.padLeft(64, 'c'),
        canonicalProjection: <String, Object?>{'value': marker},
        projectionDigest: ''.padLeft(64, 'd'),
      ),
      throwsA(_secretRejectedWithoutMarker(marker)),
    );
  });
}

Matcher _secretRejectedWithoutMarker(String marker) => isA<Object>().having(
      (error) => error.toString(),
      'safe error',
      allOf(contains('metadata_secret_rejected'), isNot(contains(marker))),
    );
