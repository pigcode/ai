import 'dart:async';
import 'dart:collection';

import 'json_rpc/id.dart';
import 'json_value.dart';

/// A safe, structured protocol diagnostic.
final class ProtocolDiagnostic {
  factory ProtocolDiagnostic({
    required String code,
    required String message,
    JsonRpcId? requestId,
    String? method,
    JsonObject details = const <String, Object?>{},
  }) {
    return ProtocolDiagnostic._(
      code: code,
      message: message,
      requestId: requestId,
      method: method,
      details: freezeJsonObject(details),
    );
  }

  const ProtocolDiagnostic._({
    required this.code,
    required this.message,
    required this.requestId,
    required this.method,
    required this.details,
  });

  final String code;
  final String message;
  final JsonRpcId? requestId;
  final String? method;
  final JsonObject details;
}

/// Caller-supplied destination for bounded protocol diagnostics.
abstract interface class ProtocolDiagnosticSink {
  int get capacity;
  void add(ProtocolDiagnostic diagnostic);
}

/// Retains the newest diagnostics in a bounded in-memory queue.
final class BoundedProtocolDiagnostics implements ProtocolDiagnosticSink {
  BoundedProtocolDiagnostics({required this.maxEntries}) {
    if (maxEntries <= 0) {
      throw ArgumentError.value(
        maxEntries,
        'maxEntries',
        'Must be positive.',
      );
    }
  }

  final int maxEntries;
  final Queue<ProtocolDiagnostic> _entries = Queue<ProtocolDiagnostic>();
  final StreamController<ProtocolDiagnostic> _changes =
      StreamController<ProtocolDiagnostic>.broadcast(sync: true);
  int _droppedCount = 0;

  @override
  int get capacity => maxEntries;

  List<ProtocolDiagnostic> get entries =>
      List<ProtocolDiagnostic>.unmodifiable(_entries);

  int get droppedCount => _droppedCount;

  Stream<ProtocolDiagnostic> get changes => _changes.stream;

  Future<ProtocolDiagnostic> get next {
    if (_entries.isNotEmpty) {
      return Future<ProtocolDiagnostic>.value(_entries.last);
    }
    return changes.first;
  }

  Future<void> waitForEntries(int count) {
    if (_entries.length >= count) {
      return Future<void>.value();
    }
    return changes.firstWhere((_) => _entries.length >= count).then((_) {});
  }

  @override
  void add(ProtocolDiagnostic diagnostic) {
    if (_entries.length == maxEntries) {
      _entries.removeFirst();
      _droppedCount += 1;
    }
    _entries.addLast(diagnostic);
    if (!_changes.isClosed) {
      _changes.add(diagnostic);
    }
  }

  Future<void> dispose() => _changes.close();
}
