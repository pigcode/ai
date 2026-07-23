import 'dart:async';
import 'dart:collection';

import '../cancellation.dart';
import '../diagnostics.dart';
import '../errors.dart';
import '../json_value.dart';
import '../limits.dart';
import '../transport.dart';
import 'id.dart';
import 'message.dart';

typedef JsonRpcRequestHandler = FutureOr<JsonValue> Function(
  JsonRpcRequest request,
  ProtocolCancellationSignal cancellation,
);

typedef JsonRpcNotificationHandler = FutureOr<void> Function(
  JsonRpcNotification notification,
);

/// One outbound request whose wire identifier is available immediately.
final class JsonRpcPendingRequest {
  const JsonRpcPendingRequest({
    required this.id,
    required this.response,
  });

  final JsonRpcId id;
  final Future<JsonValue> response;
}

/// Correlates outbound JSON-RPC requests and dispatches inbound calls.
final class JsonRpcPeer {
  JsonRpcPeer({
    required this.transport,
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
    Map<String, JsonRpcRequestHandler> requestHandlers =
        const <String, JsonRpcRequestHandler>{},
    Map<String, JsonRpcNotificationHandler> notificationHandlers =
        const <String, JsonRpcNotificationHandler>{},
  })  : limits = limits ?? ProtocolLimits.defaults,
        requestHandlers =
            Map<String, JsonRpcRequestHandler>.unmodifiable(requestHandlers),
        notificationHandlers =
            Map<String, JsonRpcNotificationHandler>.unmodifiable(
          notificationHandlers,
        ) {
    this.diagnostics = diagnostics ??
        BoundedProtocolDiagnostics(maxEntries: this.limits.maxDiagnostics);
    if (this.diagnostics.capacity > this.limits.maxDiagnostics) {
      throw ArgumentError.value(
        this.diagnostics.capacity,
        'diagnostics.capacity',
        'Must not exceed limits.maxDiagnostics.',
      );
    }
    _subscription = transport.incomingMessages.listen(
      _handleMessage,
      onError: _handleTransportError,
      onDone: _handleTransportDone,
    );
  }

  final ProtocolMessageTransport<JsonRpcMessage> transport;
  final ProtocolLimits limits;
  late final ProtocolDiagnosticSink diagnostics;
  final Map<String, JsonRpcRequestHandler> requestHandlers;
  final Map<String, JsonRpcNotificationHandler> notificationHandlers;

  final Map<JsonRpcId, _PendingRequest> _pending =
      <JsonRpcId, _PendingRequest>{};
  final LinkedHashMap<JsonRpcId, _TombstoneReason> _tombstones =
      LinkedHashMap<JsonRpcId, _TombstoneReason>();
  final Map<JsonRpcId, ProtocolCancellationSource> _inboundCancellations =
      <JsonRpcId, ProtocolCancellationSource>{};
  final Completer<void> _done = Completer<void>();
  late final StreamSubscription<JsonRpcMessage> _subscription;
  Future<void> _outboundTail = Future<void>.value();
  Future<void>? _closeFuture;
  _PeerState _state = _PeerState.open;
  var _nextRequestId = 1;
  var _outboundMessageCount = 0;
  var _activeInboundRequests = 0;

  int get pendingRequestCount => _pending.length;
  int get tombstoneCount => _tombstones.length;
  int get activeInboundRequestCount => _activeInboundRequests;
  Future<void> get done => _done.future;
  bool get isClosed => _state == _PeerState.closed;

