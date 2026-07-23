import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'client.dart';
import 'generated/mcp_models.g.dart';
import 'server.dart';

extension McpClientResources on McpClient {
  Future<McpListResourcesResult> listResources(
    McpPaginatedRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpListResourcesResult.fromJson(
        await requestServer(
          'resources/list',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpListResourceTemplatesResult> listResourceTemplates(
    McpPaginatedRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpListResourceTemplatesResult.fromJson(
        await requestServer(
          'resources/templates/list',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpReadResourceResult> readResource(
    McpReadResourceRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpReadResourceResult.fromJson(
        await requestServer(
          'resources/read',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpEmptyResult> subscribeResource(
    McpSubscribeRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpEmptyResult.fromJson(
        await requestServer(
          'resources/subscribe',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpEmptyResult> unsubscribeResource(
    McpUnsubscribeRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpEmptyResult.fromJson(
        await requestServer(
          'resources/unsubscribe',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );
}

extension McpServerResourceNotifications on McpServer {
  Future<void> notifyResourceListChanged() =>
      notifyClient('notifications/resources/list_changed', const {});

  Future<void> notifyResourceUpdated(
    McpResourceUpdatedNotificationParams params,
  ) =>
      notifyClient('notifications/resources/updated', params.toJson());
}
