import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';
import '../support/ownership_fixture.dart';
import '../support/running_kernel_fixture.dart';

void main() {
  test('DeferredOperation defaults to Run owner with deadline and policy',
      () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final deadline = DateTime.utc(2026, 7, 25);
    final created = await fixture.kernel.createDeferredOperation(
      CreateDeferredOperationCommand(
        commandId: createDeferredCommandId,
        handle: running.handle,
        runId: running.runId,
        deadlineAt: deadline,
        cancellationPolicy: DeferredCancellationPolicy.transferToSession,
      ),
    );
    final operation = (await fixture.kernel.loadProjection(running.sessionId))
        .deferredOperations[created.deferredOperationId]!;

    expect(operation.owner, DeferredOperationOwner.run);
    expect(operation.deadlineAt, deadline);
    expect(
      operation.cancellationPolicy,
      DeferredCancellationPolicy.transferToSession,
    );
    expect(operation.state, DeferredOperationState.pending);
  });

  test('DeferredOperation records an explicit terminal result', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final created = await fixture.kernel.createDeferredOperation(
      CreateDeferredOperationCommand(
        commandId: createDeferredCommandId,
        handle: running.handle,
        runId: running.runId,
        deadlineAt: DateTime.utc(2026, 7, 25),
        cancellationPolicy: DeferredCancellationPolicy.cancelWithOwner,
      ),
    );
    await fixture.kernel.recordDeferredOperationOutcome(
      RecordDeferredOperationOutcomeCommand(
        commandId: deferredOutcomeCommandId,
        handle: created.sessionHandle!,
        runId: running.runId,
        deferredOperationId: created.deferredOperationId!,
        outcome: DeferredOperationOutcome.completed,
      ),
    );
    final operation = (await fixture.kernel.loadProjection(running.sessionId))
        .deferredOperations[created.deferredOperationId]!;

    expect(operation.state, DeferredOperationState.completed);
    expect(operation.terminalResult, 'completed');
    expect(operation.terminalDigest, isNotNull);
  });

  test('same transfer command is idempotent', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final created = await fixture.kernel.createDeferredOperation(
      CreateDeferredOperationCommand(
        commandId: createDeferredCommandId,
        handle: running.handle,
        runId: running.runId,
        deadlineAt: DateTime.utc(2026, 7, 25),
        cancellationPolicy: DeferredCancellationPolicy.transferToSession,
      ),
    );
    final command = TransferDeferredOperationCommand(
      commandId: transferDeferredCommandId,
      handle: created.sessionHandle!,
      runId: running.runId,
      deferredOperationId: created.deferredOperationId!,
    );
    final first = await fixture.kernel.transferDeferredOperation(command);
    final retry = await fixture.kernel.transferDeferredOperation(command);

    expect(retry.toJson(), first.toJson());
    expect(
      (await fixture.kernel.loadProjection(running.sessionId))
          .deferredOperations[created.deferredOperationId]!
          .owner,
      DeferredOperationOwner.session,
    );
  });
}