  /// Sends one request with a connection-unique generated identifier.
  Future<JsonValue> request(
    String method, {
    JsonValue params,
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async {
    return startRequest(
      method,
      params: params,
      cancellation: cancellation,
      timeout: timeout,
    ).response;
  }

  /// Starts one request and exposes its generated ID for wire adapters.
  JsonRpcPendingRequest startRequest(
    String method, {
    JsonValue params,
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) {
    _ensureOpen();
    if (timeout != null && timeout.isNegative) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Must not be negative.',
      );
    }
    if (cancellation?.isCancelled ?? false) {
      throw ProtocolCancellationException(reason: cancellation?.reason);
    }
    if (_pending.length >= limits.maxPendingRequests) {
      throw const JsonRpcPeerException(
        'json_rpc_pending_limit',
        'Pending JSON-RPC request limit reached.',
      );
    }
    if (_nextRequestId > _maximumSafeRequestId) {
      throw const JsonRpcPeerException(
        'json_rpc_id_exhausted',
        'JSON-RPC request identifier space is exhausted.',
      );
    }

    final id = JsonRpcIntegerId(_nextRequestId++);
    final message = JsonRpcRequest(
      id: id,
      method: method,
      params: params,
    );
    final pending = _PendingRequest(id);
    _pending[id] = pending;
    if (cancellation != null) {
      pending.cancellationRegistration = cancellation.onCancel(
        (reason) => _cancelPending(id, pending, reason),
      );
    }
    if (timeout != null) {
      pending.timer = Timer(
        timeout,
        () => _timeoutPending(id, pending),
      );
    }

    unawaited(_sendPendingRequest(message, pending));
    return JsonRpcPendingRequest(
      id: id,
      response: pending.completer.future,
    );
  }

  /// Sends one notification after applying outbound queue backpressure.
  Future<void> notify(String method, {JsonValue params}) async {
    _ensureOpen();
    final message = JsonRpcNotification(method: method, params: params);
    try {
      await _enqueueSend(message);
    } on ProtocolException {
      rethrow;
    } on Object catch (error) {
      throw ProtocolTransportException(
        'transport_send_failed',
        'Caller-supplied message transport failed to send.',
        cause: error,
      );
    }
  }

  /// Requests cancellation of one currently executing inbound request.
  bool cancelInboundRequest(JsonRpcId id, [Object? reason]) {
    final source = _inboundCancellations[id];
    return source?.cancel(reason) ?? false;
  }

  /// Closes this logical peer. It never owns or terminates a process.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_state == _PeerState.closed) {
      return;
    }
    _state = _PeerState.closing;
    _failAllPending(
      const ProtocolTransportException(
        'transport_closed',
        'JSON-RPC peer closed before a response arrived.',
      ),
    );
    for (final source in _inboundCancellations.values) {
      source.cancel('peer closed');
    }
    _inboundCancellations.clear();
    await _subscription.cancel();
    try {
      await transport.close();
    } on Object catch (error) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'transport_close_failed',
          message: 'Caller-supplied transport failed while closing.',
          details: <String, Object?>{
            'errorType': error.runtimeType.toString(),
          },
        ),
      );
    }
    _state = _PeerState.closed;
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  Future<void> _sendPendingRequest(
    JsonRpcRequest message,
    _PendingRequest pending,
  ) async {
    try {
      await _enqueueSend(message);
    } on Object catch (error) {
      if (!identical(_pending[message.id], pending)) {
        return;
      }
      _pending.remove(message.id);
      pending.dispose();
      _addTombstone(message.id, _TombstoneReason.sendFailed);
      if (error is ProtocolException) {
        pending.completer.completeError(error);
      } else {
        pending.completer.completeError(
          ProtocolTransportException(
            'transport_send_failed',
            'Caller-supplied message transport failed to send.',
            cause: error,
          ),
        );
      }
    }
  }

  Future<void> _enqueueSend(JsonRpcMessage message) {
    _ensureOpen();
    if (_outboundMessageCount >= limits.maxOutboundMessages) {
      throw const JsonRpcPeerException(
        'json_rpc_outbound_backpressure',
        'Outbound JSON-RPC queue limit reached.',
      );
    }
    _outboundMessageCount += 1;
    final operation = _outboundTail.then((_) async {
      _ensureOpen();
      await transport.sendMessage(message);
    });
    _outboundTail = operation.then<void>(
      (_) {
        _outboundMessageCount -= 1;
      },
      onError: (_, __) {
        _outboundMessageCount -= 1;
      },
    );
    return operation;
  }

  void _handleMessage(JsonRpcMessage message) {
    switch (message) {
      case JsonRpcSuccessResponse():
        _handleResponse(message);
      case JsonRpcErrorResponse():
        _handleResponse(message);
      case JsonRpcRequest():
        unawaited(_dispatchRequest(message));
      case JsonRpcNotification():
        unawaited(_dispatchNotification(message));
    }
  }

  void _handleResponse(JsonRpcMessage message) {
    final id = switch (message) {
      JsonRpcSuccessResponse(:final id) => id,
      JsonRpcErrorResponse(:final id) => id,
      _ => throw StateError('Expected a JSON-RPC response.'),
    };
    final pending = _pending.remove(id);
    if (pending == null) {
      final reason = _tombstones[id];
      _diagnose(
        ProtocolDiagnostic(
          code: reason == _TombstoneReason.completed
              ? 'duplicate_response'
              : reason == null
                  ? 'unknown_response'
                  : 'late_response',
          message: reason == _TombstoneReason.completed
              ? 'Duplicate JSON-RPC response ignored.'
              : reason == null
                  ? 'Response for an unknown JSON-RPC id ignored.'
                  : 'Late JSON-RPC response ignored.',
          requestId: id,
        ),
      );
      return;
    }

    pending.dispose();
    _addTombstone(id, _TombstoneReason.completed);
    switch (message) {
      case JsonRpcSuccessResponse(:final result):
        pending.completer.complete(result);
      case JsonRpcErrorResponse(:final error):
        pending.completer.completeError(
          JsonRpcRemoteException(
            remoteCode: error.code,
            remoteMessage: error.message,
            hasData: error.hasData,
            data: error.data,
          ),
        );
      default:
        throw StateError('Expected a JSON-RPC response.');
    }
  }

  Future<void> _dispatchRequest(JsonRpcRequest request) async {
    if (_state != _PeerState.open) {
      return;
    }
    if (_inboundCancellations.containsKey(request.id)) {
      await _sendErrorResponse(
        request.id,
        code: -32600,
        message: 'Duplicate active request id',
      );
      return;
    }
    if (_activeInboundRequests >= limits.maxInboundRequests) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'inbound_request_backpressure',
          message: 'Inbound request rejected by the concurrency limit.',
          requestId: request.id,
          method: request.method,
        ),
      );
      await _sendErrorResponse(
        request.id,
        code: -32001,
        message: 'Too many concurrent requests',
      );
      return;
    }
    final handler = requestHandlers[request.method];
    if (handler == null) {
      await _sendErrorResponse(
        request.id,
        code: -32601,
        message: 'Method not found',
      );
      return;
    }

    final cancellation = ProtocolCancellationSource();
    _inboundCancellations[request.id] = cancellation;
    _activeInboundRequests += 1;
    try {
      final result = await Future<JsonValue>.sync(
        () => handler(request, cancellation.signal),
      );
      await _safeSend(
        JsonRpcSuccessResponse(id: request.id, result: result),
        requestId: request.id,
        method: request.method,
      );
    } on JsonRpcHandlerException catch (error) {
      await _sendErrorResponse(
        request.id,
        code: error.code,
        message: error.message,
        data: error.data,
        hasData: error.hasData,
        method: request.method,
      );
    } on Object catch (error) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'request_handler_failed',
          message: 'Inbound request handler failed.',
          requestId: request.id,
          method: request.method,
          details: <String, Object?>{
            'errorType': error.runtimeType.toString(),
          },
        ),
      );
      await _sendErrorResponse(
        request.id,
        code: -32603,
        message: 'Internal error',
        method: request.method,
      );
    } finally {
      _inboundCancellations.remove(request.id);
      _activeInboundRequests -= 1;
    }
  }

  Future<void> _dispatchNotification(
    JsonRpcNotification notification,
  ) async {
    final handler = notificationHandlers[notification.method];
    if (handler == null) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'unhandled_notification',
          message: 'No handler is registered for the notification.',
          method: notification.method,
        ),
      );
      return;
    }
    try {
      await Future<void>.sync(() => handler(notification));
    } on Object catch (error) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'notification_handler_failed',
          message: 'Notification handler failed.',
          method: notification.method,
          details: <String, Object?>{
            'errorType': error.runtimeType.toString(),
          },
        ),
      );
    }
  }

  Future<void> _sendErrorResponse(
    JsonRpcId id, {
    required int code,
    required String message,
    Object? data,
    bool hasData = false,
    String? method,
  }) async {
    late final JsonRpcError error;
    try {
      error = hasData
          ? JsonRpcError(code: code, message: message, data: data)
          : JsonRpcError(code: code, message: message);
    } on Object catch (invalidData) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'invalid_handler_error_data',
          message: 'Request handler supplied non-JSON error data.',
          requestId: id,
          method: method,
          details: <String, Object?>{
            'errorType': invalidData.runtimeType.toString(),
          },
        ),
      );
      error = JsonRpcError(code: -32603, message: 'Internal error');
    }
    await _safeSend(
      JsonRpcErrorResponse(id: id, error: error),
      requestId: id,
      method: method,
    );
  }

  Future<void> _safeSend(
    JsonRpcMessage message, {
    JsonRpcId? requestId,
    String? method,
  }) async {
    if (_state != _PeerState.open) {
      return;
    }
    try {
      await _enqueueSend(message);
    } on Object catch (error) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'response_send_failed',
          message: 'Failed to send an inbound request response.',
          requestId: requestId,
          method: method,
          details: <String, Object?>{
            'errorType': error.runtimeType.toString(),
          },
        ),
      );
    }
  }

  void _cancelPending(
    JsonRpcId id,
    _PendingRequest pending,
    Object? reason,
  ) {
    if (!identical(_pending[id], pending)) {
      return;
    }
    _pending.remove(id);
    pending.dispose();
    _addTombstone(id, _TombstoneReason.cancelled);
    pending.completer.completeError(
      ProtocolCancellationException(reason: reason),
    );
  }

  void _timeoutPending(JsonRpcId id, _PendingRequest pending) {
    if (!identical(_pending[id], pending)) {
      return;
    }
    _pending.remove(id);
    pending.dispose();
    _addTombstone(id, _TombstoneReason.timedOut);
    pending.completer.completeError(const ProtocolTimeoutException());
  }

  void _failAllPending(ProtocolTransportException error) {
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final request in pending) {
      request.dispose();
      request.completer.completeError(error);
    }
  }

  void _addTombstone(JsonRpcId id, _TombstoneReason reason) {
    _tombstones.remove(id);
    _tombstones[id] = reason;
    while (_tombstones.length > limits.maxTombstones) {
      _tombstones.remove(_tombstones.keys.first);
    }
  }

  void _handleTransportError(Object error, StackTrace stackTrace) {
    _diagnose(
      ProtocolDiagnostic(
        code: 'transport_receive_failed',
        message: 'Caller-supplied transport emitted an error.',
        details: <String, Object?>{
          'errorType': error.runtimeType.toString(),
        },
      ),
    );
    _finishFromTransport(
      error is ProtocolTransportException
          ? error
          : ProtocolTransportException(
              'transport_receive_failed',
              'Caller-supplied transport emitted an error.',
              cause: error,
            ),
    );
  }

  void _handleTransportDone() {
    _finishFromTransport();
  }

  void _finishFromTransport([ProtocolTransportException? error]) {
    if (_state != _PeerState.open) {
      return;
    }
    _state = _PeerState.closed;
    _failAllPending(
      error ??
          const ProtocolTransportException(
            'transport_closed',
            'Caller-supplied transport closed before a response arrived.',
          ),
    );
    for (final source in _inboundCancellations.values) {
      source.cancel('transport closed');
    }
    _inboundCancellations.clear();
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  void _diagnose(ProtocolDiagnostic diagnostic) {
    try {
      diagnostics.add(diagnostic);
    } on Object {
      // A caller diagnostic sink cannot break protocol state transitions.
    }
  }

  void _ensureOpen() {
    if (_state != _PeerState.open) {
      throw const JsonRpcPeerException(
        'json_rpc_peer_closed',
        'JSON-RPC peer is not open.',
      );
    }
  }
}

final class _PendingRequest {
  _PendingRequest(this.id);

  final JsonRpcId id;
  final Completer<JsonValue> completer = Completer<JsonValue>();
  ProtocolCancellationRegistration? cancellationRegistration;
  Timer? timer;

  void dispose() {
    cancellationRegistration?.dispose();
    cancellationRegistration = null;
    timer?.cancel();
    timer = null;
  }
}

enum _TombstoneReason {
  completed,
  cancelled,
  timedOut,
  sendFailed,
}

enum _PeerState {
  open,
  closing,
  closed,
}

const _maximumSafeRequestId = 9007199254740991;
