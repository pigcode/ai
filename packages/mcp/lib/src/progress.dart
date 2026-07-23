import 'dart:async';
import 'dart:collection';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'generated/mcp_models.g.dart';

/// One validated progress update associated with an opaque progress token.
final class McpProgressEvent {
  McpProgressEvent(McpProgressNotificationParams params)
      : params = params,
        token = (params.toJson()! as Map<String, Object?>)['progressToken']!,
        progress =
            (params.toJson()! as Map<String, Object?>)['progress']! as num;

  final McpProgressNotificationParams params;
  final Object token;
  final num progress;
}

/// A single registered progress-token stream.
final class McpProgressOperation {
  McpProgressOperation._(this.token);

  final Object token;
  final StreamController<McpProgressEvent> _updates =
      StreamController<McpProgressEvent>.broadcast(sync: true);
  final List<McpProgressEvent> _events = <McpProgressEvent>[];
  var _closed = false;

  Stream<McpProgressEvent> get updates => _updates.stream;
  List<McpProgressEvent> get events =>
      List<McpProgressEvent>.unmodifiable(_events);
  bool get isClosed => _closed;

  void _add(McpProgressEvent event) {
    _events.add(event);
    _updates.add(event);
  }

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _updates.close();
  }
}

/// Correlates progress notifications without interpreting their opaque tokens.
final class McpProgressTracker {
  McpProgressTracker({
    ProtocolDiagnosticSink? diagnostics,
    this.maxOperations = 256,
    this.maxClosedTokens = 256,
  }) : diagnostics = diagnostics ??
            BoundedProtocolDiagnostics(maxEntries: maxOperations) {
    if (maxOperations <= 0) {
      throw ArgumentError.value(
        maxOperations,
        'maxOperations',
        'Must be positive.',
      );
    }
    if (maxClosedTokens <= 0) {
      throw ArgumentError.value(
        maxClosedTokens,
        'maxClosedTokens',
        'Must be positive.',
      );
    }
  }

  final ProtocolDiagnosticSink diagnostics;
  final int maxOperations;
  final int maxClosedTokens;
  final Map<Object, McpProgressOperation> _operations =
      <Object, McpProgressOperation>{};
  final LinkedHashSet<Object> _closedTokens = LinkedHashSet<Object>();

  int get activeCount => _operations.length;

  McpProgressOperation? register(McpProgressToken token) {
    final raw = token.toJson()!;
    if (_operations.containsKey(raw) || _closedTokens.contains(raw)) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'mcp_duplicate_progress_token',
          message: 'Ignored duplicate MCP progress token registration.',
          method: 'notifications/progress',
          details: <String, Object?>{'tokenType': raw.runtimeType.toString()},
        ),
      );
      return null;
    }
    if (_operations.length >= maxOperations) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'mcp_progress_operation_limit',
          message: 'Ignored MCP progress token because the tracker is full.',
          method: 'notifications/progress',
        ),
      );
      return null;
    }
    final operation = McpProgressOperation._(raw);
    _operations[raw] = operation;
    return operation;
  }

  bool handle(McpProgressNotificationParams params) {
    final event = McpProgressEvent(params);
    final operation = _operations[event.token];
    if (operation == null) {
      _diagnose(
        ProtocolDiagnostic(
          code: _closedTokens.contains(event.token)
              ? 'mcp_late_progress_token'
              : 'mcp_unknown_progress_token',
          message: 'Ignored MCP progress for an inactive opaque token.',
          method: 'notifications/progress',
          details: <String, Object?>{
            'tokenType': event.token.runtimeType.toString(),
          },
        ),
      );
      return false;
    }
    final previous =
        operation.events.isEmpty ? null : operation.events.last.progress;
    if (previous != null && event.progress <= previous) {
      _diagnose(
        ProtocolDiagnostic(
          code: event.progress == previous
              ? 'mcp_duplicate_progress'
              : 'mcp_non_monotonic_progress',
          message: 'Ignored duplicate or decreasing MCP progress.',
          method: 'notifications/progress',
        ),
      );
      return false;
    }
    operation._add(event);
    return true;
  }

  Future<bool> complete(McpProgressToken token) async {
    final raw = token.toJson()!;
    final operation = _operations.remove(raw);
    if (operation == null) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'mcp_unknown_progress_completion',
          message: 'Ignored completion for an inactive MCP progress token.',
          method: 'notifications/progress',
        ),
      );
      return false;
    }
    _rememberClosed(raw);
    await operation._close();
    return true;
  }

  void _rememberClosed(Object token) {
    if (_closedTokens.length == maxClosedTokens) {
      _closedTokens.remove(_closedTokens.first);
    }
    _closedTokens.add(token);
  }

  void _diagnose(ProtocolDiagnostic diagnostic) {
    try {
      diagnostics.add(diagnostic);
    } on Object {
      // Caller diagnostics must not change progress correlation.
    }
  }
}
