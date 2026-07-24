import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';
import '../support/running_kernel_fixture.dart';
import '../support/scripted_checkpoint_driver.dart';

void main() {
  test('checkpoint is persisted before suspended, then resume advances epoch',
      () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(
      fixture,
      durableCheckpointResume: true,
    );
    final suspendedRequested = await fixture.kernel.suspendRun(
      SuspendRunCommand(
        commandId: suspendCommandId,
        handle: running.handle,
        runId: running.runId,
      ),
    );
    expect(
      (await fixture.kernel.loadProjection(running.sessionId))
          .runs[running.runId]!
          .state,
      AgentRunState.suspending,
    );

    final driver = ScriptedCheckpointDriver(
      durableCheckpointResume: true,
    );
    final checkpoint = await driver.checkpoint();
    final suspended = await fixture.kernel.recordSuspendedCheckpoint(
      handle: suspendedRequested.sessionHandle!,
      runId: running.runId,
      attemptId: running.attemptId,
      causationId: running.driverCommandId,
      checkpointReference: checkpoint!,
    );
    expect(
      (await fixture.kernel.loadProjection(running.sessionId))
          .runs[running.runId]!
          .state,
      AgentRunState.suspended,
    );

    final resumed = await fixture.kernel.resumeRunFromCheckpoint(
      ResumeRunFromCheckpointCommand(
        commandId: resumeCommandId,
        handle: suspended,
        runId: running.runId,
        checkpointReference: checkpoint,
      ),
    );
    final run = (await fixture.kernel.loadProjection(running.sessionId))
        .runs[running.runId]!;
    expect(run.state, AgentRunState.resuming);
    expect(run.currentAttemptId, isNot(running.attemptId));
    expect(run.attempts[running.attemptId]!.state, RunAttemptState.fenced);
    expect(run.attempts[run.currentAttemptId]!.executionEpoch, 2);
    expect(resumed.eventIds, hasLength(2));
  });

  test('suspend is unsupported without durable checkpoint capability',
      () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);

    await expectLater(
      fixture.kernel.suspendRun(
        SuspendRunCommand(
          commandId: suspendCommandId,
          handle: running.handle,
          runId: running.runId,
        ),
      ),
      throwsA(_commandError(AgentErrorCode.unsupported)),
    );
  });

  test('failed checkpoint append leaves Run suspending', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(
      fixture,
      durableCheckpointResume: true,
    );
    final requested = await fixture.kernel.suspendRun(
      SuspendRunCommand(
        commandId: suspendCommandId,
        handle: running.handle,
        runId: running.runId,
      ),
    );
    fixture.store.failNextAppendBeforeCommit = true;

    await expectLater(
      fixture.kernel.recordSuspendedCheckpoint(
        handle: requested.sessionHandle!,
        runId: running.runId,
        attemptId: running.attemptId,
        causationId: running.driverCommandId,
        checkpointReference: 'checkpoint:test',
      ),
      throwsA(_commandError(AgentErrorCode.unavailable)),
    );
    expect(
      (await fixture.kernel.loadProjection(running.sessionId))
          .runs[running.runId]!
          .state,
      AgentRunState.suspending,
    );
  });
}

Matcher _commandError(AgentErrorCode code) =>
    isA<AgentCommandError>().having((error) => error.code, 'code', code);
