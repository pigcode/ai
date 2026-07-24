import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/availability.dart';
import '../common/errors.dart';
import 'capabilities.dart';
import 'models.dart';
import 'version.dart';

enum VmServiceConnectionLifecycle {
  created,
  versionPending,
  versionNegotiated,
  protocolsPending,
  ready,
  closed,
}

final class VmServicePendingRequest {
  VmServicePendingRequest._({
    required this.id,
    required this.method,
    required this.params,
    required this.connectionId,
  });

  final String id;
  final String method;
  final JsonObject params;
  final int connectionId;
  bool _done = false;
  Object? _failure;

  bool get done => _done;
  Object? get failure => _failure;

  void _complete([Object? failure]) {
    if (_done) {
      throw const ToolingProtocolStateError(
        'vm_service_request_completed_twice',
        'VM Service request completed more than once.',
      );
    }
    _done = true;
    _failure = failure;
  }
}

final class VmServiceConnection {
  VmServiceConnection() : connectionId = _nextConnectionId++;

  static int _nextConnectionId = 1;

  final int connectionId;
  VmServiceConnectionLifecycle _lifecycle =
      VmServiceConnectionLifecycle.created;
  int _nextRequestId = 1;
  final Map<String, VmServicePendingRequest> _pending =
      <String, VmServicePendingRequest>{};
  final Map<String, String> _tombstones = <String, String>{};
  VmServiceWireVersion? _wireVersion;
  VmServiceCapabilitySnapshot? _capabilities;

  VmServiceConnectionLifecycle get lifecycle => _lifecycle;

  VmServiceCapabilitySnapshot get capabilities {
    final value = _capabilities;
    if (value == null) {
      throw const ToolingProtocolStateError(
        'vm_service_capabilities_unavailable',
        'VM Service capabilities require both handshake RPCs.',
      );
    }
    return value;
  }

  Iterable<VmServicePendingRequest> get pendingRequests =>
      List<VmServicePendingRequest>.unmodifiable(_pending.values);

  VmServicePendingRequest beginVersionQuery() {
    if (_lifecycle != VmServiceConnectionLifecycle.created) {
      throw const ToolingProtocolStateError(
        'vm_service_version_already_started',
        'VM Service getVersion is allowed exactly once and first.',
      );
    }
    _lifecycle = VmServiceConnectionLifecycle.versionPending;
    return _allocate('getVersion', const <String, Object?>{});
  }

  void completeVersionQuery(String id, Map<String, Object?> result) {
    if (_lifecycle != VmServiceConnectionLifecycle.versionPending) {
      throw const ToolingProtocolStateError(
        'vm_service_version_response_unexpected',
        'VM Service version response is not expected.',
      );
    }
    final pending = _expectPending(id, 'getVersion');
    try {
      VmServiceModelRegistry.instance.validateResult(
        'getVersion',
        result,
      );
      final version = VmServiceWireVersion(
        result['major']! as int,
        result['minor']! as int,
      );
      if (version.major != vmServiceCurrentRuntimeVersion.major) {
        throw const ToolingVersionError(
          'vm_service_major_unsupported',
          'VM Service protocol major is unsupported.',
        );
      }
      if (!vmServiceVersionPolicy.supports(version)) {
        throw const ToolingVersionError(
          'vm_service_version_unsupported',
          'VM Service protocol is outside the pinned supported range.',
        );
      }
      _wireVersion = version;
    } on DartToolingError catch (error) {
      _completePending(pending, error);
      _lifecycle = VmServiceConnectionLifecycle.closed;
      rethrow;
    }
    _completePending(pending);
    _lifecycle = VmServiceConnectionLifecycle.versionNegotiated;
  }

  VmServicePendingRequest beginSupportedProtocolsQuery() {
    if (_lifecycle != VmServiceConnectionLifecycle.versionNegotiated) {
      throw const ToolingProtocolStateError(
        'vm_service_protocols_out_of_order',
        'VM Service getSupportedProtocols must follow getVersion.',
      );
    }
    _lifecycle = VmServiceConnectionLifecycle.protocolsPending;
    return _allocate(
      'getSupportedProtocols',
      const <String, Object?>{},
    );
  }

