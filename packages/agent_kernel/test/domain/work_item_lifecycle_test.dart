import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';
import '../support/running_kernel_fixture.dart';
import '../support/work_policy_fixture.dart';

void main() {
  test('managed WorkItem follows policy before execution and terminal',
      () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final request = workRequest(running.runId);
    final policy = workPolicy(effectControl: EffectControl.managed);
    final proposed = await fixture.kernel.proposeWorkItem(
      ProposeWorkItemCommand(
        commandId: proposeWorkCommandId,
        handle: running.handle,
        runId: running.runId,
        request: request,
        policyVersion: policy.version,
      ),
      policy: policy,
    );
    expect(
      (await fixture.kernel.loadProjection(running.sessionId))
          .workItems[proposed.workItemId]!
          .state,
      WorkItemState.policyEvaluated,
    );

    final executing = await fixture.kernel.startWorkExecution(
      StartWorkExecutionCommand(
        commandId: startWorkCommandId,
        handle: proposed.sessionHandle!,
        runId: running.runId,
        workItemId: proposed.workItemId!,
      ),
    );
    final completed = await fixture.kernel.recordWorkItemOutcome(
      RecordWorkItemOutcomeCommand(
        commandId: outcomeWorkCommandId,
        handle: executing.sessionHandle!,
        runId: running.runId,
        workItemId: proposed.workItemId!,
        outcome: WorkItemOutcome.succeeded,
      ),
    );

    expect(
      (await fixture.kernel.loadProjection(running.sessionId))
          .workItems[completed.workItemId]!
          .state,
      WorkItemState.succeeded,
    );
  });

  test('interceptable WorkItem approval is binding-checked', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final request = workRequest(
      running.runId,
      effectControl: EffectControl.interceptable,
    );
    final policy = workPolicy(
      effectControl: EffectControl.interceptable,
      requireApproval: true,
    );
    final proposed = await fixture.kernel.proposeWorkItem(
      ProposeWorkItemCommand(
        commandId: proposeWorkCommandId,
        handle: running.handle,
        runId: running.runId,
        request: request,
        policyVersion: policy.version,
      ),
      policy: policy,
    );
    final binding = approvalBinding(
      request,
      proposed.workItemId!,
      policy.version,
    );

    final resolved = await fixture.kernel.resolveApproval(
      ResolveApprovalCommand(
        commandId: resolveApprovalCommandId,
        handle: proposed.sessionHandle!,
        runId: running.runId,
        approvalId: proposed.approvalId!,
        binding: binding,
        decision: ApprovalDecision.approve,
        currentPrincipal: request.principal,
      ),
    );
    expect(
      (await fixture.kernel.loadProjection(running.sessionId))
          .workItems[proposed.workItemId]!
          .state,
      WorkItemState.approved,
    );
    await fixture.kernel.startWorkExecution(
      StartWorkExecutionCommand(
        commandId: startWorkCommandId,
        handle: resolved.sessionHandle!,
        runId: running.runId,
        workItemId: proposed.workItemId!,
      ),
    );
  });

  test('deny-by-default reaches denied and cannot execute', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    const policy = DenyByDefaultPolicy();
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
    expect(
      (await fixture.kernel.loadProjection(running.sessionId))
          .workItems[proposed.workItemId]!
          .state,
      WorkItemState.denied,
    );

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
  });

  test('cancel resolves pending approval explicitly', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final request = workRequest(running.runId);
    final policy = workPolicy(
      effectControl: EffectControl.managed,
      requireApproval: true,
    );
    final proposed = await fixture.kernel.proposeWorkItem(
      ProposeWorkItemCommand(
        commandId: proposeWorkCommandId,
        handle: running.handle,
        runId: running.runId,
        request: request,
        policyVersion: policy.version,
      ),
      policy: policy,
    );
    await fixture.kernel.cancelRun(
      CancelRunCommand(
        commandId: cancelCommandId,
        handle: proposed.sessionHandle!,
        runId: running.runId,
      ),
    );

    final projection = await fixture.kernel.loadProjection(running.sessionId);
    expect(
      projection.approvals[proposed.approvalId]!.state,
      ApprovalState.denied,
    );
    expect(
      projection.workItems[proposed.workItemId]!.state,
      WorkItemState.denied,
    );
  });
}

Matcher _commandError(AgentErrorCode code) =>
    isA<AgentCommandError>().having((error) => error.code, 'code', code);
