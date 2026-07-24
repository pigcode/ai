import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/availability.dart';
import '../common/errors.dart';
import 'capabilities.dart';
import 'models.dart';
import 'version.dart';

enum AnalysisServerConnectionLifecycle {
  created,
  versionPending,
  ready,
  shuttingDown,
  closed,
}

/// One outbound Analysis Server request owned by a connection identity.
final class AnalysisServerPendingRequest {
  AnalysisServerPendingRequest._({
    required this.id,
    required this.method,
    required this.params,
    required this.connectionId,
  });

  final String id;
  final String method;
  final JsonObject? params;
  final int connectionId;
  bool _done = false;
  Object? _failure;

  bool get done => _done;
  Object? get failure => _failure;

  void _complete([Object? failure]) {
    if (_done) {
      throw const ToolingProtocolStateError(
        'analysis_server_request_completed_twice',
        'Analysis Server request completed more than once.',
      );
    }
    _done = true;
    _failure = failure;
  }
}

final class AnalysisServerNotificationRecord {
  const AnalysisServerNotificationRecord({
    required this.sequence,
    required this.event,
    required this.params,
  });

  final int sequence;
  final String event;
  final JsonObject params;
}

/// Ordered and bounded notification storage.
final class AnalysisServerNotificationQueue {
  AnalysisServerNotificationQueue({this.maxNotifications = 1024}) {
    if (maxNotifications <= 0) {
      throw ArgumentError.value(
        maxNotifications,
        'maxNotifications',
        'Must be positive.',
      );
    }
  }

  final int maxNotifications;
  final List<AnalysisServerNotificationRecord> _records =
      <AnalysisServerNotificationRecord>[];
  int _nextSequence = 1;

  List<AnalysisServerNotificationRecord> get records =>
      List<AnalysisServerNotificationRecord>.unmodifiable(_records);

  AnalysisServerNotificationRecord add(
    String event,
    Map<String, Object?> params,
  ) {
    if (_records.length >= maxNotifications) {
      throw const ToolingResourceLimitError(
        'analysis_server_notification_queue_full',
        'Analysis Server notification queue reached its configured limit.',
      );
    }
    final record = AnalysisServerNotificationRecord(
      sequence: _nextSequence++,
      event: event,
      params: freezeJsonObject(params),
    );
    _records.add(record);
    return record;
  }
}

/// Deterministic version, request, cancellation, and notification state.
final class AnalysisServerConnection {
  AnalysisServerConnection({int maxNotifications = 1024})
      : connectionId = _nextConnectionId++,
        notifications = AnalysisServerNotificationQueue(
          maxNotifications: maxNotifications,
        ),
        _maxNotifications = maxNotifications;

  static int _nextConnectionId = 1;

  final int connectionId;
  final AnalysisServerNotificationQueue notifications;
  final int _maxNotifications;
  AnalysisServerConnectionLifecycle _lifecycle =
      AnalysisServerConnectionLifecycle.created;
  int _nextRequestId = 1;
  final Map<String, AnalysisServerPendingRequest> _pending =
      <String, AnalysisServerPendingRequest>{};
  final Map<String, String> _tombstones = <String, String>{};
  final Set<String> _cancellationIntents = <String>{};
  final Map<String, List<Object?>> _latestErrorsByFile =
      <String, List<Object?>>{};
  AnalysisServerCapabilitySnapshot? _capabilities;
  JsonObject? _latestStatus;

  AnalysisServerConnectionLifecycle get lifecycle => _lifecycle;

  Iterable<AnalysisServerPendingRequest> get pendingRequests =>
      List<AnalysisServerPendingRequest>.unmodifiable(_pending.values);

  AnalysisServerCapabilitySnapshot get capabilities {
    final snapshot = _capabilities;
    if (snapshot == null) {
      throw const ToolingProtocolStateError(
        'analysis_server_capabilities_unavailable',
        'Analysis Server capabilities require successful version negotiation.',
      );
    }
    return snapshot;
  }

  JsonObject? get latestStatus => _latestStatus;

  Map<String, List<Object?>> get latestErrorsByFile =>
      Map<String, List<Object?>>.unmodifiable(_latestErrorsByFile);

  AnalysisServerPendingRequest beginVersionQuery() {
    if (_lifecycle != AnalysisServerConnectionLifecycle.created) {
      throw const ToolingProtocolStateError(
        'analysis_server_version_already_started',
        'Analysis Server version query is allowed exactly once.',
      );
    }
    _lifecycle = AnalysisServerConnectionLifecycle.versionPending;
    return _allocate('server.getVersion', null);
  }

