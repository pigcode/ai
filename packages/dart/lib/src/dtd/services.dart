import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/errors.dart';
import 'connection.dart';
import 'models.dart';

final class DtdServiceRegistration {
  DtdServiceRegistration._({
    required this.request,
    required this.service,
    required this.method,
    required this.capabilities,
    required this.ownerGeneration,
  });

  final DtdPendingRequest request;
  final String service;
  final String method;
  final JsonObject capabilities;
  final int ownerGeneration;
  bool _active = false;
  bool _valid = true;

  String get fullMethod => '$service.$method';
  bool get active => _active && _valid;
}

final class DtdForwardedServiceCall {
  DtdForwardedServiceCall._({
    required this.id,
    required this.method,
    required this.params,
    required this.connectionId,
    required this.ownerGeneration,
    required this.registration,
  });

  final String id;
  final String method;
  final JsonObject params;
  final int connectionId;
  final int ownerGeneration;
  final DtdServiceRegistration registration;
  bool _done = false;
}

final class DtdServices {
  DtdServices({required this.connection});

  final DtdConnection connection;
  final Map<String, DtdServiceRegistration> _registrations =
      <String, DtdServiceRegistration>{};
  final Map<String, DtdServiceRegistration> _operations =
      <String, DtdServiceRegistration>{};
  int _nextOwnerGeneration = 1;
  bool _disconnected = false;

  DtdServiceRegistration register({
    required String service,
    required String method,
    Map<String, Object?> capabilities = const <String, Object?>{},
  }) {
    if (_disconnected) {
      throw const ToolingProtocolStateError(
        'dtd_service_owner_disconnected',
        'DTD service owner is disconnected.',
      );
    }
    final fullMethod = '$service.$method';
    if (_registrations.containsKey(fullMethod)) {
      throw const ToolingProtocolStateError(
        'dtd_service_registration_duplicate',
        'DTD service or method is already owned by this registry.',
      );
    }
    final request = connection.beginRequest(
      'registerService',
      params: <String, Object?>{
        'service': service,
        'method': method,
        if (capabilities.isNotEmpty) 'capabilities': capabilities,
      },
    );
    final registration = DtdServiceRegistration._(
      request: request,
      service: service,
      method: method,
      capabilities: freezeJsonObject(capabilities),
      ownerGeneration: _nextOwnerGeneration++,
    );
    _registrations[fullMethod] = registration;
    _operations[request.id] = registration;
    return registration;
  }

  DtdForwardedServiceCall acceptForwarded({
    required String id,
    required String method,
    required Map<String, Object?> params,
  }) {
    if (_disconnected) {
      throw const ToolingProtocolStateError(
        'dtd_service_owner_disconnected',
        'DTD service owner is disconnected.',
      );
    }
    final registration = _registrations[method];
    if (registration == null || !registration.active) {
      throw const ToolingProtocolStateError(
        'dtd_service_forward_unknown',
        'DTD forwarded call has no active local owner.',
      );
    }
    final validated = DtdModelRegistry.instance.validateParams(method, params);
    return DtdForwardedServiceCall._(
      id: id,
      method: method,
      params: validated,
      connectionId: connection.connectionId,
      ownerGeneration: registration.ownerGeneration,
      registration: registration,
    );
  }

  JsonObject completeForwarded(
    DtdForwardedServiceCall call,
    JsonValue result,
  ) {
    final registration = _registrations[call.method];
    if (_disconnected ||
        call._done ||
        call.connectionId != connection.connectionId ||
        registration == null ||
        !identical(registration, call.registration) ||
        registration.ownerGeneration != call.ownerGeneration ||
        !registration.active) {
      throw const ToolingProtocolStateError(
        'dtd_service_forward_stale',
        'DTD forwarded response belongs to a stale service owner.',
      );
    }
    final validated =
        DtdModelRegistry.instance.validateResult(call.method, result);
    call._done = true;
    return freezeJsonObject(<String, Object?>{
      'jsonrpc': '2.0',
      'id': call.id,
      'result': validated,
    });
  }

  void complete(String requestId, {Object? failure}) {
    final registration = _operations.remove(requestId);
    if (registration == null) {
      return;
    }
    if (failure == null) {
      registration._active = true;
    } else {
      registration._valid = false;
      _registrations.remove(registration.fullMethod);
    }
  }

  void disconnect() {
    if (_disconnected) {
      return;
    }
    _disconnected = true;
    for (final registration in _registrations.values) {
      registration._valid = false;
      registration._active = false;
    }
    _registrations.clear();
    _operations.clear();
  }
}
