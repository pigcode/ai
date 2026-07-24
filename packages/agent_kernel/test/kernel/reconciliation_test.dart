import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';
import '../support/running_kernel_fixture.dart';

void main() {
  test('lost response reconciliation never replays prompt or effect', () {
    final plan = ReconciliationPlan.failClosed(
      ReconciliationTrigger.lostResponse,
    );

    expect(plan.replayPrompt, isFalse);
    expect(plan.retryExternalEffect, isFalse);
  });

  test('reconcile command persists explicit reconciling state', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final receipt = await fixture.kernel.reconcileRun(
      ReconcileRunCommand(
        commandId: reconcileCommandId,
        handle: running.handle,
        runId: running.runId,
        reason: 'lostResponse',
      ),
    );

    expect(receipt.eventIds, hasLength(1));
    final projection = await fixture.kernel.loadProjection(running.sessionId);
    expect(
      projection.runs[running.runId]!.state,
      AgentRunState.reconciling,
    );
  });
}
