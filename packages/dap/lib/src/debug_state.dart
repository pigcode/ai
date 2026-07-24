import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';

final class DapThreadState {
  const DapThreadState({required this.id, required this.name});

  final int id;
  final String name;
}

final class DapFrameState {
  const DapFrameState({
    required this.id,
    required this.name,
    required this.line,
    required this.column,
  });

  final int id;
  final String name;
  final int line;
  final int column;
}

final class DapScopeState {
  const DapScopeState({
    required this.name,
    required this.variablesReference,
    required this.expensive,
  });

  final String name;
  final int variablesReference;
  final bool expensive;
}

final class DapVariableState {
  const DapVariableState({
    required this.name,
    required this.value,
    required this.variablesReference,
  });

  final String name;
  final String value;
  final int variablesReference;
}

/// Connection/session/pause-scoped in-memory debug state.
final class DapDebugState {
  DapDebugState({required this.connectionId});

  final int connectionId;
  int sessionGeneration = 1;
  int pauseGeneration = 0;
  bool _disconnected = false;
  final Map<int, DapThreadState> _threads = <int, DapThreadState>{};
  final Set<int> _pausedThreads = <int>{};
  final Map<int, List<DapFrameState>> _frames = <int, List<DapFrameState>>{};
  final Map<int, List<DapScopeState>> _scopes = <int, List<DapScopeState>>{};
  final Map<int, List<DapVariableState>> _variables =
      <int, List<DapVariableState>>{};

  List<DapThreadState> get threads =>
      List<DapThreadState>.unmodifiable(_threads.values);
  bool get disconnected => _disconnected;

  void updateThreads(List<Map<String, Object?>> values) {
    _requireConnected();
    final next = <int, DapThreadState>{};
    for (final value in values) {
      freezeJsonObject(value);
      final id = value['id'];
      final name = value['name'];
      if (id is! int || name is! String) {
        throw const DapDebugStateException(
          'dap_thread_invalid',
          'DAP thread requires integer id and string name.',
        );
      }
      next[id] = DapThreadState(id: id, name: name);
    }
    _threads
      ..clear()
      ..addAll(next);
  }

  int stop({required int threadId, required String reason}) {
    _requireConnected();
    if (reason.isEmpty) {
      throw const DapDebugStateException(
        'dap_stop_reason_empty',
        'DAP stop reason must be non-empty.',
      );
    }
    pauseGeneration += 1;
    _pausedThreads.add(threadId);
    _clearPauseData();
    return pauseGeneration;
  }

  bool isPaused(int threadId) => _pausedThreads.contains(threadId);

  void continueThread(int threadId) {
    _requirePause(threadId, pauseGeneration);
    _pausedThreads.remove(threadId);
    pauseGeneration += 1;
    _clearPauseData();
  }

  void setStackFrames({
    required int threadId,
    required int pauseGeneration,
    required List<Map<String, Object?>> frames,
  }) {
    _requirePause(threadId, pauseGeneration);
    _frames[threadId] = List<DapFrameState>.unmodifiable(
      frames.map((frame) {
        freezeJsonObject(frame);
        return DapFrameState(
          id: frame['id']! as int,
          name: frame['name']! as String,
          line: frame['line']! as int,
          column: frame['column']! as int,
        );
      }),
    );
  }

  List<DapFrameState> stackFrames(int threadId) {
    _requirePause(threadId, pauseGeneration);
    return _frames[threadId] ?? const <DapFrameState>[];
  }

  void setScopes({
    required int frameId,
    required int pauseGeneration,
    required List<Map<String, Object?>> scopes,
  }) {
    _requireCurrentPause(pauseGeneration);
    _scopes[frameId] = List<DapScopeState>.unmodifiable(
      scopes.map((scope) {
        freezeJsonObject(scope);
        return DapScopeState(
          name: scope['name']! as String,
          variablesReference: scope['variablesReference']! as int,
          expensive: scope['expensive']! as bool,
        );
      }),
    );
  }

  List<DapScopeState> scopes(int frameId) {
    _requireCurrentPause(pauseGeneration);
    return _scopes[frameId] ?? const <DapScopeState>[];
  }

  void setVariables({
    required int variablesReference,
    required int pauseGeneration,
    required List<Map<String, Object?>> variables,
  }) {
    _requireCurrentPause(pauseGeneration);
    _variables[variablesReference] = List<DapVariableState>.unmodifiable(
      variables.map((variable) {
        freezeJsonObject(variable);
        return DapVariableState(
          name: variable['name']! as String,
          value: variable['value']! as String,
          variablesReference: variable['variablesReference']! as int,
        );
      }),
    );
  }

  List<DapVariableState> variables(int variablesReference) {
    _requireCurrentPause(pauseGeneration);
    return _variables[variablesReference] ?? const <DapVariableState>[];
  }

  void restart() {
    _requireConnected();
    sessionGeneration += 1;
    pauseGeneration += 1;
    _pausedThreads.clear();
    _clearPauseData();
  }

  void disconnect() {
    if (_disconnected) {
      return;
    }
    _disconnected = true;
    sessionGeneration += 1;
    pauseGeneration += 1;
    _pausedThreads.clear();
    _clearPauseData();
  }

  void _requirePause(int threadId, int expectedGeneration) {
    _requireCurrentPause(expectedGeneration);
    if (!_pausedThreads.contains(threadId)) {
      throw const DapDebugStateException(
        'dap_thread_not_stopped',
        'DAP thread is not stopped in the current pause generation.',
      );
    }
  }

  void _requireCurrentPause(int expectedGeneration) {
    _requireConnected();
    if (expectedGeneration != pauseGeneration || _pausedThreads.isEmpty) {
      throw const DapDebugStateException(
        'dap_reference_stale',
        'DAP state belongs to a stale pause generation.',
      );
    }
  }

  void _requireConnected() {
    if (_disconnected) {
      throw const DapDebugStateException(
        'dap_session_disconnected',
        'DAP debug state is disconnected.',
      );
    }
  }

  void _clearPauseData() {
    _frames.clear();
    _scopes.clear();
    _variables.clear();
  }
}
