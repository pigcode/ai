import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/errors.dart';
import 'method.dart';
import 'models.dart';

enum DtdConnectionLifecycle {
  open,
  closed,
}

final class DtdPendingRequest {
  DtdPendingRequest._({
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
        'dtd_request_completed_twice',
        'DTD request completed more than once.',
      );
    }
    _done = true;
    _failure = failure;
  }

  @override
  String toString() => 'DtdPendingRequest(id: $id, method: $method)';
}

final class DtdConnection {
  DtdConnection() : connectionId = _nextConnectionId++;

  static int _nextConnectionId = 1;

  final int connectionId;
  DtdConnectionLifecycle _lifecycle = DtdConnectionLifecycle.open;
  int _nextRequestId = 1;
  final Map<String, DtdPendingRequest> _pending = <String, DtdPendingRequest>{};
  final Map<String, String> _tombstones = <String, String>{};

  DtdConnectionLifecycle get lifecycle => _lifecycle;

  Iterable<DtdPendingRequest> get pendingRequests =>
      List<DtdPendingRequest>.unmodifiable(_pending.values);

  DtdPendingRequest beginRequest(
    String method, {
    required Map<String, Object?> params,
  }) {
    if (_lifecycle != DtdConnectionLifecycle.open) {
      throw const ToolingProtocolStateError(
        'dtd_request_on_closed_connection',
        'DTD requests require an open connection.',
      );
    }
    final descriptor = DtdModelRegistry.instance.method(method);
    if (descriptor?.kind == DtdMethodKind.notification) {
      throw const ToolingProtocolStateError(
        'dtd_outbound_request_invalid',
        'DTD notification cannot be sent as a request.',
      );
    }
    final validated = DtdModelRegistry.instance.validateParams(method, params);
    final request = DtdPendingRequest._(
      id: '${_nextRequestId++}',
      method: method,
      params: validated,
      connectionId: connectionId,
    );
    _pending[request.id] = request;
    return request;
  }

  void completeResponse({
    required String id,
    required String method,
    Object? result,
    Object? failure,
  }) {
    if (_tombstones.containsKey(id)) {
      throw const ToolingProtocolStateError(
        'dtd_response_tombstoned',
        'DTD response matches an already completed request.',
      );
    }
    final request = _pending[id];
    if (request == null) {
      throw const ToolingProtocolStateError(
        'dtd_response_unknown',
        'DTD response does not match a pending request.',
      );
    }
    if (request.method != method) {
      throw const ToolingProtocolStateError(
        'dtd_response_method_mismatch',
        'DTD response method does not match its request id.',
      );
    }
    if (failure == null) {
      DtdModelRegistry.instance.validateResult(method, result);
    }
    _pending.remove(id);
    request._complete(failure);
    _tombstones[id] = method;
  }

  void close() {
    if (_lifecycle == DtdConnectionLifecycle.closed) {
      return;
    }
    const failure = ToolingProtocolStateError(
      'dtd_connection_closed',
      'DTD connection closed before the request completed.',
    );
    for (final request in _pending.values) {
      request._complete(failure);
      _tombstones[request.id] = request.method;
    }
    _pending.clear();
    _lifecycle = DtdConnectionLifecycle.closed;
  }

  DtdConnection reconnect() {
    close();
    return DtdConnection();
  }
}
