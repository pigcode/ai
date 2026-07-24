enum ModelRunState {
  pending,
  inProgress,
  suspending,
  suspended,
  resuming,
  cancelling,
  reconciling,
  completed,
  failed,
  cancelled,
  interrupted;

  bool get isTerminal => switch (this) {
        completed || failed || cancelled || interrupted => true,
        _ => false,
      };
}

enum ModelRunSignal {
  started,
  startFailed,
  cancelRequested,
  suspendRequested,
  suspended,
  resumeRequested,
  reconciling,
  completed,
  failed,
  cancelled,
  interrupted,
}

final class RunStateModel {
  const RunStateModel();

  List<ModelRunSignal> legalSignals(ModelRunState state) => <ModelRunSignal>[
        for (final signal in ModelRunSignal.values)
          if (_tryTransition(state, signal) != null) signal,
      ];

  ModelRunState transition(ModelRunState state, ModelRunSignal signal) {
    final next = switch ((state, signal)) {
      (ModelRunState.pending, ModelRunSignal.started) =>
        ModelRunState.inProgress,
      (ModelRunState.pending, ModelRunSignal.startFailed) =>
        ModelRunState.failed,
      (
        ModelRunState.pending ||
            ModelRunState.inProgress ||
            ModelRunState.suspending ||
            ModelRunState.suspended ||
            ModelRunState.resuming ||
            ModelRunState.reconciling,
        ModelRunSignal.cancelRequested
      ) =>
        ModelRunState.cancelling,
      (ModelRunState.inProgress, ModelRunSignal.suspendRequested) =>
        ModelRunState.suspending,
      (
        ModelRunState.suspending || ModelRunState.resuming,
        ModelRunSignal.suspended
      ) =>
        ModelRunState.suspended,
      (ModelRunState.suspended, ModelRunSignal.resumeRequested) =>
        ModelRunState.resuming,
      (
        ModelRunState.pending ||
            ModelRunState.inProgress ||
            ModelRunState.suspending ||
            ModelRunState.resuming ||
            ModelRunState.cancelling,
        ModelRunSignal.reconciling
      ) =>
        ModelRunState.reconciling,
      (
        ModelRunState.suspending ||
            ModelRunState.resuming ||
            ModelRunState.reconciling,
        ModelRunSignal.started
      ) =>
        ModelRunState.inProgress,
      (
        ModelRunState.inProgress ||
            ModelRunState.suspending ||
            ModelRunState.resuming ||
            ModelRunState.cancelling ||
            ModelRunState.reconciling,
        ModelRunSignal.completed
      ) =>
        ModelRunState.completed,
      (
        ModelRunState.inProgress ||
            ModelRunState.suspending ||
            ModelRunState.resuming ||
            ModelRunState.cancelling ||
            ModelRunState.reconciling,
        ModelRunSignal.failed
      ) =>
        ModelRunState.failed,
      (
        ModelRunState.cancelling || ModelRunState.reconciling,
        ModelRunSignal.cancelled
      ) =>
        ModelRunState.cancelled,
      (
        ModelRunState.inProgress ||
            ModelRunState.cancelling ||
            ModelRunState.reconciling,
        ModelRunSignal.interrupted
      ) =>
        ModelRunState.interrupted,
      _ => throw StateError('Illegal Run transition: $state + $signal'),
    };
    return next;
  }

  ModelRunState? _tryTransition(
    ModelRunState state,
    ModelRunSignal signal,
  ) {
    try {
      return transition(state, signal);
    } on StateError {
      return null;
    }
  }
}
