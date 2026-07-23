import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'capabilities.dart';
import 'cancellation_adapter.dart';
import 'errors.dart';
import 'handlers.dart';
import 'models.dart';
import 'schema.dart';

enum AcpParticipant {
  agent,
  client,
}

enum AcpConnectionState {
  uninitialized,
  initializing,
  initialized,
  closing,
  closed,
}

/// One logical ACP connection over a caller-supplied message transport.
final class AcpConnection {
  AcpConnection.agent({
    required ProtocolMessageTransport<JsonRpcMessage> transport,
    required AcpAgentCapabilities capabilities,
    required AcpHandlerSet handlers,
    JsonObject? agentInfo,
    List<JsonValue> authMethods = const <JsonValue>[],
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  })  : participant = AcpParticipant.agent,
        _agentCapabilities = capabilities,
        _clientCapabilities = null,
        _agentInfo = _validateImplementation(agentInfo),
        _authMethods = _validateAuthMethods(authMethods),
        _handlers = handlers {
    _validateLocalHandlers();
    _createPeer(
      transport,
      limits: limits,
      diagnostics: diagnostics,
    );
  }

  AcpConnection.client({
    required ProtocolMessageTransport<JsonRpcMessage> transport,
    required AcpClientCapabilities capabilities,
    required AcpHandlerSet handlers,
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  })  : participant = AcpParticipant.client,
        _agentCapabilities = null,
        _clientCapabilities = capabilities,
        _agentInfo = null,
        _authMethods = const <JsonValue>[],
        _handlers = handlers {
    _validateLocalHandlers();
    _createPeer(
      transport,
      limits: limits,
      diagnostics: diagnostics,
    );
  }

  final AcpParticipant participant;
  final AcpAgentCapabilities? _agentCapabilities;
  final AcpClientCapabilities? _clientCapabilities;
  final JsonObject? _agentInfo;
  final List<JsonValue> _authMethods;
  final AcpHandlerSet _handlers;
  late final JsonRpcPeer _peer;
  AcpConnectionState _state = AcpConnectionState.uninitialized;
  AcpNegotiatedCapabilities? _negotiatedCapabilities;

  AcpConnectionState get state => _state;
  AcpNegotiatedCapabilities? get negotiatedCapabilities =>
      _negotiatedCapabilities;
  JsonRpcPeer get peer => _peer;

  Future<AcpNegotiatedCapabilities> initializeClient({
    JsonObject? clientInfo,
  }) async {
    if (participant != AcpParticipant.client) {
      throw const AcpStateException(
        'acp_initialize_wrong_side',
        'Only the ACP client initiates initialize.',
      );
    }
    if (_state != AcpConnectionState.uninitialized) {
      throw const AcpStateException(
        'acp_duplicate_initialize',
        'ACP initialize may be sent exactly once.',
      );
    }
    _state = AcpConnectionState.initializing;
    try {
      final validatedClientInfo = _validateImplementation(clientInfo);
      final result = await _requestUnchecked(
        'initialize',
        <String, Object?>{
          'protocolVersion': 1,
          'clientCapabilities': _clientCapabilities!.toJson(),
          if (validatedClientInfo != null) 'clientInfo': validatedClientInfo,
        },
      );
      final response = result! as JsonObject;
      final version = response['protocolVersion'];
      if (version != 1) {
        throw AcpVersionException(
          receivedVersion: version is int ? version : null,
        );
      }
      final agentCapabilities = AcpAgentCapabilities.fromJson(
        response['agentCapabilities'] ?? const <String, Object?>{},
      );
      _negotiatedCapabilities = AcpNegotiatedCapabilities(
        protocolVersion: 1,
        client: _clientCapabilities,
        agent: agentCapabilities,
      );
      _state = AcpConnectionState.initialized;
      return _negotiatedCapabilities!;
    } on Object {
      _state = AcpConnectionState.closing;
      await _peer.close();
      _state = AcpConnectionState.closed;
      rethrow;
    }
  }

