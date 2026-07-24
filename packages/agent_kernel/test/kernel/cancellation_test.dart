import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';
import '../support/running_kernel_fixture.dart';

void main() {
  test('cancel command persists intent but not terminal', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final receipt = await fixture.kernel.cancelRun(
      CancelRunCommand(
        commandId: cancelCommandId,
        handle: running.handle,
        runId: running.runId,
      ),
    );

    expect(receipt.eventIds, hasLength(1));
    final projection = await fixture.kernel.loadProjection(running.sessionId);
    expect(
      projection.runs[running.runId]!.state,
      AgentRunState.cancelling,
    );
    expect(projection.runs[running.runId]!.terminalEventId, isNull);
  });

  test('acknowledgement is not terminal; authoritative matching barrier is',
      () {
    const cancellation = Cancellation();
    final intent = CancellationIntent(
      commandId: cancelCommandId,
      runId: _run,
    );
    final acknowledgement = CancellationBarrier(
      runId: _run,
      attemptId: runningAttemptId,
      executionEpoch: 1,
      driverAcknowledged: true,
    );
    expect(
      cancellation.evaluate(
        intent: intent,
        barrier: acknowledgement,
        authoritativeAttemptId: runningAttemptId,
        authoritativeExecutionEpoch: 1,
      ),
      CancellationDisposition.awaitingAuthoritativeBarrier,
    );

    final matching = CancellationBarrier(
      runId: _run,
      attemptId: runningAttemptId,
      executionEpoch: 1,
      intentCommandId: cancelCommandId,
    );
    expect(
      cancellation.terminalOutcome(
        cancellation.evaluate(
          intent: intent,
          barrier: matching,
          authoritativeAttemptId: runningAttemptId,
          authoritativeExecutionEpoch: 1,
        ),
      ),
      TerminalOutcome.cancelled,
    );
  });

  test('containment can prove cancellation; unknown truth is interrupted', () {
    const cancellation = Cancellation();
    final contained = CancellationBarrier(
      runId: _run,
      attemptId: runningAttemptId,
      executionEpoch: 1,
      executionContainmentProven: true,
    );
    final unknown = CancellationBarrier(
      runId: _run,
      attemptId: runningAttemptId,
      executionEpoch: 1,
    );

    expect(
      cancellation.evaluate(
        intent: null,
        barrier: contained,
        authoritativeAttemptId: runningAttemptId,
        authoritativeExecutionEpoch: 1,
      ),
      CancellationDisposition.cancelled,
    );
    expect(
      cancellation.terminalOutcome(
        cancellation.evaluate(
          intent: null,
          barrier: unknown,
          authoritativeAttemptId: runningAttemptId,
          authoritativeExecutionEpoch: 1,
        ),
      ),
      TerminalOutcome.interrupted,
    );
  });
}

final _run = RunId.parse('run_90000000000000000000000000000000');
