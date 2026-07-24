import 'capabilities.dart';
import 'errors.dart';
import 'method.dart';
import 'registration.dart';

enum LspConnectionLifecycle {
  created,
  initializePending,
  initialized,
  shutdownPending,
  shutdown,
  exited,
  closed,
}

/// One outbound request owned by a single connection identity.
final class LspPendingRequest {
  LspPendingRequest._({
    required this.id,
    required this.method,
    required this.connectionId,
  });

  final int id;
  final String method;
  final int connectionId;
  bool _done = false;
  Object? _failure;

  bool get done => _done;
  Object? get failure => _failure;

  void _complete([Object? failure]) {
    if (_done) {
      throw const LspStateException(
        'lsp_request_already_completed',
        'LSP request completed more than once.',
      );
    }
    _done = true;
    _failure = failure;
  }
}

/// Deterministic LSP lifecycle, request, and capability state.
final class LspConnection {
  LspConnection() : connectionId = _nextConnectionId++;

  static int _nextConnectionId = 1;

  final int connectionId;
  LspConnectionLifecycle _lifecycle = LspConnectionLifecycle.created;
  bool _initializeStarted = false;
  LspCapabilitySnapshot? _initializeSnapshot;
  LspCapabilitySnapshot? _capabilities;
  int _nextRequestId = 1;
  final Map<int, LspPendingRequest> _pending = <int, LspPendingRequest>{};

  LspConnectionLifecycle get lifecycle => _lifecycle;
  int get nextRequestId => _nextRequestId;
  Iterable<LspPendingRequest> get pendingRequests =>
      List<LspPendingRequest>.unmodifiable(_pending.values);

  LspCapabilitySnapshot get capabilities {
    final snapshot = _capabilities;
    if (snapshot == null) {
      throw const LspStateException(
        'lsp_capabilities_unavailable',
        'LSP capabilities are unavailable before initialized.',
      );
    }
    return snapshot;
  }

  void beginInitialize() {
    if (_initializeStarted || _lifecycle != LspConnectionLifecycle.created) {
      throw const LspStateException(
        'lsp_initialize_already_started',
        'LSP initialize is allowed exactly once per connection.',
      );
    }
    _initializeStarted = true;
    _lifecycle = LspConnectionLifecycle.initializePending;
  }

  void completeInitialize(Map<String, Object?> serverCapabilities) {
    if (_lifecycle != LspConnectionLifecycle.initializePending ||
        _initializeSnapshot != null) {
      throw const LspStateException(
        'lsp_initialize_response_unexpected',
        'LSP initialize response is not expected in the current state.',
      );
    }
    _initializeSnapshot = LspCapabilitySnapshot.fromInitialize(
      connectionId: connectionId,
      generation: 1,
      serverCapabilities: serverCapabilities,
    );
  }

  void sendInitialized() {
    final snapshot = _initializeSnapshot;
    if (_lifecycle != LspConnectionLifecycle.initializePending ||
        snapshot == null) {
      throw const LspStateException(
        'lsp_initialized_out_of_order',
        'LSP initialized requires a successful initialize response.',
      );
    }
    _capabilities = snapshot;
    _initializeSnapshot = null;
    _lifecycle = LspConnectionLifecycle.initialized;
  }

  LspPendingRequest beginRequest(String method) {
    if (_lifecycle != LspConnectionLifecycle.initialized) {
      throw const LspStateException(
        'lsp_request_out_of_state',
        'Ordinary LSP requests require initialized state.',
      );
    }
    final descriptor = lspMethodsByName[method];
    if (descriptor == null ||
        descriptor.kind != LspMethodKind.request ||
        descriptor.direction == LspMessageDirection.serverToClient) {
      throw LspStateException(
        'lsp_outbound_request_invalid',
        'Method is not a client-originated LSP request: $method.',
      );
    }
    if (!capabilities.supportsMethod(method)) {
      throw LspCapabilityException(
        'lsp_capability_unavailable',
        'Server did not advertise this optional LSP operation.',
        method: method,
      );
    }
    final pending = LspPendingRequest._(
      id: _nextRequestId++,
      method: method,
      connectionId: connectionId,
    );
    _pending[pending.id] = pending;
    return pending;
  }

  void completeRequest(int requestId, {Object? failure}) {
    final pending = _pending.remove(requestId);
    if (pending == null) {
      throw const LspStateException(
        'lsp_request_unknown',
        'LSP response does not match a pending request.',
      );
    }
    pending._complete(failure);
  }

  void beginShutdown() {
    if (_lifecycle != LspConnectionLifecycle.initialized) {
      throw const LspStateException(
        'lsp_shutdown_out_of_order',
        'LSP shutdown requires initialized state.',
      );
    }
    _lifecycle = LspConnectionLifecycle.shutdownPending;
  }

  void completeShutdown() {
    if (_lifecycle != LspConnectionLifecycle.shutdownPending) {
      throw const LspStateException(
        'lsp_shutdown_response_unexpected',
        'LSP shutdown response is not expected in the current state.',
      );
    }
    _lifecycle = LspConnectionLifecycle.shutdown;
  }

  void sendExit() {
    if (_lifecycle != LspConnectionLifecycle.shutdown) {
      throw const LspStateException(
        'lsp_exit_out_of_order',
        'LSP exit requires a completed shutdown.',
      );
    }
    _lifecycle = LspConnectionLifecycle.exited;
  }

  void registerCapability(LspDynamicRegistration registration) {
    _requireInitialized('register a dynamic capability');
    _capabilities = capabilities.register(registration);
  }

  void unregisterCapability(String registrationId) {
    _requireInitialized('unregister a dynamic capability');
    _capabilities = capabilities.unregister(registrationId);
  }

  void assertCurrentSnapshot(LspCapabilitySnapshot snapshot) {
    if (snapshot.connectionId != connectionId ||
        _capabilities == null ||
        snapshot.generation != _capabilities!.generation) {
      throw const LspStateException(
        'lsp_capability_snapshot_stale',
        'LSP capability snapshot belongs to an old connection generation.',
      );
    }
  }

  void close() {
    if (_lifecycle == LspConnectionLifecycle.closed) {
      return;
    }
    const failure = LspStateException(
      'lsp_connection_closed',
      'LSP connection closed before the request completed.',
    );
    for (final pending in _pending.values) {
      pending._complete(failure);
    }
    _pending.clear();
    _initializeSnapshot = null;
    _capabilities = null;
    _lifecycle = LspConnectionLifecycle.closed;
  }

  LspConnection reconnect() {
    close();
    return LspConnection();
  }

  void _requireInitialized(String action) {
    if (_lifecycle != LspConnectionLifecycle.initialized) {
      throw LspStateException(
        'lsp_operation_out_of_state',
        'LSP initialized state is required to $action.',
      );
    }
  }
}
