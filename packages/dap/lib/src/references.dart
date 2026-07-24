import 'debug_state.dart';
import 'errors.dart';

enum DapReferenceKind {
  frame,
  scope,
  variables,
}

final class DapBoundReference {
  const DapBoundReference({
    required this.reference,
    required this.kind,
    required this.connectionId,
    required this.sessionGeneration,
    required this.pauseGeneration,
  });

  final int reference;
  final DapReferenceKind kind;
  final int connectionId;
  final int sessionGeneration;
  final int pauseGeneration;
}

final class DapReferenceRegistry {
  final Map<int, DapBoundReference> _references = <int, DapBoundReference>{};

  void bind({
    required int reference,
    required DapReferenceKind kind,
    required int connectionId,
    required int sessionGeneration,
    required int pauseGeneration,
  }) {
    if (reference <= 0 || _references.containsKey(reference)) {
      throw const DapDebugStateException(
        'dap_reference_invalid_or_duplicate',
        'DAP reference must be positive and unique.',
      );
    }
    _references[reference] = DapBoundReference(
      reference: reference,
      kind: kind,
      connectionId: connectionId,
      sessionGeneration: sessionGeneration,
      pauseGeneration: pauseGeneration,
    );
  }

  DapBoundReference resolve(
    int reference, {
    required DapDebugState state,
  }) {
    final bound = _references[reference];
    if (bound == null) {
      throw const DapDebugStateException(
        'dap_reference_unknown',
        'Unknown DAP reference.',
      );
    }
    if (state.disconnected ||
        bound.connectionId != state.connectionId ||
        bound.sessionGeneration != state.sessionGeneration ||
        bound.pauseGeneration != state.pauseGeneration) {
      throw const DapDebugStateException(
        'dap_reference_stale',
        'DAP reference belongs to a stale session or pause generation.',
      );
    }
    return bound;
  }
}