  void completeVersionQuery(
    String requestId,
    Map<String, Object?> result, {
    Map<String, Object?> clientCapabilities = const <String, Object?>{},
  }) {
    if (_lifecycle != AnalysisServerConnectionLifecycle.versionPending) {
      throw const ToolingProtocolStateError(
        'analysis_server_version_response_unexpected',
        'Analysis Server version response is not expected.',
      );
    }
    final pending = _expectPending(requestId, 'server.getVersion');
    late final AnalysisServerCapabilitySnapshot snapshot;
    try {
      AnalysisServerModelRegistry.instance.validateResponseResult(
        pending.method,
        result,
        version: analysisServerMinimumApiVersion,
      );
      final version = _parseApiVersion(result['version']);
      final incompatibility = _versionIncompatibility(version);
      if (incompatibility != null) {
        throw incompatibility;
      }
      snapshot = AnalysisServerCapabilitySnapshot.negotiated(
        connectionId: connectionId,
        apiVersion: version,
        clientCapabilities: clientCapabilities,
      );
    } on DartToolingError catch (error) {
      _completePending(pending, error);
      _capabilities = null;
      _lifecycle = AnalysisServerConnectionLifecycle.closed;
      rethrow;
    }
    _completePending(pending);
    _capabilities = snapshot;
    _lifecycle = AnalysisServerConnectionLifecycle.ready;
  }

  AnalysisServerPendingRequest beginRequest(
    String method, {
    Map<String, Object?>? params,
  }) {
    if (_lifecycle != AnalysisServerConnectionLifecycle.ready) {
      throw const ToolingProtocolStateError(
        'analysis_server_request_out_of_state',
        'Ordinary Analysis Server requests require ready state.',
      );
    }
    if (_controlMethods.contains(method) ||
        _serverOriginatedRequests.contains(method)) {
      throw ToolingProtocolStateError(
        'analysis_server_outbound_request_invalid',
        'Method is not an ordinary client-originated request: $method.',
      );
    }
    return _allocateValidated(method, params);
  }

  AnalysisServerPendingRequest beginCancel(String targetId) {
    if (_lifecycle != AnalysisServerConnectionLifecycle.ready) {
      throw const ToolingProtocolStateError(
        'analysis_server_cancel_out_of_state',
        'Analysis Server cancellation requires ready state.',
      );
    }
    final target = _pending[targetId];
    if (target == null || _controlMethods.contains(target.method)) {
      throw const ToolingProtocolStateError(
        'analysis_server_cancel_target_unknown',
        'Analysis Server cancel target is not an active ordinary request.',
      );
    }
    if (!_cancellationIntents.add(targetId)) {
      throw const ToolingProtocolStateError(
        'analysis_server_cancel_duplicate',
        'Analysis Server cancellation intent was already recorded.',
      );
    }
    try {
      return _allocateValidated(
        'server.cancelRequest',
        <String, Object?>{'id': targetId},
      );
    } on Object {
      _cancellationIntents.remove(targetId);
      rethrow;
    }
  }

  bool isCancellationRequested(String requestId) =>
      _cancellationIntents.contains(requestId);

  AnalysisServerPendingRequest beginShutdown() {
    if (_lifecycle != AnalysisServerConnectionLifecycle.ready) {
      throw const ToolingProtocolStateError(
        'analysis_server_shutdown_out_of_order',
        'Analysis Server shutdown requires ready state.',
      );
    }
    final pending = _allocateValidated('server.shutdown', null);
    _lifecycle = AnalysisServerConnectionLifecycle.shuttingDown;
    return pending;
  }

  void completeResponse({
    required String id,
    required String method,
    Object? result,
    Object? failure,
  }) {
    final pending = _expectPending(id, method);
    if (failure == null) {
      AnalysisServerModelRegistry.instance.validateResponseResult(
        method,
        result,
        version: capabilities.apiVersion,
      );
    }
    _completePending(pending, failure);
    if (method == 'server.shutdown') {
      close();
    }
  }