  Future<JsonValue> requestRemote(
    String method,
    JsonValue params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async {
    _requireInitialized();
    return _requestChecked(
      method,
      params,
      cancellation: cancellation,
      timeout: timeout,
    );
  }

  Future<void> notifyRemote(String method, JsonValue params) async {
    _requireInitialized();
    final descriptor = _outboundDescriptor(method, notification: true);
    _requireCapability(descriptor);
    final definition = descriptor.notificationDefinition!;
    final validated = AcpSchema.instance.validateDefinition(
      definition,
      params ?? const <String, Object?>{},
    );
    await _peer.notify(method, params: validated);
  }

  Future<void> close() async {
    if (_state == AcpConnectionState.closed) {
      return;
    }
    _state = AcpConnectionState.closing;
    await _peer.close();
    _state = AcpConnectionState.closed;
  }

  void _createPeer(
    ProtocolMessageTransport<JsonRpcMessage> transport, {
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  }) {
    final requestHandlers = <String, JsonRpcRequestHandler>{};
    if (participant == AcpParticipant.agent) {
      requestHandlers['initialize'] = _handleInitialize;
    }
    for (final entry in _handlers.requests.entries) {
      if (entry.key == 'initialize') {
        continue;
      }
      requestHandlers[entry.key] = (request, cancellation) =>
          _dispatchRequest(entry.value, request, cancellation);
    }

    final notificationHandlers = <String, JsonRpcNotificationHandler>{
      r'$/cancel_request': _handleCancelRequest,
      for (final entry in _handlers.notifications.entries)
        entry.key: (notification) =>
            _dispatchNotification(entry.value, notification),
    };
    _peer = JsonRpcPeer(
      transport: transport,
      limits: limits,
      diagnostics: diagnostics,
      requestHandlers: requestHandlers,
      notificationHandlers: notificationHandlers,
    );
    unawaited(
      _peer.done.then((_) {
        if (_state != AcpConnectionState.closing) {
          _state = AcpConnectionState.closed;
        }
      }),
    );
  }

  Future<JsonValue> _handleInitialize(
    JsonRpcRequest request,
    ProtocolCancellationSignal cancellation,
  ) async {
    if (_state != AcpConnectionState.uninitialized) {
      throw const JsonRpcHandlerException(
        code: -32600,
        message: 'Duplicate initialize request',
      );
    }
    final params =
        _validateParams('InitializeRequest', request.params)! as JsonObject;
    final version = params['protocolVersion'];
    if (version != 1) {
      throw JsonRpcHandlerException(
        code: -32602,
        message: 'Unsupported protocol version',
        hasData: true,
        data: <String, Object?>{
          'supportedProtocolVersion': 1,
          if (version is int) 'receivedProtocolVersion': version,
        },
      );
    }
    final clientCapabilities = AcpClientCapabilities.fromJson(
      params['clientCapabilities'] ?? const <String, Object?>{},
    );
    _negotiatedCapabilities = AcpNegotiatedCapabilities(
      protocolVersion: 1,
      client: clientCapabilities,
      agent: _agentCapabilities!,
    );
    _state = AcpConnectionState.initialized;
    return AcpSchema.instance.validateDefinition(
      'InitializeResponse',
      <String, Object?>{
        'protocolVersion': 1,
        'agentCapabilities': _agentCapabilities.toJson(),
        'authMethods': _authMethods,
        if (_agentInfo != null) 'agentInfo': _agentInfo,
      },
    );
  }

  Future<JsonValue> _dispatchRequest(
    AcpRequestHandler handler,
    JsonRpcRequest request,
    ProtocolCancellationSignal cancellation,
  ) async {
    if (_state != AcpConnectionState.initialized) {
      throw const JsonRpcHandlerException(
        code: -32001,
        message: 'ACP connection is not initialized',
      );
    }
    final descriptor = acpMethodsByName[request.method]!;
    late final JsonValue params;
    try {
      params = _validateParams(
        descriptor.requestDefinition!,
        request.params,
      );
    } on AcpSchemaException {
      throw const JsonRpcHandlerException(
        code: -32602,
        message: 'Invalid ACP method parameters',
      );
    }
    final result = await Future<JsonValue>.sync(
      () => handler(
        AcpRequestInvocation(
          descriptor: descriptor,
          params: params,
          cancellation: cancellation,
        ),
      ),
    );
    return AcpSchema.instance.validateDefinition(
      descriptor.responseDefinition!,
      result,
    );
  }

  Future<void> _dispatchNotification(
    AcpNotificationHandler handler,
    JsonRpcNotification notification,
  ) async {
    if (_state != AcpConnectionState.initialized) {
      throw const AcpStateException(
        'acp_not_initialized',
        'ACP operation requires a completed initialize exchange.',
      );
    }
    final descriptor = acpMethodsByName[notification.method]!;
    final params = _validateParams(
      descriptor.notificationDefinition!,
      notification.params,
    );
    await Future<void>.sync(
      () => handler(
        AcpNotificationInvocation(
          descriptor: descriptor,
          params: params,
        ),
      ),
    );
  }

  void _handleCancelRequest(JsonRpcNotification notification) {
    final params = _validateParams(
      'CancelRequestNotification',
      notification.params,
    )! as JsonObject;
    final requestId = JsonRpcId.fromJson(params['requestId']);
    _peer.cancelInboundRequest(requestId, 'remote cancellation');
  }

  Future<JsonValue> _requestChecked(
    String method,
    JsonValue params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async {
    final descriptor = _outboundDescriptor(method, notification: false);
    _requireCapability(descriptor);
    return _requestUnchecked(
      method,
      params,
      cancellation: cancellation,
      timeout: timeout,
    );
  }

  Future<JsonValue> _requestUnchecked(
    String method,
    JsonValue params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async {
    final descriptor = _outboundDescriptor(method, notification: false);
    final validatedParams = AcpSchema.instance.validateDefinition(
      descriptor.requestDefinition!,
      params ?? const <String, Object?>{},
    );
    final result = await AcpRequestCancellationAdapter.request(
      peer: _peer,
      method: method,
      params: validatedParams,
      cancellation: cancellation,
      timeout: timeout,
    );
    return AcpSchema.instance.validateDefinition(
      descriptor.responseDefinition!,
      result,
    );
  }

  AcpMethodDescriptor _outboundDescriptor(
    String method, {
    required bool notification,
  }) {
    final descriptor = acpMethodsByName[method];
    final remoteSide = participant == AcpParticipant.client
        ? AcpMethodHandlerSide.agent
        : AcpMethodHandlerSide.client;
    final correctKind = notification
        ? descriptor?.notificationDefinition != null
        : descriptor?.requestDefinition != null;
    if (descriptor == null ||
        descriptor.handlerSide != remoteSide ||
        !correctKind) {
      throw AcpCodecException(
        'acp_wrong_role',
        'ACP method cannot be sent by this participant.',
        method: method,
      );
    }
    return descriptor;
  }

  void _requireCapability(AcpMethodDescriptor descriptor) {
    if (!_negotiatedCapabilities!.supportsMethod(descriptor.method)) {
      throw AcpCapabilityException(
        'acp_capability_not_negotiated',
        'ACP optional method was not negotiated.',
        method: descriptor.method,
      );
    }
  }

  void _requireInitialized() {
    if (_state != AcpConnectionState.initialized) {
      throw const AcpStateException(
        'acp_not_initialized',
        'ACP operation requires a completed initialize exchange.',
      );
    }
  }

  JsonValue _validateParams(String definition, JsonValue params) =>
      AcpSchema.instance.validateDefinition(
        definition,
        params ?? const <String, Object?>{},
      );

  void _validateLocalHandlers() {
    final side = participant == AcpParticipant.agent
        ? AcpMethodHandlerSide.agent
        : AcpMethodHandlerSide.client;
    _handlers.requireSide(side);
    if (_handlers.requests.containsKey('initialize')) {
      throw AcpHandlerException(
        'acp_reserved_handler',
        'Initialize is owned by AcpConnection.',
        methods: const <String>['initialize'],
      );
    }
    if (participant == AcpParticipant.agent) {
      _handlers.requireHandlers(_agentCapabilities!.requiredHandlerMethods);
    } else {
      _handlers.requireHandlers(_clientCapabilities!.requiredHandlerMethods);
    }
  }
}

JsonObject? _validateImplementation(JsonObject? value) {
  if (value == null) {
    return null;
  }
  return AcpSchema.instance.validateDefinition('Implementation', value)!
      as JsonObject;
}

List<JsonValue> _validateAuthMethods(List<JsonValue> values) =>
    List<JsonValue>.unmodifiable(
      values.map(
        (value) => AcpSchema.instance.validateDefinition('AuthMethod', value),
      ),
    );
