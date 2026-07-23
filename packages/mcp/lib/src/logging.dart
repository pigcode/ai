import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'client.dart';
import 'generated/mcp_models.g.dart';
import 'server.dart';

extension McpClientLogging on McpClient {
  Future<McpEmptyResult> setLoggingLevel(
    McpSetLevelRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpEmptyResult.fromJson(
        await requestServer(
          'logging/setLevel',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );
}

extension McpServerLogging on McpServer {
  Future<void> logMessage(McpLoggingMessageNotificationParams params) =>
      notifyClient('notifications/message', params.toJson());
}
