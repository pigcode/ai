import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('persisted Session capabilities can only narrow the manifest', () {
    final manifest = DriverCapabilitySnapshot(
      capabilities: const <String>{'run'},
      eventKinds: const <DriverEventKind>{DriverEventKind.runStarted},
      maximumPayloadBytes: 1024,
    );
    final requested = DriverCapabilitySnapshot(
      capabilities: const <String>{'run', 'work'},
      eventKinds: const <DriverEventKind>{
        DriverEventKind.runStarted,
        DriverEventKind.workProposed,
      },
      maximumPayloadBytes: 4096,
    );

    final binding = DriverBinding.bind(
      driverId: 'driver:test',
      sessionId: testSessionId,
      runId: testRunId,
      attemptId: testAttemptId,
      executionEpoch: 2,
      connectionEpoch: 3,
      manifestCapabilities: manifest,
      persistedSessionCapabilities: requested,
    );

    expect(binding.sessionCapabilities.capabilities, <String>{'run'});
    expect(
      binding.sessionCapabilities.eventKinds,
      <DriverEventKind>{DriverEventKind.runStarted},
    );
    expect(binding.sessionCapabilities.maximumPayloadBytes, 1024);
  });

  test('wrong driver, Session, Run, or Attempt is fenced audit-only', () {
    const validator = DriverEventValidator();
    final binding = testBinding();
    final cursor = DriverSourceCursor(sourceId: 'source:test');
    final proposals = <DriverEvent>[
      event(driverId: 'driver:wrong'),
      event(sessionId: otherSessionId),
      event(runId: otherRunId),
      event(attemptId: otherAttemptId),
    ];

    for (final proposal in proposals) {
      final result = validator.validate(
        binding: binding,
        proposal: proposal,
        cursor: cursor,
      );
      expect(result.disposition, DriverProposalDisposition.fenced);
      expect(result.changesDomain, isFalse);
      expect(result.canonicalEventType, isNull);
      expect(result.audit, isNotNull);
      expect(result.cursor.lastOrdinal, 0);
    }
  });
}

DriverBinding testBinding({
  Set<DriverEventKind> eventKinds = const <DriverEventKind>{
    DriverEventKind.runStarted,
    DriverEventKind.workProposed,
    DriverEventKind.terminalCompleted,
  },
  int maximumPayloadBytes = 1024,
}) {
  final capabilities = DriverCapabilitySnapshot(
    capabilities: const <String>{'run', 'work', 'terminal'},
    eventKinds: eventKinds,
    maximumPayloadBytes: maximumPayloadBytes,
  );
  return DriverBinding(
    driverId: 'driver:test',
    sessionId: testSessionId,
    runId: testRunId,
    attemptId: testAttemptId,
    executionEpoch: 2,
    connectionEpoch: 3,
    manifestCapabilities: capabilities,
    sessionCapabilities: capabilities,
  );
}

DriverEvent event({
  String driverId = 'driver:test',
  SessionId? sessionId,
  RunId? runId,
  AttemptId? attemptId,
  int executionEpoch = 2,
  int connectionEpoch = 3,
  String sourceId = 'source:test',
  int sourceOrdinal = 1,
  int? sourceWatermark,
  DriverEventKind kind = DriverEventKind.runStarted,
  Map<String, Object?> payload = const <String, Object?>{},
  Map<String, Object?> metadata = const <String, Object?>{},
}) =>
    DriverEvent(
      driverId: driverId,
      sessionId: sessionId ?? testSessionId,
      runId: runId ?? testRunId,
      attemptId: attemptId ?? testAttemptId,
      executionEpoch: executionEpoch,
      connectionEpoch: connectionEpoch,
      sourceId: sourceId,
      sourceOrdinal: sourceOrdinal,
      sourceWatermark: sourceWatermark,
      kind: kind,
      payload: payload,
      metadata: metadata,
    );

final testSessionId = SessionId.parse('ses_00000000000000000000000000000000');
final otherSessionId = SessionId.parse('ses_10000000000000000000000000000000');
final testRunId = RunId.parse('run_00000000000000000000000000000000');
final otherRunId = RunId.parse('run_10000000000000000000000000000000');
final testAttemptId = AttemptId.parse('att_00000000000000000000000000000000');
final otherAttemptId = AttemptId.parse('att_10000000000000000000000000000000');
