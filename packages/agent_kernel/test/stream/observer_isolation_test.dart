import 'dart:async';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';
import '../support/running_kernel_fixture.dart';

void main() {
  test('observer cancel, error, and idle close append no Run event', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final before = (await fixture.store.loadSession(running.sessionId)).head;

    final cancelled = fixture.kernel.subscribeEvents(
      sessionId: running.sessionId,
      cursor: AgentEventCursor(
        sessionId: running.sessionId,
        sequence: before.sequence,
      ),
    );
    await cancelled.stream.listen((_) {}).cancel();

    final errored = fixture.kernel.subscribeEvents(
      sessionId: running.sessionId,
      cursor: AgentEventCursor(
        sessionId: running.sessionId,
        sequence: before.sequence,
      ),
    );
    final errorDone = Completer<void>();
    errored.stream.listen(
      (_) {},
      onError: (_) {},
      onDone: errorDone.complete,
    );
    errored.fail(
      const SubscriptionError(
        SubscriptionErrorCode.closed,
        'Injected observer failure.',
      ),
    );
    await errorDone.future;

    final idle = fixture.kernel.subscribeEvents(
      sessionId: running.sessionId,
      cursor: AgentEventCursor(
        sessionId: running.sessionId,
        sequence: before.sequence,
      ),
    );
    final idleDone = idle.stream.listen((_) {}).asFuture<void>();
    idle.closeForIdle();
    await idleDone;

    expect(
      (await fixture.store.loadSession(running.sessionId)).head,
      before,
    );
  });

  test('Run-scoped stream closes only after persisted terminal is emitted',
      () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final subscription = fixture.kernel.subscribeEvents(
      sessionId: running.sessionId,
      runId: running.runId,
      cursor: AgentEventCursor(
        sessionId: running.sessionId,
        sequence: running.handle.head.sequence,
      ),
    );
    final eventsFuture = subscription.stream.toList();
    await Future<void>.delayed(Duration.zero);
    expect(subscription.isClosed, isFalse);

    await fixture.kernel.commitTerminal(
      handle: running.handle,
      proposal: TerminalProposal(
        runId: running.runId,
        attemptId: running.attemptId,
        executionEpoch: 1,
        outcome: TerminalOutcome.completed,
        sourceId: 'source:test',
        sourceWatermark: 1,
        causationId: running.driverCommandId,
        payload: const <String, Object?>{},
      ),
      drainedSourceWatermarks: const <String, int>{'source:test': 1},
    );
    final events = await eventsFuture;

    expect(events, hasLength(1));
    expect(events.single.type, AgentEventType.runCompleted);
    expect(subscription.isClosed, isTrue);
  });
}
