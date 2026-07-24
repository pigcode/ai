import 'errors.dart';

final class DapProgressState {
  const DapProgressState({
    required this.progressId,
    required this.title,
    this.requestId,
    this.message,
    this.percentage,
    this.ended = false,
  });

  final String progressId;
  final String title;
  final int? requestId;
  final String? message;
  final int? percentage;
  final bool ended;

  DapProgressState copyWith({
    String? message,
    int? percentage,
    bool? ended,
  }) =>
      DapProgressState(
        progressId: progressId,
        title: title,
        requestId: requestId,
        message: message ?? this.message,
        percentage: percentage ?? this.percentage,
        ended: ended ?? this.ended,
      );
}

final class DapProgressRegistry {
  final Map<String, DapProgressState> _progress = <String, DapProgressState>{};

  void start({
    required String progressId,
    required String title,
    int? requestId,
  }) {
    if (progressId.isEmpty || _progress.containsKey(progressId)) {
      throw const DapProgressException(
        'dap_progress_duplicate_or_invalid',
        'DAP progress id must be non-empty and unique.',
      );
    }
    _progress[progressId] = DapProgressState(
      progressId: progressId,
      title: title,
      requestId: requestId,
    );
  }

  void update({
    required String progressId,
    String? message,
    int? percentage,
  }) {
    final current = progress(progressId);
    if (current.ended) {
      throw const DapProgressException(
        'dap_progress_already_ended',
        'DAP progress has already ended.',
      );
    }
    if (percentage != null && (percentage < 0 || percentage > 100)) {
      throw const DapProgressException(
        'dap_progress_percentage_invalid',
        'DAP progress percentage must be between 0 and 100.',
      );
    }
    _progress[progressId] = current.copyWith(
      message: message,
      percentage: percentage,
    );
  }

  void end({required String progressId, String? message}) {
    final current = progress(progressId);
    if (current.ended) {
      throw const DapProgressException(
        'dap_progress_already_ended',
        'DAP progress has already ended.',
      );
    }
    _progress[progressId] = current.copyWith(
      message: message,
      ended: true,
    );
  }

  DapProgressState progress(String progressId) {
    final state = _progress[progressId];
    if (state == null) {
      throw const DapProgressException(
        'dap_progress_unknown',
        'Unknown DAP progress id.',
      );
    }
    return state;
  }
}
