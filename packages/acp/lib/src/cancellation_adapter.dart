import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// Adapts local request cancellation to ACP `$/cancel_request`.
final class AcpRequestCancellationAdapter {
  const AcpRequestCancellationAdapter._();

  static Future<JsonValue> request({
    required JsonRpcPeer peer,
    required String method,
    required JsonValue params,
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async {
    final pending = peer.startRequest(
      method,
      params: params,
      cancellation: cancellation,
      timeout: timeout,
    );
    final registration = cancellation?.onCancel((reason) {
      unawaited(_sendCancel(peer, pending.id));
    });
    try {
      return await pending.response;
    } finally {
      registration?.dispose();
    }
  }

  static Future<void> _sendCancel(JsonRpcPeer peer, JsonRpcId id) async {
    try {
      await peer.notify(
        r'$/cancel_request',
        params: <String, Object?>{'requestId': id.toJson()},
      );
    } on Object catch (error) {
      try {
        peer.diagnostics.add(
          ProtocolDiagnostic(
            code: 'acp_cancel_send_failed',
            message: 'Failed to send ACP request cancellation.',
            requestId: id,
            method: r'$/cancel_request',
            details: <String, Object?>{
              'errorType': error.runtimeType.toString(),
            },
          ),
        );
      } on Object {
        // Caller diagnostics must not change cancellation state.
      }
    }
  }
}