  AnalysisServerNotificationRecord receiveNotification(
    String event,
    Map<String, Object?> params,
  ) {
    if (_lifecycle != AnalysisServerConnectionLifecycle.ready &&
        _lifecycle != AnalysisServerConnectionLifecycle.shuttingDown) {
      throw const ToolingProtocolStateError(
        'analysis_server_notification_out_of_state',
        'Analysis Server notifications require negotiated state.',
      );
    }
    final validated =
        AnalysisServerModelRegistry.instance.validateNotificationParams(
              event,
              params,
              version: capabilities.apiVersion,
            ) ??
            const <String, Object?>{};
    final record = notifications.add(event, validated);
    switch (event) {
      case 'server.status':
        _latestStatus = record.params;
      case 'analysis.errors':
        final file = record.params['file']! as String;
        _latestErrorsByFile[file] = List<Object?>.unmodifiable(
          record.params['errors']! as List<Object?>,
        );
      default:
        break;
    }
    return record;
  }

  void assertCurrentSnapshot(AnalysisServerCapabilitySnapshot snapshot) {
    if (snapshot.connectionId != connectionId ||
        _capabilities == null ||
        snapshot.generation != _capabilities!.generation) {
      throw const ToolingProtocolStateError(
        'analysis_server_capability_snapshot_stale',
        'Analysis Server capability snapshot belongs to an old connection.',
      );
    }
  }

  void close() {
    if (_lifecycle == AnalysisServerConnectionLifecycle.closed) {
      return;
    }
    const failure = ToolingProtocolStateError(
      'analysis_server_connection_closed',
      'Analysis Server connection closed before the request completed.',
    );
    for (final pending in _pending.values.toList()) {
      _completePending(pending, failure);
    }
    _capabilities = null;
    _lifecycle = AnalysisServerConnectionLifecycle.closed;
  }

  AnalysisServerConnection reconnect() {
    close();
    return AnalysisServerConnection(maxNotifications: _maxNotifications);
  }

  AnalysisServerPendingRequest _allocateValidated(
    String method,
    Map<String, Object?>? params,
  ) {
    AnalysisServerModelRegistry.instance.validateRequestParams(
      method,
      params,
      version: capabilities.apiVersion,
    );
    return _allocate(method, params);
  }

  AnalysisServerPendingRequest _allocate(
    String method,
    Map<String, Object?>? params,
  ) {
    final pending = AnalysisServerPendingRequest._(
      id: '${_nextRequestId++}',
      method: method,
      params: params == null ? null : freezeJsonObject(params),
      connectionId: connectionId,
    );
    _pending[pending.id] = pending;
    return pending;
  }

  AnalysisServerPendingRequest _expectPending(String id, String method) {
    if (_tombstones.containsKey(id)) {
      throw const ToolingProtocolStateError(
        'analysis_server_response_tombstoned',
        'Analysis Server response matches an already completed request.',
      );
    }
    final pending = _pending[id];
    if (pending == null) {
      throw const ToolingProtocolStateError(
        'analysis_server_response_unknown',
        'Analysis Server response does not match a pending request.',
      );
    }
    if (pending.method != method) {
      throw const ToolingProtocolStateError(
        'analysis_server_response_method_mismatch',
        'Analysis Server response method does not match its request id.',
      );
    }
    return pending;
  }

  void _completePending(
    AnalysisServerPendingRequest pending, [
    Object? failure,
  ]) {
    _pending.remove(pending.id);
    _cancellationIntents.remove(pending.id);
    pending._complete(failure);
    _tombstones[pending.id] = pending.method;
  }
}

const _controlMethods = <String>{
  'server.getVersion',
  'server.cancelRequest',
  'server.shutdown',
};

const _serverOriginatedRequests = <String>{
  'server.openUrlRequest',
  'server.showMessageRequest',
};

AnalysisServerApiVersion _parseApiVersion(Object? value) {
  if (value is! String) {
    throw const ToolingVersionError(
      'analysis_server_api_version_invalid',
      'Analysis Server API version must be a semantic version string.',
    );
  }
  final match = RegExp(r'^([0-9]+)\.([0-9]+)\.([0-9]+)$').firstMatch(value);
  if (match == null) {
    throw const ToolingVersionError(
      'analysis_server_api_version_invalid',
      'Analysis Server API version must use major.minor.patch.',
    );
  }
  return AnalysisServerApiVersion(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

ToolingVersionError? _versionIncompatibility(
  AnalysisServerApiVersion version,
) {
  if (version.major != analysisServerCurrentApiVersion.major) {
    return const ToolingVersionError(
      'analysis_server_api_major_unsupported',
      'Analysis Server API major is unsupported.',
    );
  }
  if (!analysisServerVersionPolicy.supports(version)) {
    return const ToolingVersionError(
      'analysis_server_api_version_unsupported',
      'Analysis Server API version is outside the pinned supported range.',
    );
  }
  return null;
}
