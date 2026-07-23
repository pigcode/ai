import 'dart:collection';

/// Resumption state for one logical SSE stream.
final class McpHttpEventCursor {
  const McpHttpEventCursor({
    required this.streamKey,
    required this.lastEventId,
    required this.retry,
  });

  final String streamKey;
  final String lastEventId;
  final Duration? retry;
}

abstract interface class McpHttpEventStore {
  McpHttpEventCursor? read(String streamKey);
  void write(McpHttpEventCursor cursor);
  void remove(String streamKey);
}

/// Bounded in-memory event cursor store.
final class McpMemoryHttpEventStore implements McpHttpEventStore {
  McpMemoryHttpEventStore({this.maxStreams = 64}) {
    if (maxStreams <= 0) {
      throw ArgumentError.value(maxStreams, 'maxStreams', 'Must be positive.');
    }
  }

  final int maxStreams;
  final LinkedHashMap<String, McpHttpEventCursor> _cursors =
      LinkedHashMap<String, McpHttpEventCursor>();

  int get length => _cursors.length;

  @override
  McpHttpEventCursor? read(String streamKey) => _cursors[streamKey];

  @override
  void write(McpHttpEventCursor cursor) {
    _cursors.remove(cursor.streamKey);
    if (_cursors.length == maxStreams) {
      _cursors.remove(_cursors.keys.first);
    }
    _cursors[cursor.streamKey] = cursor;
  }

  @override
  void remove(String streamKey) {
    _cursors.remove(streamKey);
  }
}
