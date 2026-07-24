import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';
import '../support/running_kernel_fixture.dart';
import '../support/work_policy_fixture.dart';

void main() {
  for (final effectControl in <EffectControl>[
    EffectControl.observedOnly,
    EffectControl.unknown,
  ]) {
    test('${effectControl.name} records facts without managed approval claims',
        () async {
      final fixture = KernelFixture();
      final running = await prepareRunningRun(fixture);
      const policy = DenyByDefaultPolicy();
      final proposed = await fixture.kernel.proposeWorkItem(
        ProposeWorkItemCommand(
          commandId: proposeWorkCommandId,
          handle: running.handle,
          runId: running.runId,
          request: workRequest(
            running.runId,
            effectControl: effectControl,
          ),
          policyVersion: policy.version,
        ),
        policy: policy,
      );
      expect(proposed.eventIds, hasLength(1));
      expect(proposed.approvalId, isNull);

      await expectLater(
        fixture.kernel.startWorkExecution(
          StartWorkExecutionCommand(
            commandId: startWorkCommandId,
            handle: proposed.sessionHandle!,
            runId: running.runId,
            workItemId: proposed.workItemId!,
          ),
        ),
        throwsA(_commandError(AgentErrorCode.preconditionFailed)),
      );
      final recorded = await fixture.kernel.recordWorkItemOutcome(
        RecordWorkItemOutcomeCommand(
          commandId: outcomeWorkCommandId,
          handle: proposed.sessionHandle!,
          runId: running.runId,
          workItemId: proposed.workItemId!,
          outcome: WorkItemOutcome.succeeded,
        ),
      );
      expect(
        (await fixture.kernel.loadProjection(running.sessionId))
            .workItems[recorded.workItemId]!
            .state,
        WorkItemState.succeeded,
      );
    });
  }

  test('external success with missing result becomes outcomeUnknown', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final policy = workPolicy(effectControl: EffectControl.managed);
    final proposed = await fixture.kernel.proposeWorkItem(
      ProposeWorkItemCommand(
        commandId: proposeWorkCommandId,
        handle: running.handle,
        runId: running.runId,
        request: workRequest(running.runId),
        policyVersion: policy.version,
      ),
      policy: policy,
    );
    final executing = await fixture.kernel.startWorkExecution(
      StartWorkExecutionCommand(
        commandId: startWorkCommandId,
        handle: proposed.sessionHandle!,
        runId: running.runId,
        workItemId: proposed.workItemId!,
      ),
    );
    await fixture.kernel.recordWorkItemOutcome(
      RecordWorkItemOutcomeCommand(
        commandId: outcomeWorkCommandId,
        handle: executing.sessionHandle!,
        runId: running.runId,
        workItemId: proposed.workItemId!,
        outcome: WorkItemOutcome.succeeded,
        externalEffectSucceededButResultMissing: true,
      ),
    );

    expect(
      (await fixture.kernel.loadProjection(running.sessionId))
          .workItems[proposed.workItemId]!
          .state,
      WorkItemState.outcomeUnknown,
    );
  });
}

Matcher _commandError(AgentErrorCode code) =>
    isA<AgentCommandError>().having((error) => error.code, 'code', code);
