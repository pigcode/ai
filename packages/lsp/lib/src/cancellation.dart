import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';

/// Immutable terminal record for one canceled or completed request.
final class LspCancellationCompletion {
  LspCancellationCompletion._({
    required this.requestId,
    required this.method,
    required this.cancelRequested,
    required this.lateAfterCancel,
    required List<JsonValue> partialValues,
    this.result,
    this.remoteErrorCode,
    this.remoteErrorMessage,
  }) : partialValues = List<JsonValue>.unmodifiable(partialValues);

  final Object requestId;
  final String method;
  final bool cancelRequested;
  final bool lateAfterCancel;
  final List<JsonValue> partialValues;
  final JsonValue result;
  final int? remoteErrorCode;
  final String? remoteErrorMessage;
}

final class _TrackedCancellation {
  _TrackedCancellation({required this.requestId, required this.method});

  final Object requestId;
  final String method;
  bool cancelRequested = false;
  final List<JsonValue> partialValues = <JsonValue>[];
}

/// Connection-owned cancellation intent and late-response tombstones.
final class LspCancellationRegistry {
  LspCancellationRegistry({required this.connectionId});

  final int connectionId;
  final Map<Object, _TrackedCancellation> _pending =
      <Object, _TrackedCancellation>{};
  final Map<Object, LspCancellationCompletion> _tombstones =
      <Object, LspCancellationCompletion>{};

  void track({required Object requestId, required String method}) {
    _validateId(requestId);
    if (_pending.containsKey(requestId) || _tombstones.containsKey(requestId)) {
      throw const LspCancellationException(
        'lsp_request_duplicate',
        'LSP request id is already tracked.',
      );
    }
    _pending[requestId] = _TrackedCancellation(
      requestId: requestId,
      method: method,
    );
  }

  JsonObject requestCancel(Object requestId) {
    final tracked = _requirePending(requestId);
    if (tracked.cancelRequested) {
      throw const LspCancellationException(
        'lsp_cancel_duplicate',
        'LSP cancellation intent was already sent.',
      );
    }
    tracked.cancelRequested = true;
    return freezeJsonObject(<String, Object?>{
      'jsonrpc': '2.0',
      'method': r'$/cancelRequest',
      'params': <String, Object?>{'id': requestId},
    });
  }

  void addPartial(Object requestId, JsonValue value) {
    final tracked = _requirePending(requestId);
    tracked.partialValues.add(freezeJsonValue(value));
  }

  LspCancellationCompletion completeSuccess(
    Object requestId,
    JsonValue result,
  ) {
    final tracked = _takePending(requestId);
    return _finish(
      tracked,
      result: freezeJsonValue(result),
    );
  }

  LspCancellationCompletion completeError(
    Object requestId, {
    required int code,
    required String message,
  }) {
    final tracked = _takePending(requestId);
    return _finish(
      tracked,
      remoteErrorCode: code,
      remoteErrorMessage: message,
    );
  }

  LspCancellationCompletion tombstone(Object requestId) {
    final completion = _tombstones[requestId];
    if (completion == null) {
      throw const LspCancellationException(
        'lsp_request_unknown',
        'Unknown LSP request id.',
      );
    }
    return completion;
  }

  _TrackedCancellation _requirePending(Object requestId) {
    if (_tombstones.containsKey(requestId)) {
      throw const LspCancellationException(
        'lsp_response_tombstoned',
        'LSP request already has a terminal response tombstone.',
      );
    }
    final tracked = _pending[requestId];
    if (tracked == null) {
      throw const LspCancellationException(
        'lsp_request_unknown',
        'Unknown LSP request id.',
      );
    }
    return tracked;
  }

  _TrackedCancellation _takePending(Object requestId) {
    final tracked = _requirePending(requestId);
    _pending.remove(requestId);
    return tracked;
  }

  LspCancellationCompletion _finish(
    _TrackedCancellation tracked, {
    JsonValue result,
    int? remoteErrorCode,
    String? remoteErrorMessage,
  }) {
    final completion = LspCancellationCompletion._(
      requestId: tracked.requestId,
      method: tracked.method,
      cancelRequested: tracked.cancelRequested,
      lateAfterCancel: tracked.cancelRequested,
      partialValues: tracked.partialValues,
      result: result,
      remoteErrorCode: remoteErrorCode,
      remoteErrorMessage: remoteErrorMessage,
    );
    _tombstones[tracked.requestId] = completion;
    return completion;
  }

  void _validateId(Object requestId) {
    if (requestId is! String && requestId is! int) {
      throw const LspCancellationException(
        'lsp_request_id_invalid',
        'LSP request id must be a string or integer.',
      );
    }
  }
}
