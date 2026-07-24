import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'capabilities.dart';
import 'errors.dart';

final class DapCancelIntent {
  DapCancelIntent._(Map<String, Object?> arguments)
      : _arguments = freezeJsonObject(arguments);

  final JsonObject _arguments;

  JsonObject toJson() => _arguments;
}

/// Tracks cancellation intent without claiming request completion.
final class DapCancellationRegistry {
  DapCancellationRegistry({required this.capabilities});

  final DapCapabilitySnapshot capabilities;
  final Set<int> _requests = <int>{};
  final Set<String> _progress = <String>{};
  final Set<String> _intents = <String>{};

  void trackRequest(int requestId) {
    if (requestId <= 0 || !_requests.add(requestId)) {
      throw const DapCancellationException(
        'dap_cancel_request_duplicate_or_invalid',
        'DAP tracked request id must be positive and unique.',
      );
    }
  }

  void trackProgress(String progressId) {
    if (progressId.isEmpty || !_progress.add(progressId)) {
      throw const DapCancellationException(
        'dap_cancel_progress_duplicate_or_invalid',
        'DAP tracked progress id must be non-empty and unique.',
      );
    }
  }

  DapCancelIntent cancel({int? requestId, String? progressId}) {
    if (!capabilities.supportsCommand('cancel')) {
      throw const DapCancellationException(
        'dap_cancel_unsupported',
        'Debug adapter did not advertise supportsCancelRequest.',
      );
    }
    if ((requestId == null) == (progressId == null)) {
      throw const DapCancellationException(
        'dap_cancel_target_invalid',
        'DAP cancel requires exactly one requestId or progressId.',
      );
    }
    final key =
        requestId == null ? 'progress:$progressId' : 'request:$requestId';
    if (requestId != null && !_requests.contains(requestId) ||
        progressId != null && !_progress.contains(progressId)) {
      throw const DapCancellationException(
        'dap_cancel_target_unknown',
        'DAP cancel target is not active.',
      );
    }
    if (!_intents.add(key)) {
      throw const DapCancellationException(
        'dap_cancel_duplicate',
        'DAP cancel intent was already recorded.',
      );
    }
    return DapCancelIntent._(<String, Object?>{
      if (requestId != null) 'requestId': requestId,
      if (progressId != null) 'progressId': progressId,
    });
  }

  bool isRequestPending(int requestId) => _requests.contains(requestId);

  void completeRequest(int requestId) {
    if (!_requests.remove(requestId)) {
      throw const DapCancellationException(
        'dap_cancel_target_unknown',
        'DAP request is not active.',
      );
    }
  }
}
