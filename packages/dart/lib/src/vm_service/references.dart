import '../common/errors.dart';

enum VmServiceReferenceKind {
  isolate,
  object,
}

final class VmServiceExecutionState {
  VmServiceExecutionState({required this.connectionId});

  final int connectionId;
  final Map<String, int> _isolateGenerations = <String, int>{};
  final Map<String, int> _pauseGenerations = <String, int>{};
  final Set<String> _paused = <String>{};
  bool _disconnected = false;

  bool get disconnected => _disconnected;

  int isolateGeneration(String isolateId) =>
      _isolateGenerations.putIfAbsent(isolateId, () => 1);

  int pauseGeneration(String isolateId) =>
      _pauseGenerations.putIfAbsent(isolateId, () => 0);

  bool isPaused(String isolateId) => _paused.contains(isolateId);

  int pause(String isolateId) {
    _requireConnected();
    isolateGeneration(isolateId);
    final generation = pauseGeneration(isolateId) + 1;
    _pauseGenerations[isolateId] = generation;
    _paused.add(isolateId);
    return generation;
  }

  void resume(String isolateId) {
    _requireConnected();
    if (!_paused.remove(isolateId)) {
      throw const ToolingProtocolStateError(
        'vm_service_isolate_not_paused',
        'VM Service isolate is not paused.',
      );
    }
    _pauseGenerations[isolateId] = pauseGeneration(isolateId) + 1;
  }

  void exitIsolate(String isolateId) {
    _requireConnected();
    _paused.remove(isolateId);
    _pauseGenerations[isolateId] = pauseGeneration(isolateId) + 1;
    _isolateGenerations[isolateId] = isolateGeneration(isolateId) + 1;
  }

  void disconnect() {
    if (_disconnected) {
      return;
    }
    _disconnected = true;
    _paused.clear();
    for (final isolateId in _isolateGenerations.keys.toList()) {
      _isolateGenerations[isolateId] = _isolateGenerations[isolateId]! + 1;
      _pauseGenerations[isolateId] = pauseGeneration(isolateId) + 1;
    }
  }

  void _requireConnected() {
    if (_disconnected) {
      throw const ToolingProtocolStateError(
        'vm_service_execution_disconnected',
        'VM Service execution state is disconnected.',
      );
    }
  }
}

final class VmServiceBoundReference {
  const VmServiceBoundReference({
    required this.id,
    required this.kind,
    required this.connectionId,
    required this.isolateId,
    required this.isolateGeneration,
    required this.pauseGeneration,
    required this.temporary,
  });

  final String id;
  final VmServiceReferenceKind kind;
  final int connectionId;
  final String isolateId;
  final int isolateGeneration;
  final int pauseGeneration;
  final bool temporary;
}

final class VmServiceReferenceRegistry {
  final Map<String, VmServiceBoundReference> _objects =
      <String, VmServiceBoundReference>{};
  final Map<String, VmServiceBoundReference> _isolates =
      <String, VmServiceBoundReference>{};

  void bindIsolate({
    required String id,
    required VmServiceExecutionState state,
  }) {
    _requireUsableId(id);
    if (state.disconnected || _isolates.containsKey(id)) {
      throw const ToolingProtocolStateError(
        'vm_service_isolate_reference_invalid',
        'VM Service isolate reference is invalid or duplicate.',
      );
    }
    _isolates[id] = VmServiceBoundReference(
      id: id,
      kind: VmServiceReferenceKind.isolate,
      connectionId: state.connectionId,
      isolateId: id,
      isolateGeneration: state.isolateGeneration(id),
      pauseGeneration: state.pauseGeneration(id),
      temporary: false,
    );
  }

  void bindObject({
    required String id,
    required String isolateId,
    required bool temporary,
    required VmServiceExecutionState state,
  }) {
    _requireUsableId(id);
    final key = '$isolateId::$id';
    if (state.disconnected ||
        _objects.containsKey(key) ||
        temporary && !state.isPaused(isolateId)) {
      throw const ToolingProtocolStateError(
        'vm_service_object_reference_invalid',
        'VM Service object reference is invalid, duplicate, or unpaused.',
      );
    }
    _objects[key] = VmServiceBoundReference(
      id: id,
      kind: VmServiceReferenceKind.object,
      connectionId: state.connectionId,
      isolateId: isolateId,
      isolateGeneration: state.isolateGeneration(isolateId),
      pauseGeneration: state.pauseGeneration(isolateId),
      temporary: temporary,
    );
  }

  void bindResponse(
    Map<String, Object?> response, {
    required String isolateId,
    required VmServiceExecutionState state,
  }) {
    if (response['type'] == 'Sentinel') {
      throw const ToolingProtocolStateError(
        'vm_service_sentinel_not_reference',
        'VM Service Sentinel cannot be bound as an object reference.',
      );
    }
    final id = response['id'];
    if (id is! String) {
      throw const ToolingProtocolStateError(
        'vm_service_object_id_missing',
        'VM Service object response has no opaque id.',
      );
    }
    bindObject(
      id: id,
      isolateId: isolateId,
      temporary: response['fixedId'] != true,
      state: state,
    );
  }

  VmServiceBoundReference resolveObject(
    String id, {
    required VmServiceExecutionState state,
    String isolateId = 'isolates/1',
  }) {
    final reference = _objects['$isolateId::$id'];
    if (reference == null) {
      throw const ToolingProtocolStateError(
        'vm_service_object_reference_unknown',
        'VM Service object reference is unknown.',
      );
    }
    _validate(reference, state);
    return reference;
  }

  VmServiceBoundReference resolveIsolate(
    String id, {
    required VmServiceExecutionState state,
  }) {
    final reference = _isolates[id];
    if (reference == null) {
      throw const ToolingProtocolStateError(
        'vm_service_isolate_reference_unknown',
        'VM Service isolate reference is unknown.',
      );
    }
    _validate(reference, state);
    return reference;
  }

  void _validate(
    VmServiceBoundReference reference,
    VmServiceExecutionState state,
  ) {
    if (state.disconnected ||
        reference.connectionId != state.connectionId ||
        reference.isolateGeneration !=
            state.isolateGeneration(reference.isolateId) ||
        reference.temporary &&
            (reference.pauseGeneration !=
                    state.pauseGeneration(reference.isolateId) ||
                !state.isPaused(reference.isolateId))) {
      throw const ToolingProtocolStateError(
        'vm_service_reference_stale',
        'VM Service reference belongs to a stale generation.',
      );
    }
  }
}

void _requireUsableId(String id) {
  if (id.isEmpty) {
    throw const ToolingProtocolStateError(
      'vm_service_reference_id_invalid',
      'VM Service reference id must be opaque and non-empty.',
    );
  }
}
