import 'dart:async';
import 'dart:collection';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../server.dart';

typedef McpHttpServerFactory = McpServer Function(
  ProtocolMessageTransport<JsonRpcMessage> transport,
);

final class McpHttpServerEvent {
  const McpHttpServerEvent({
    required this.id,
    required this.streamKey,
    required this.sequence,
    required this.message,
  });

  final String id;
  final String streamKey;
  final int sequence;
  final JsonRpcMessage message;
}

/// Bounded event retention shared by all SSE streams in one session.
final class McpHttpServerEventStore {
  McpHttpServerEventStore({this.maxEvents = 256}) {
    if (maxEvents <= 0) {
      throw ArgumentError.value(maxEvents, 'maxEvents', 'Must be positive.');
    }
  }

  final int maxEvents;
  final Queue<McpHttpServerEvent> _events = Queue<McpHttpServerEvent>();
  final Map<String, McpHttpServerEvent> _byId = <String, McpHttpServerEvent>{};

  int get length => _events.length;

  McpHttpServerEvent? byId(String id) => _byId[id];

  List<McpHttpServerEvent> after(
    String streamKey, {
    int afterSequence = 0,
  }) {
    return List<McpHttpServerEvent>.unmodifiable(
      _events.where(
        (event) =>
            event.streamKey == streamKey && event.sequence > afterSequence,
      ),
    );
  }

  void add(McpHttpServerEvent event) {
    if (_events.length == maxEvents) {
      final removed = _events.removeFirst();
      _byId.remove(removed.id);
    }
    _events.addLast(event);
    _byId[event.id] = event;
  }

  void removeStream(String streamKey) {
    final removed = _events
        .where((event) => event.streamKey == streamKey)
        .toList(growable: false);
    _events.removeWhere((event) => event.streamKey == streamKey);
    for (final event in removed) {
      _byId.remove(event.id);
    }
  }

  void clear() {
    _events.clear();
    _byId.clear();
  }
}

/// One resumable server-side SSE stream.
final class McpHttpServerStream {
  McpHttpServerStream._({
    required this.streamKey,
    required McpHttpServerSession owner,
    required this.isSideChannel,
  }) : _owner = owner;

  final String streamKey;
  final bool isSideChannel;
  final McpHttpServerSession _owner;
  final StreamController<McpHttpServerEvent> _live =
      StreamController<McpHttpServerEvent>.broadcast(sync: true);
  final Completer<McpHttpServerEvent> _first = Completer<McpHttpServerEvent>();
  var _nextSequence = 1;
  var _terminal = false;

  Future<McpHttpServerEvent> get firstEvent => _first.future;
  bool get isTerminal => _terminal;

  Stream<McpHttpServerEvent> events({int afterSequence = 0}) async* {
    final pending = Queue<McpHttpServerEvent>();
    Completer<void>? wake;
    var liveDone = false;
    final subscription = _live.stream.listen(
      (event) {
        pending.addLast(event);
        wake?.complete();
        wake = null;
      },
      onDone: () {
        liveDone = true;
        wake?.complete();
        wake = null;
      },
    );
    final replay = _owner.eventStore.after(
      streamKey,
      afterSequence: afterSequence,
    );
    var lastSequence = afterSequence;
    try {
      for (final event in replay) {
        if (event.sequence > lastSequence) {
          lastSequence = event.sequence;
          yield event;
        }
      }
      while (true) {
        while (pending.isNotEmpty) {
          final event = pending.removeFirst();
          if (event.sequence > lastSequence) {
            lastSequence = event.sequence;
            yield event;
          }
        }
        if (_terminal || liveDone) {
          return;
        }
        wake = Completer<void>();
        if (pending.isNotEmpty || _terminal || liveDone) {
          wake!.complete();
        }
        await wake!.future;
      }
    } finally {
      await subscription.cancel();
    }
  }

  void _add(JsonRpcMessage message, {required bool terminal}) {
    final sequence = _nextSequence++;
    final event = McpHttpServerEvent(
      id: '$streamKey:$sequence',
      streamKey: streamKey,
      sequence: sequence,
      message: message,
    );
    _owner.eventStore.add(event);
    if (!_first.isCompleted) {
      _first.complete(event);
    }
    _live.add(event);
    if (terminal) {
      _terminal = true;
      unawaited(_live.close());
    }
  }

  Future<void> _close() async {
    _terminal = true;
    if (!isSideChannel && !_first.isCompleted) {
      _first.completeError(
        const ProtocolTransportException(
          'mcp_http_session_closed',
          'MCP HTTP session closed before producing a response.',
        ),
      );
    }
    if (!_live.isClosed) {
      await _live.close();
    }
  }
}

/// One framework-neutral MCP server session.
final class McpHttpServerSession {
  McpHttpServerSession({
    required this.id,
    required McpHttpServerFactory serverFactory,
    this.maxStreams = 16,
    int maxEvents = 256,
  }) : eventStore = McpHttpServerEventStore(maxEvents: maxEvents) {
    if (maxStreams <= 0) {
      throw ArgumentError.value(maxStreams, 'maxStreams', 'Must be positive.');
    }
    _transport = _SessionMessageTransport(this);
    server = serverFactory(_transport);
  }

