import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// Adapts local cancellation to MCP `notifications/cancelled`.
///
/// MCP cancellation does not terminate response correlation. The original
/// response is still awaited so a late success or error is consumed exactly
/// once and cannot be mis-associated with another request.
final class McpRequestCancellationAdapter {
  const McpRequestCancellationAdapter._();

  static Future<JsonValue> waitForResponse({
    required JsonRpcPendingRequest pending,
    required Future<void> Function(JsonRpcId id, String? reason)
        sendCancellation,
    required ProtocolDiagnosticSink diagnostics,
    ProtocolCancellationSignal? cancellation,
  }) async {
    final registration = cancellation?.onCancel((reason) {
      unawaited(
        _sendCancellation(
          pending.id,
          reason is String ? reason : null,
          sendCancellation,
          diagnostics,
        ),
      );
    });
    try {
      return await pending.response;
    } finally {
      registration?.dispose();
    }
  }

  static Future<void> _sendCancellation(
    JsonRpcId id,
    String? reason,
    Future<void> Function(JsonRpcId id, String? reason) sendCancellation,
    ProtocolDiagnosticSink diagnostics,
  ) async {
    try {
      await sendCancellation(id, reason);
    } on Object catch (error) {
      _diagnose(
        diagnostics,
        ProtocolDiagnostic(
          code: 'mcp_cancel_send_failed',
          message: 'Failed to send MCP request cancellation.',
          requestId: id,
          method: 'notifications/cancelled',
          details: <String, Object?>{
            'errorType': error.runtimeType.toString(),
          },
        ),
      );
    }
  }
}

void _diagnose(
  ProtocolDiagnosticSink diagnostics,
  ProtocolDiagnostic diagnostic,
) {
  try {
    diagnostics.add(diagnostic);
  } on Object {
    // Caller diagnostics must not change protocol state.
  }
}