  void completeSupportedProtocolsQuery(
    String id,
    Map<String, Object?> result,
  ) {
    if (_lifecycle != VmServiceConnectionLifecycle.protocolsPending ||
        _wireVersion == null) {
      throw const ToolingProtocolStateError(
        'vm_service_protocols_response_unexpected',
        'VM Service supported protocols response is not expected.',
      );
    }
    final pending = _expectPending(id, 'getSupportedProtocols');
    try {
      VmServiceModelRegistry.instance.validateResult(
        pending.method,
        result,
        version: _wireVersion!,
      );
      _capabilities = VmServiceCapabilitySnapshot.fromResult(
        connectionId: connectionId,
        wireVersion: _wireVersion!,
        result: result,
      );
    } on DartToolingError catch (error) {
      _completePending(pending, error);
      _lifecycle = VmServiceConnectionLifecycle.closed;
      rethrow;
    }
    _completePending(pending);
    _lifecycle = VmServiceConnectionLifecycle.ready;
  }

  VmServicePendingRequest beginRequest(
    String method, {
    required Map<String, Object?> params,
  }) {
    if (_lifecycle != VmServiceConnectionLifecycle.ready) {
      throw const ToolingProtocolStateError(
        'vm_service_request_out_of_state',
        'Ordinary VM Service RPCs require ready state.',
      );
    }
    if (_controlMethods.contains(method)) {
      throw const ToolingProtocolStateError(
        'vm_service_control_rpc_repeated',
        'VM Service handshake RPC cannot be repeated.',
      );
    }
    if (!capabilities.supportsRpc(method)) {
      if (VmServiceModelRegistry.instance.currentRpcNames.contains(method)) {
        throw ToolingVersionError(
          'vm_service_method_unavailable',
          'VM Service RPC is unavailable in ${capabilities.wireVersion}.',
        );
      }
      throw const ToolingCapabilityError(
        'vm_service_method_unsupported',
        'VM Service did not advertise support for this RPC.',
      );
    }
    final validated = VmServiceModelRegistry.instance.validateParams(
      method,
      params,
      version: capabilities.wireVersion,
    );
    return _allocate(method, validated);
  }

  void completeResponse({
    required String id,
    required String method,
    Object? result,
    Object? failure,
  }) {
    final pending = _expectPending(id, method);
    if (failure == null) {
      VmServiceModelRegistry.instance.validateResult(
        method,
        result,
        version: capabilities.wireVersion,
      );
    }
    _completePending(pending, failure);
  }

  void assertCurrentSnapshot(VmServiceCapabilitySnapshot snapshot) {
    if (_capabilities == null ||
        snapshot.connectionId != connectionId ||
        snapshot.generation != _capabilities!.generation) {
      throw const ToolingProtocolStateError(
        'vm_service_capability_snapshot_stale',
        'VM Service capability snapshot belongs to another connection.',
      );
    }
  }

  void close() {
    if (_lifecycle == VmServiceConnectionLifecycle.closed) {
      return;
    }
    const failure = ToolingProtocolStateError(
      'vm_service_connection_closed',
      'VM Service connection closed before the request completed.',
    );
    for (final pending in _pending.values.toList()) {
      _completePending(pending, failure);
    }
    _capabilities = null;
    _wireVersion = null;
    _lifecycle = VmServiceConnectionLifecycle.closed;
  }

  VmServiceConnection reconnect() {
    close();
    return VmServiceConnection();
  }

  VmServicePendingRequest _allocate(
    String method,
    Map<String, Object?> params,
  ) {
    final request = VmServicePendingRequest._(
      id: '${_nextRequestId++}',
      method: method,
      params: freezeJsonObject(params),
      connectionId: connectionId,
    );
    _pending[request.id] = request;
    return request;
  }

  VmServicePendingRequest _expectPending(String id, String method) {
    if (_tombstones.containsKey(id)) {
      throw const ToolingProtocolStateError(
        'vm_service_response_tombstoned',
        'VM Service response matches an already completed request.',
      );
    }
    final request = _pending[id];
    if (request == null) {
      throw const ToolingProtocolStateError(
        'vm_service_response_unknown',
        'VM Service response does not match a pending request.',
      );
    }
    if (request.method != method) {
      throw const ToolingProtocolStateError(
        'vm_service_response_method_mismatch',
        'VM Service response method does not match its request id.',
      );
    }
    return request;
  }

  void _completePending(
    VmServicePendingRequest pending, [
    Object? failure,
  ]) {
    _pending.remove(pending.id);
    pending._complete(failure);
    _tombstones[pending.id] = pending.method;
  }
}

const _controlMethods = <String>{
  'getVersion',
  'getSupportedProtocols',
};
