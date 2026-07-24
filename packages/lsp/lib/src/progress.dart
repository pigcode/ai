import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';

/// Immutable view of one work-done progress token.
final class LspWorkDoneProgress {
  LspWorkDoneProgress._({
    required this.token,
    required this.title,
    this.message,
    this.percentage,
    this.ended = false,
  });

  final Object token;
  final String title;
  final String? message;
  final int? percentage;
  final bool ended;

  LspWorkDoneProgress copyWith({
    String? message,
    int? percentage,
    bool? ended,
  }) =>
      LspWorkDoneProgress._(
        token: token,
        title: title,
        message: message ?? this.message,
        percentage: percentage ?? this.percentage,
        ended: ended ?? this.ended,
      );
}

/// Immutable view of partial results associated with one request.
final class LspPartialProgress {
  LspPartialProgress._({
    required this.token,
    required this.requestId,
    required List<JsonValue> values,
  }) : values = List<JsonValue>.unmodifiable(values);

  final Object token;
  final Object requestId;
  final List<JsonValue> values;
}

/// Connection-owned work-done and partial-result token registry.
final class LspProgressRegistry {
  LspProgressRegistry({required this.connectionId});

  final int connectionId;
  final Map<Object, LspWorkDoneProgress> _workDone =
      <Object, LspWorkDoneProgress>{};
  final Map<Object, LspPartialProgress> _partial =
      <Object, LspPartialProgress>{};

  void beginWorkDone(Object token, {required String title}) {
    _validateToken(token);
    if (_workDone.containsKey(token) || _partial.containsKey(token)) {
      throw const LspProgressException(
        'lsp_progress_token_duplicate',
        'LSP progress token is already registered.',
      );
    }
    _workDone[token] = LspWorkDoneProgress._(
      token: token,
      title: title,
    );
  }

  void reportWorkDone(
    Object token, {
    String? message,
    int? percentage,
  }) {
    final current = workDone(token);
    if (current.ended) {
      throw const LspProgressException(
        'lsp_progress_already_ended',
        'LSP work-done progress has already ended.',
      );
    }
    if (percentage != null && (percentage < 0 || percentage > 100)) {
      throw const LspProgressException(
        'lsp_progress_percentage_invalid',
        'LSP progress percentage must be between 0 and 100.',
      );
    }
    _workDone[token] = current.copyWith(
      message: message,
      percentage: percentage,
    );
  }

  void endWorkDone(Object token, {String? message}) {
    final current = workDone(token);
    if (current.ended) {
      throw const LspProgressException(
        'lsp_progress_already_ended',
        'LSP work-done progress has already ended.',
      );
    }
    _workDone[token] = current.copyWith(message: message, ended: true);
  }

  LspWorkDoneProgress workDone(Object token) {
    final progress = _workDone[token];
    if (progress == null) {
      throw const LspProgressException(
        'lsp_progress_token_unknown',
        'Unknown LSP work-done progress token.',
      );
    }
    return progress;
  }

  void registerPartial(Object token, {required Object requestId}) {
    _validateToken(token);
    _validateToken(requestId);
    if (_workDone.containsKey(token) || _partial.containsKey(token)) {
      throw const LspProgressException(
        'lsp_progress_token_duplicate',
        'LSP progress token is already registered.',
      );
    }
    _partial[token] = LspPartialProgress._(
      token: token,
      requestId: requestId,
      values: const <JsonValue>[],
    );
  }

  void addPartial(Object token, JsonValue value) {
    final current = partial(token);
    _partial[token] = LspPartialProgress._(
      token: token,
      requestId: current.requestId,
      values: <JsonValue>[
        ...current.values,
        freezeJsonValue(value),
      ],
    );
  }

  LspPartialProgress partial(Object token) {
    final progress = _partial[token];
    if (progress == null) {
      throw const LspProgressException(
        'lsp_progress_token_unknown',
        'Unknown LSP partial-result token.',
      );
    }
    return progress;
  }

  void _validateToken(Object token) {
    if (token is! String && token is! int) {
      throw const LspProgressException(
        'lsp_progress_token_invalid',
        'LSP progress token must be a string or integer.',
      );
    }
  }
}
