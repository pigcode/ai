import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'models.dart';

typedef McpRequestHandler = FutureOr<JsonValue> Function(
  McpRequestInvocation invocation,
);

typedef McpNotificationHandler = FutureOr<void> Function(
  McpNotificationInvocation invocation,
);

final class McpRequestInvocation {
  const McpRequestInvocation({
    required this.binding,
    required this.params,
    required this.cancellation,
  });

  final McpMethodBinding binding;
  final JsonValue params;
  final ProtocolCancellationSignal cancellation;
}

final class McpNotificationInvocation {
  const McpNotificationInvocation({
    required this.binding,
    required this.params,
  });

  final McpMethodBinding binding;
  final JsonValue params;
}

final class McpHandlerSet {
  McpHandlerSet({
    Map<String, McpRequestHandler> requests =
        const <String, McpRequestHandler>{},
    Map<String, McpNotificationHandler> notifications =
        const <String, McpNotificationHandler>{},
  })  : requests = Map<String, McpRequestHandler>.unmodifiable(requests),
        notifications =
            Map<String, McpNotificationHandler>.unmodifiable(notifications);

  final Map<String, McpRequestHandler> requests;
  final Map<String, McpNotificationHandler> notifications;

  void validateFor(McpParticipant localParticipant) {
    final remoteParticipant = localParticipant == McpParticipant.client
        ? McpParticipant.server
        : McpParticipant.client;
    final invalid = <String>[];
    for (final method in requests.keys) {
      if (!_hasBinding(method, remoteParticipant, notification: false)) {
        invalid.add(method);
      }
    }
    for (final method in notifications.keys) {
      if (!_hasBinding(method, remoteParticipant, notification: true)) {
        invalid.add(method);
      }
    }
    if (invalid.isNotEmpty) {
      invalid.sort();
      throw McpHandlerException(
        'mcp_invalid_handler_registration',
        'MCP handler does not match the local participant role.',
        methods: invalid,
      );
    }
  }

  void requireHandlers(Iterable<String> requiredMethods) {
    final missing = requiredMethods
        .where((method) => !requests.containsKey(method))
        .toList()
      ..sort();
    if (missing.isNotEmpty) {
      throw McpHandlerException(
        'mcp_claimed_capability_missing_handler',
        'Advertised MCP capability has no matching request handler.',
        methods: missing,
      );
    }
  }
}

bool _hasBinding(
  String method,
  McpParticipant sender, {
  required bool notification,
}) =>
    mcpMethodBindingsByName[method]?.any(
      (binding) =>
          binding.sender == sender && binding.isNotification == notification,
    ) ??
    false;
