import 'errors.dart';

/// A disposable cancellation callback registration.
abstract interface class ProtocolCancellationRegistration {
  void dispose();
}

/// Read-only protocol cancellation state.
abstract interface class ProtocolCancellationSignal {
  bool get isCancelled;
  Object? get reason;

  ProtocolCancellationRegistration onCancel(
    void Function(Object? reason) listener,
  );

  void throwIfCancelled();
}

/// Owns and triggers one idempotent protocol cancellation signal.
final class ProtocolCancellationSource {
  ProtocolCancellationSource() : _signal = _ProtocolCancellationSignal();

  final _ProtocolCancellationSignal _signal;

  ProtocolCancellationSignal get signal => _signal;

  /// Cancels once and returns whether this invocation won the race.
  bool cancel([Object? reason]) => _signal._cancel(reason);
}

final class _ProtocolCancellationSignal implements ProtocolCancellationSignal {
  final Map<int, void Function(Object?)> _listeners =
      <int, void Function(Object?)>{};
  var _nextListenerId = 0;
  bool _isCancelled = false;
  Object? _reason;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Object? get reason => _reason;

  @override
  ProtocolCancellationRegistration onCancel(
    void Function(Object? reason) listener,
  ) {
    if (_isCancelled) {
      listener(_reason);
      return const _DisposedCancellationRegistration();
    }
    final id = _nextListenerId++;
    _listeners[id] = listener;
    return _CancellationRegistration(this, id);
  }

  @override
  void throwIfCancelled() {
    if (_isCancelled) {
      throw ProtocolCancellationException(reason: _reason);
    }
  }

  bool _cancel(Object? reason) {
    if (_isCancelled) {
      return false;
    }
    _isCancelled = true;
    _reason = reason;
    final listeners = _listeners.values.toList(growable: false);
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener(reason);
      } on Object {
        // Cancellation must reach every registered listener.
      }
    }
    return true;
  }

  void _remove(int id) {
    _listeners.remove(id);
  }
}

final class _CancellationRegistration
    implements ProtocolCancellationRegistration {
  _CancellationRegistration(this.signal, this.id);

  _ProtocolCancellationSignal? signal;
  final int id;

  @override
  void dispose() {
    signal?._remove(id);
    signal = null;
  }
}

final class _DisposedCancellationRegistration
    implements ProtocolCancellationRegistration {
  const _DisposedCancellationRegistration();

  @override
  void dispose() {}
}