  final String id;
  final int maxStreams;
  final McpHttpServerEventStore eventStore;
  late final _SessionMessageTransport _transport;
  late final McpServer server;
  final Map<JsonRpcId, McpHttpServerStream> _requestStreams =
      <JsonRpcId, McpHttpServerStream>{};
  final LinkedHashMap<String, McpHttpServerStream> _streams =
      LinkedHashMap<String, McpHttpServerStream>();
  final List<McpHttpServerStream> _sideChannels = <McpHttpServerStream>[];
  var _nextStreamId = 1;
  var _sideIndex = 0;
  var _closed = false;

  bool get isClosed => _closed;
  int get streamCount => _streams.length;

  McpHttpServerStream beginRequest(JsonRpcRequest request) {
    _ensureOpen();
    if (_requestStreams.containsKey(request.id)) {
      throw StateError('Duplicate in-flight MCP HTTP request ID.');
    }
    final stream = _createStream(isSideChannel: false);
    _requestStreams[request.id] = stream;
    _transport.addIncoming(request);
    return stream;
  }

  void accept(JsonRpcMessage message) {
    _ensureOpen();
    _transport.addIncoming(message);
  }

  McpHttpServerStream openSideChannel() {
    _ensureOpen();
    final stream = _createStream(isSideChannel: true);
    _sideChannels.add(stream);
    return stream;
  }

  McpHttpServerStream? streamForEvent(String eventId) {
    final event = eventStore.byId(eventId);
    if (event == null) {
      return null;
    }
    final stream = _streams[event.streamKey];
    if (stream != null && stream.isSideChannel) {
      _activateSideChannel(stream);
    }
    return stream;
  }

  McpHttpServerEvent? eventForId(String eventId) => eventStore.byId(eventId);

  void discardJsonStream(McpHttpServerStream stream) {
    _streams.remove(stream.streamKey);
    eventStore.removeStream(stream.streamKey);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await server.close();
    for (final stream in _streams.values.toList(growable: false)) {
      await stream._close();
    }
    _streams.clear();
    _requestStreams.clear();
    _sideChannels.clear();
    eventStore.clear();
  }

  McpHttpServerStream _createStream({required bool isSideChannel}) {
    if (_streams.length == maxStreams) {
      final oldestKey = _streams.keys.first;
      final oldest = _streams.remove(oldestKey)!;
      _sideChannels.remove(oldest);
      eventStore.removeStream(oldestKey);
      unawaited(oldest._close());
    }
    final stream = McpHttpServerStream._(
      streamKey: '$id-stream-${_nextStreamId++}',
      owner: this,
      isSideChannel: isSideChannel,
    );
    _streams[stream.streamKey] = stream;
    return stream;
  }

  void _routeOutbound(JsonRpcMessage message) {
    if (_closed) {
      throw const ProtocolTransportException(
        'mcp_http_session_closed',
        'MCP HTTP session is closed.',
      );
    }
    if (message
        case JsonRpcSuccessResponse(:final id) ||
            JsonRpcErrorResponse(:final id)) {
      final requestStream = _requestStreams.remove(id);
      if (requestStream != null) {
        requestStream._add(message, terminal: true);
        return;
      }
    }
    if (message is JsonRpcRequest && _sideChannels.isNotEmpty) {
      if (_sideIndex >= _sideChannels.length) {
        _sideIndex = 0;
      }
      _sideChannels[_sideIndex++]._add(message, terminal: false);
      return;
    }
    final activeRequest = _requestStreams.values.firstOrNull;
    if (activeRequest != null) {
      activeRequest._add(message, terminal: false);
      return;
    }
    if (_sideChannels.isEmpty) {
      final stream = openSideChannel();
      stream._add(message, terminal: false);
      return;
    }
    if (_sideIndex >= _sideChannels.length) {
      _sideIndex = 0;
    }
    _sideChannels[_sideIndex++]._add(message, terminal: false);
  }

  void _activateSideChannel(McpHttpServerStream stream) {
    if (!_sideChannels.contains(stream)) {
      _sideChannels.add(stream);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw const ProtocolTransportException(
        'mcp_http_session_closed',
        'MCP HTTP session is closed.',
      );
    }
  }
}

final class _SessionMessageTransport
    implements ProtocolMessageTransport<JsonRpcMessage> {
  _SessionMessageTransport(this.owner);

  final McpHttpServerSession owner;
  final StreamController<JsonRpcMessage> _incoming =
      StreamController<JsonRpcMessage>(sync: true);
  var _closed = false;

  @override
  Stream<JsonRpcMessage> get incomingMessages => _incoming.stream;

  void addIncoming(JsonRpcMessage message) {
    if (_closed) {
      throw const ProtocolTransportException(
        'mcp_http_session_closed',
        'MCP HTTP session input is closed.',
      );
    }
    _incoming.add(message);
  }

  @override
  Future<void> sendMessage(JsonRpcMessage message) async {
    owner._routeOutbound(message);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}
