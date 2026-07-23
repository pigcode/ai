import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'client.dart';
import 'generated/mcp_models.g.dart';
import 'server.dart';

extension McpServerReverseRequests on McpServer {
  Future<McpCreateMessageResult> createMessage(
    McpCreateMessageRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpCreateMessageResult.fromJson(
        await requestClient(
          'sampling/createMessage',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpListRootsResult> listRoots({
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpListRootsResult.fromJson(
        await requestClient(
          'roots/list',
          const <String, Object?>{},
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpElicitResult> elicit(
    McpElicitRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpElicitResult.fromJson(
        await requestClient(
          'elicitation/create',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<void> notifyElicitationComplete(String elicitationId) => notifyClient(
        'notifications/elicitation/complete',
        <String, Object?>{'elicitationId': elicitationId},
      );

  Future<void> notifyProgress(McpProgressNotificationParams params) =>
      notifyClient('notifications/progress', params.toJson());
}

extension McpClientReverseNotifications on McpClient {
  Future<void> notifyRootsListChanged() =>
      notifyServer('notifications/roots/list_changed', const {});

  Future<void> notifyProgress(McpProgressNotificationParams params) =>
      notifyServer('notifications/progress', params.toJson());
}
