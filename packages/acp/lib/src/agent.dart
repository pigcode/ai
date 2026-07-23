import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'capabilities.dart';
import 'connection.dart';
import 'generated/acp_models.g.dart'
    hide AcpAgentCapabilities, AcpClientCapabilities;
import 'handlers.dart';
import 'transport.dart';

/// ACP agent-side runtime with typed client reverse requests.
final class AcpAgent {
  factory AcpAgent.fromByteTransport({
    required ProtocolByteTransport byteTransport,
    required AcpAgentCapabilities capabilities,
    required AcpHandlerSet handlers,
    JsonObject? agentInfo,
    List<JsonValue> authMethods = const <JsonValue>[],
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  }) =>
      AcpAgent(
        transport: createAcpNdjsonTransport(
          byteTransport: byteTransport,
          limits: limits,
        ),
        capabilities: capabilities,
        handlers: handlers,
        agentInfo: agentInfo,
        authMethods: authMethods,
        limits: limits,
        diagnostics: diagnostics,
      );

  AcpAgent({
    required ProtocolMessageTransport<JsonRpcMessage> transport,
    required AcpAgentCapabilities capabilities,
    required AcpHandlerSet handlers,
    JsonObject? agentInfo,
    List<JsonValue> authMethods = const <JsonValue>[],
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  }) : connection = AcpConnection.agent(
          transport: transport,
          capabilities: capabilities,
          handlers: handlers,
          agentInfo: agentInfo,
          authMethods: authMethods,
          limits: limits,
          diagnostics: diagnostics,
        );

  final AcpConnection connection;

  AcpConnectionState get state => connection.state;
  AcpNegotiatedCapabilities? get negotiatedCapabilities =>
      connection.negotiatedCapabilities;

  Future<JsonValue> requestClient(
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

  Future<void> notifyClient(String method, JsonValue params) =>
      connection.notifyRemote(method, params);

  Future<AcpRequestPermissionResponse> requestPermission(
    AcpRequestPermissionRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpRequestPermissionResponse.fromJson(
        await requestClient(
          'session/request_permission',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpReadTextFileResponse> readTextFile(
    AcpReadTextFileRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpReadTextFileResponse.fromJson(
        await requestClient(
          'fs/read_text_file',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpWriteTextFileResponse> writeTextFile(
    AcpWriteTextFileRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpWriteTextFileResponse.fromJson(
        await requestClient(
          'fs/write_text_file',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpCreateTerminalResponse> createTerminal(
    AcpCreateTerminalRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpCreateTerminalResponse.fromJson(
        await requestClient(
          'terminal/create',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpTerminalOutputResponse> terminalOutput(
    AcpTerminalOutputRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpTerminalOutputResponse.fromJson(
        await requestClient(
          'terminal/output',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpReleaseTerminalResponse> releaseTerminal(
    AcpReleaseTerminalRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpReleaseTerminalResponse.fromJson(
        await requestClient(
          'terminal/release',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpWaitForTerminalExitResponse> waitForTerminalExit(
    AcpWaitForTerminalExitRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpWaitForTerminalExitResponse.fromJson(
        await requestClient(
          'terminal/wait_for_exit',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<AcpKillTerminalResponse> killTerminal(
    AcpKillTerminalRequest request, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      AcpKillTerminalResponse.fromJson(
        await requestClient(
          'terminal/kill',
          request.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<void> updateSession(AcpSessionNotification notification) =>
      notifyClient('session/update', notification.toJson());

  Future<void> close() => connection.close();
}
