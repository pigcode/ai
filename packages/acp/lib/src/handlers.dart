import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'models.dart';

typedef AcpRequestHandler = FutureOr<JsonValue> Function(
  AcpRequestInvocation invocation,
);

typedef AcpNotificationHandler = FutureOr<void> Function(
  AcpNotificationInvocation invocation,
);

/// One schema-validated inbound ACP request.
final class AcpRequestInvocation {
  const AcpRequestInvocation({
    required this.descriptor,
    required this.params,
    required this.cancellation,
  });

  final AcpMethodDescriptor descriptor;
  final JsonValue params;
  final ProtocolCancellationSignal cancellation;
}

/// One schema-validated inbound ACP notification.
final class AcpNotificationInvocation {
  const AcpNotificationInvocation({
    required this.descriptor,
    required this.params,
  });

  final AcpMethodDescriptor descriptor;
  final JsonValue params;
}

/// Immutable request and notification handler registry.
final class AcpHandlerSet {
  AcpHandlerSet({
    Map<String, AcpRequestHandler> requests =
        const <String, AcpRequestHandler>{},
    Map<String, AcpNotificationHandler> notifications =
        const <String, AcpNotificationHandler>{},
  })  : requests = Map<String, AcpRequestHandler>.unmodifiable(requests),
        notifications =
            Map<String, AcpNotificationHandler>.unmodifiable(notifications) {
    _validate();
  }

  final Map<String, AcpRequestHandler> requests;
  final Map<String, AcpNotificationHandler> notifications;

  void requireHandlers(Iterable<String> requiredMethods) {
    final missing = requiredMethods
        .where((method) => !requests.containsKey(method))
        .toList()
      ..sort();
    if (missing.isNotEmpty) {
      throw AcpHandlerException(
        'acp_claimed_capability_missing_handler',
        'Advertised ACP capability has no matching request handler.',
        methods: missing,
      );
    }
  }

  void requireSide(AcpMethodHandlerSide side) {
    final wrongSide = <String>[];
    for (final method in <String>{
      ...requests.keys,
      ...notifications.keys,
    }) {
      final descriptor = acpMethodsByName[method]!;
      if (descriptor.handlerSide != side) {
        wrongSide.add(method);
      }
    }
    if (wrongSide.isNotEmpty) {
      wrongSide.sort();
      throw AcpHandlerException(
        'acp_handler_wrong_side',
        'ACP handler is registered on the wrong participant.',
        methods: wrongSide,
      );
    }
  }

  void _validate() {
    final invalid = <String>[];
    for (final method in requests.keys) {
      final descriptor = acpMethodsByName[method];
      if (descriptor == null || descriptor.requestDefinition == null) {
        invalid.add(method);
      }
    }
    for (final method in notifications.keys) {
      final descriptor = acpMethodsByName[method];
      if (descriptor == null || descriptor.notificationDefinition == null) {
        invalid.add(method);
      }
    }
    if (invalid.isNotEmpty) {
      invalid.sort();
      throw AcpHandlerException(
        'acp_invalid_handler_registration',
        'ACP handler does not match a stable method and message kind.',
        methods: invalid,
      );
    }
  }
}
