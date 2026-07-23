import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'capabilities.dart';
import 'connection.dart';
import 'generated/acp_models.g.dart'
    hide AcpAgentCapabilities, AcpClientCapabilities;
import 'handlers.dart';
import 'history.dart';
import 'prompt.dart';
import 'session.dart';
import 'transport.dart';

/// ACP client-side runtime with typed lifecycle and prompt primitives.
final class AcpClient {
  factory AcpClient.fromByteTransport({
    required ProtocolByteTransport byteTransport,
    required AcpClientCapabilities capabilities,
    required AcpHandlerSet handlers,
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  }) =>
      AcpClient(
        transport: createAcpNdjsonTransport(
          byteTransport: byteTransport,
          limits: limits,
        ),
        capabilities: capabilities,
        handlers: handlers,
        limits: limits,
        diagnostics: diagnostics,
      );

  factory AcpClient({
    required ProtocolMessageTransport<JsonRpcMessage> transport,
    required AcpClientCapabilities capabilities,
    required AcpHandlerSet handlers,
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  }) {
    final resolvedLimits = limits ?? ProtocolLimits.defaults;
    final resolvedDiagnostics = diagnostics ??
        BoundedProtocolDiagnostics(
          maxEntries: resolvedLimits.maxDiagnostics,
        );
    final history = AcpSessionHistory(
      maxEntries: resolvedLimits.maxTombstones,
    );
    final promptLedger = AcpPromptLedger(
      history: history,
      diagnostics: resolvedDiagnostics,
      maxSessions: resolvedLimits.maxTombstones,
    );
    final updates = StreamController<AcpSessionUpdateEvent>.broadcast(
      sync: true,
    );
    final callerUpdateHandler = handlers.notifications['session/update'];
    final combinedHandlers = AcpHandlerSet(
      requests: handlers.requests,
      notifications: <String, AcpNotificationHandler>{
        ...handlers.notifications,
        'session/update': (invocation) async {
          final event = promptLedger.recordUpdate(
            invocation.params! as JsonObject,
          );
          if (!updates.isClosed) {
            updates.add(event);
          }
          if (callerUpdateHandler != null) {
            await callerUpdateHandler(invocation);
          }
        },
      },
    );
    final connection = AcpConnection.client(
      transport: transport,
      capabilities: capabilities,
      handlers: combinedHandlers,
      limits: resolvedLimits,
      diagnostics: resolvedDiagnostics,
    );
    return AcpClient._(
      connection: connection,
      history: history,
      promptLedger: promptLedger,
      updates: updates,
    );
  }

  AcpClient._({
    required this.connection,
    required this.history,
    required AcpPromptLedger promptLedger,
    required StreamController<AcpSessionUpdateEvent> updates,
  })  : _promptLedger = promptLedger,
        _updates = updates;

  final AcpConnection connection;
  final AcpSessionHistory history;
  final AcpPromptLedger _promptLedger;
  final StreamController<AcpSessionUpdateEvent> _updates;
  Future<void>? _closeFuture;

  AcpConnectionState get state => connection.state;
  AcpNegotiatedCapabilities? get negotiatedCapabilities =>
      connection.negotiatedCapabilities;
  Stream<AcpSessionUpdateEvent> get updates => _updates.stream;

  bool hasActivePrompt(String sessionId) =>
      _promptLedger.hasActivePrompt(sessionId);

  Future<AcpNegotiatedCapabilities> initialize({
    JsonObject? clientInfo,
  }) =>
      connection.initializeClient(clientInfo: clientInfo);

  Future<JsonValue> request(
    String method,
    JsonValue params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) =>
      connection.requestRemote(
        method,
        params,
        cancellation: cancellation,
        timeout: timeout,
      );

  Future<void> notify(String method, JsonValue params) =>
      connection.notifyRemote(method, params);

  Future<AcpAuthenticateResponse> authenticate(
    AcpAuthenticateRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpAuthenticateResponse.fromJson(
        await this.request(
          'authenticate',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpNewSessionResponse> createSession(
    AcpNewSessionRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpNewSessionResponse.fromJson(
        await this.request(
          'session/new',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpSessionRestoreResult<AcpLoadSessionResponse>> loadSession(
    AcpLoadSessionRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async {
    final sessionId = (request.toJson()! as JsonObject)['sessionId']! as String;
    final marker = history.beginHistoricalReplay(sessionId);
    try {
      final response = AcpLoadSessionResponse.fromJson(
        await this.request(
          'session/load',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );
      return AcpSessionRestoreResult<AcpLoadSessionResponse>(
        kind: AcpSessionRestoreKind.load,
        response: response,
        historicalUpdates: history.endHistoricalReplay(sessionId, marker),
      );
    } on Object {
      history.endHistoricalReplay(sessionId, marker);
      rethrow;
    }
  }

  Future<AcpSetSessionModeResponse> setSessionMode(
    AcpSetSessionModeRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpSetSessionModeResponse.fromJson(
        await this.request(
          'session/set_mode',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpSetSessionConfigOptionResponse> setSessionConfigOption(
    AcpSetSessionConfigOptionRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpSetSessionConfigOptionResponse.fromJson(
        await this.request(
          'session/set_config_option',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpPromptTurnResult> prompt(
    AcpPromptRequest request, {
    ProtocolCancellationSignal? requestCancellation,
    Duration? timeout,
  }) async {
    final sessionId = (request.toJson()! as JsonObject)['sessionId']! as String;
    _promptLedger.beginPrompt(sessionId);
    try {
      final response = AcpPromptResponse.fromJson(
        await this.request(
          'session/prompt',
          request.toJson(),
          cancellation: requestCancellation,
          timeout: timeout,
        ),
      );
      return _promptLedger.completePrompt(sessionId, response);
    } on Object {
      _promptLedger.abortPrompt(sessionId);
      rethrow;
    }
  }

  Future<void> cancelSession(String sessionId) async {
    _promptLedger.noteSessionCancel(sessionId);
    try {
      await notify(
        'session/cancel',
        <String, Object?>{'sessionId': sessionId},
      );
    } on Object {
      _promptLedger.revokeSessionCancel(sessionId);
      rethrow;
    }
  }

  Future<AcpListSessionsResponse> listSessions(
    AcpListSessionsRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpListSessionsResponse.fromJson(
        await this.request(
          'session/list',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpDeleteSessionResponse> deleteSession(
    AcpDeleteSessionRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpDeleteSessionResponse.fromJson(
        await this.request(
          'session/delete',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpSessionRestoreResult<AcpResumeSessionResponse>> resumeSession(
    AcpResumeSessionRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async {
    final response = AcpResumeSessionResponse.fromJson(
      await this.request(
        'session/resume',
        request.toJson(),
        cancellation: cancellation,
        timeout: timeout,
      ),
    );
    return AcpSessionRestoreResult<AcpResumeSessionResponse>(
      kind: AcpSessionRestoreKind.resume,
      response: response,
    );
  }

  Future<AcpCloseSessionResponse> closeSession(
    AcpCloseSessionRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpCloseSessionResponse.fromJson(
        await this.request(
          'session/close',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpLogoutResponse> logout(
    AcpLogoutRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpLogoutResponse.fromJson(
        await this.request(
          'logout',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    await connection.close();
    if (!_updates.isClosed) {
      await _updates.close();
    }
  }
}
