import 'package:test/test.dart';

import '../support/run_state_model.dart';

void main() {
  const model = RunStateModel();

  test('approved happy path reaches completed exactly once', () {
    var state = ModelRunState.pending;
    state = model.transition(state, ModelRunSignal.started);
    state = model.transition(state, ModelRunSignal.completed);

    expect(state, ModelRunState.completed);
    expect(
      () => model.transition(state, ModelRunSignal.failed),
      throwsStateError,
    );
  });

  test('suspend, resume, cancellation, and reconciliation edges are explicit',
      () {
    expect(
      model.transition(
        model.transition(
          ModelRunState.inProgress,
          ModelRunSignal.suspendRequested,
        ),
        ModelRunSignal.suspended,
      ),
      ModelRunState.suspended,
    );
    expect(
      model.transition(
        model.transition(
          ModelRunState.suspended,
          ModelRunSignal.resumeRequested,
        ),
        ModelRunSignal.started,
      ),
      ModelRunState.inProgress,
    );
    expect(
      model.transition(
        ModelRunState.cancelling,
        ModelRunSignal.cancelled,
      ),
      ModelRunState.cancelled,
    );
    expect(
      model.transition(
        ModelRunState.reconciling,
        ModelRunSignal.interrupted,
      ),
      ModelRunState.interrupted,
    );
  });

  test('representative illegal edges fail closed', () {
    for (final edge in <(ModelRunState, ModelRunSignal)>[
      (ModelRunState.pending, ModelRunSignal.suspended),
      (ModelRunState.suspended, ModelRunSignal.started),
      (ModelRunState.completed, ModelRunSignal.cancelRequested),
      (ModelRunState.cancelled, ModelRunSignal.completed),
    ]) {
      expect(
        () => model.transition(edge.$1, edge.$2),
        throwsStateError,
        reason: '$edge',
      );
    }
  });
}
