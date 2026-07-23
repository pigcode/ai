import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../version.dart';
import 'server_session.dart';
import 'session.dart';

final class McpHttpEndpointRequest {
  McpHttpEndpointRequest({
    required this.method,
    required this.uri,
    Map<String, String> headers = const <String, String>{},
    required this.body,
    this.remoteAddress,
  }) : headers = Map<String, String>.unmodifiable(
          headers.map(
            (name, value) => MapEntry(name.toLowerCase(), value),
          ),
        );

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Stream<List<int>> body;
  final String? remoteAddress;

  String? header(String name) => headers[name.toLowerCase()];
}

final class McpHttpEndpointResponse {
  McpHttpEndpointResponse({
    required this.statusCode,
    Map<String, String> headers = const <String, String>{},
    Stream<List<int>>? body,
  })  : headers = Map<String, String>.unmodifiable(headers),
        body = body ?? const Stream<List<int>>.empty();

  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> body;
}

/// Framework-neutral Streamable HTTP endpoint.
final class McpHttpEndpoint {
  McpHttpEndpoint({
    required this.path,
    required Iterable<String> allowedHosts,
    Iterable<String> allowedOrigins = const <String>[],
    Iterable<String> acceptedProtocolVersions = const <String>[
      mcpProtocolVersion,
    ],
    required this.createSessionId,
    required this.serverFactory,
    ProtocolLimits? limits,
    this.maxSessions = 64,
    this.maxStreamsPerSession = 16,
    this.maxEventsPerSession = 256,
    this.maxSseEventsPerResponse = 0,
    this.maxSseEventsPerSideChannelResponse = 0,
    this.pollRetry = const Duration(milliseconds: 100),
  })  : allowedHosts = Set<String>.unmodifiable(
          allowedHosts.map((value) => value.toLowerCase()),
        ),
        allowedOrigins = Set<String>.unmodifiable(allowedOrigins),
        acceptedProtocolVersions =
            Set<String>.unmodifiable(acceptedProtocolVersions),
        limits = limits ?? ProtocolLimits.defaults {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'Must be an absolute path.');
    }
    if (this.allowedHosts.isEmpty) {
      throw ArgumentError.value(
        allowedHosts,
        'allowedHosts',
        'At least one authorized Host is required.',
      );
    }
    if (this.acceptedProtocolVersions.isEmpty) {
      throw ArgumentError.value(
        acceptedProtocolVersions,
        'acceptedProtocolVersions',
        'At least one MCP protocol version is required.',
      );
    }
    if (maxSessions <= 0 ||
        maxStreamsPerSession <= 0 ||
        maxEventsPerSession <= 0 ||
        maxSseEventsPerResponse < 0 ||
        maxSseEventsPerSideChannelResponse < 0) {
      throw ArgumentError('MCP HTTP endpoint limits must be positive.');
    }
    if (pollRetry.isNegative) {
      throw ArgumentError.value(
        pollRetry,
        'pollRetry',
        'Must not be negative.',
      );
    }
  }

  final String path;
  final Set<String> allowedHosts;
  final Set<String> allowedOrigins;
  final Set<String> acceptedProtocolVersions;
  final String Function() createSessionId;
  final McpHttpServerFactory serverFactory;
  final ProtocolLimits limits;
  final int maxSessions;
  final int maxStreamsPerSession;
  final int maxEventsPerSession;
  final int maxSseEventsPerResponse;
  final int maxSseEventsPerSideChannelResponse;
  final Duration pollRetry;
  final Map<String, McpHttpServerSession> _sessions =
      <String, McpHttpServerSession>{};
  final JsonRpcCodec _codec = const JsonRpcCodec();
  var _closed = false;

  int get sessionCount => _sessions.length;

  Future<McpHttpEndpointResponse> handle(
    McpHttpEndpointRequest request,
  ) async {
    if (_closed) {
      return _empty(503);
    }
    if (request.uri.path != path) {
      return _empty(404);
    }
    if (!_authorizedHost(request.header('host')) ||
        !_authorizedOrigin(request.header('origin'))) {
      return _empty(403);
    }
    return switch (request.method.toUpperCase()) {
      'POST' => _handlePost(request),
      'GET' => _handleGet(request),
      'DELETE' => _handleDelete(request),
      _ => _empty(405,
          headers: const <String, String>{'allow': 'POST, GET, DELETE'}),
    };
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final session in _sessions.values.toList(growable: false)) {
      await session.close();
    }
    _sessions.clear();
  }

  Future<McpHttpEndpointResponse> _handlePost(
    McpHttpEndpointRequest request,
  ) async {
    if (!_accepts(request, 'application/json') ||
        !_accepts(request, 'text/event-stream')) {
      return _empty(406);
    }
    if (_contentType(request) != 'application/json') {
      return _empty(415);
    }
    late final List<int> body;
    try {
      body = await _readBody(request.body);
    } on ProtocolException {
      return _empty(413);
    }
    late final JsonRpcMessage message;
    try {
      message = _codec.decode(utf8.decode(body, allowMalformed: false));
    } on Object {
      return _empty(400);
    }

    final isInitialize =
        message is JsonRpcRequest && message.method == 'initialize';
    late final McpHttpServerSession session;
    if (isInitialize) {
      if (request.header(mcpHttpSessionHeader) != null) {
        return _empty(400);
      }
      if (_sessions.length >= maxSessions) {
        return _empty(503);
      }
      final id = createSessionId();
      if (!_validSessionId(id) || _sessions.containsKey(id)) {
        return _empty(500);
      }
      session = McpHttpServerSession(
        id: id,
        serverFactory: serverFactory,
        maxStreams: maxStreamsPerSession,
        maxEvents: maxEventsPerSession,
      );
      _sessions[id] = session;
    } else {
      final resolved = _resolveSession(request);
      if (resolved == null) {
        return _empty(
          request.header(mcpHttpSessionHeader) == null ? 400 : 404,
        );
      }
      if (!_validProtocolVersion(request)) {
        return _empty(400);
      }
      session = resolved;
    }

    if (message is! JsonRpcRequest) {
      session.accept(message);
      return _empty(202);
    }
    late final McpHttpServerStream stream;
    try {
      stream = session.beginRequest(message);
      final first = await stream.firstEvent;
      if (_isResponseFor(first.message, message.id)) {
        session.discardJsonStream(stream);
        final encoded = utf8.encode(_codec.encode(first.message));
        final initializeFailed =
            isInitialize && first.message is JsonRpcErrorResponse;
        if (initializeFailed) {
          _sessions.remove(session.id);
          await session.close();
        }
        return McpHttpEndpointResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'application/json',
            if (isInitialize && !initializeFailed)
              mcpHttpSessionHeader: session.id,
          },
          body: Stream<List<int>>.value(encoded),
        );
      }
      return McpHttpEndpointResponse(
        statusCode: 200,
        headers: <String, String>{
          'content-type': 'text/event-stream',
          'cache-control': 'no-cache',
          if (isInitialize) mcpHttpSessionHeader: session.id,
        },
        body: _sseBody(stream),
      );
    } on Object {
      if (isInitialize) {
        _sessions.remove(session.id);
        await session.close();
      }
      return _empty(500);
    }
  }

  Future<McpHttpEndpointResponse> _handleGet(
    McpHttpEndpointRequest request,
  ) async {
    if (!_accepts(request, 'text/event-stream')) {
      return _empty(406);
    }
    final session = _resolveSession(request);
    if (session == null) {
      return _empty(request.header(mcpHttpSessionHeader) == null ? 400 : 404);
    }
    if (!_validProtocolVersion(request)) {
      return _empty(400);
    }
    final lastEventId = request.header('last-event-id');
    late final McpHttpServerStream stream;
    var afterSequence = 0;
    if (lastEventId == null) {
      stream = session.openSideChannel();
    } else {
      final event = session.eventForId(lastEventId);
      final resumed = session.streamForEvent(lastEventId);
      if (event == null || resumed == null) {
        return _empty(400);
      }
      stream = resumed;
      afterSequence = event.sequence;
    }
    return McpHttpEndpointResponse(
      statusCode: 200,
      headers: const <String, String>{
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
      },
      body: _sseBody(stream, afterSequence: afterSequence),
    );
  }

  Future<McpHttpEndpointResponse> _handleDelete(
    McpHttpEndpointRequest request,
  ) async {
    final session = _resolveSession(request);
    if (session == null) {
      return _empty(request.header(mcpHttpSessionHeader) == null ? 400 : 404);
    }
    if (!_validProtocolVersion(request)) {
      return _empty(400);
    }
    _sessions.remove(session.id);
    await session.close();
    return _empty(204);
  }

  Stream<List<int>> _sseBody(
    McpHttpServerStream stream, {
    int afterSequence = 0,
  }) async* {
    var count = 0;
    final maxEvents =
        stream.isSideChannel && maxSseEventsPerSideChannelResponse > 0
            ? maxSseEventsPerSideChannelResponse
            : maxSseEventsPerResponse;
    await for (final event in stream.events(afterSequence: afterSequence)) {
      yield utf8.encode(
        'event: message\n'
        'id: ${event.id}\n'
        'data: ${_codec.encode(event.message)}\n'
        '\n',
      );
      count++;
      if (maxEvents > 0 && count >= maxEvents && !stream.isTerminal) {
        yield utf8.encode('retry: ${pollRetry.inMilliseconds}\n\n');
        return;
      }
    }
  }

  McpHttpServerSession? _resolveSession(McpHttpEndpointRequest request) {
    final id = request.header(mcpHttpSessionHeader);
    return id == null ? null : _sessions[id];
  }

  bool _validProtocolVersion(McpHttpEndpointRequest request) =>
      acceptedProtocolVersions.contains(
        request.header(mcpHttpProtocolVersionHeader),
      );

  bool _authorizedHost(String? host) =>
      host != null && allowedHosts.contains(host.toLowerCase());

  bool _authorizedOrigin(String? origin) =>
      origin == null || allowedOrigins.contains(origin);

  bool _accepts(McpHttpEndpointRequest request, String value) =>
      request
          .header('accept')
          ?.split(',')
          .map((item) => item.split(';').first.trim().toLowerCase())
          .contains(value) ??
      false;

  String _contentType(McpHttpEndpointRequest request) =>
      request.header('content-type')?.split(';').first.trim().toLowerCase() ??
      '';

  Future<List<int>> _readBody(Stream<List<int>> stream) async {
    final body = <int>[];
    await for (final chunk in stream) {
      if (body.length + chunk.length > limits.maxMessageBytes) {
        throw const ProtocolTransportException(
          'mcp_http_request_body_too_large',
          'MCP HTTP request body exceeds the configured limit.',
        );
      }
      body.addAll(chunk);
    }
    if (body.isEmpty) {
      throw const ProtocolTransportException(
        'mcp_http_empty_request_body',
        'MCP HTTP POST body is empty.',
      );
    }
    return body;
  }
}

McpHttpEndpointResponse _empty(
  int statusCode, {
  Map<String, String> headers = const <String, String>{},
}) =>
    McpHttpEndpointResponse(statusCode: statusCode, headers: headers);

bool _validSessionId(String value) =>
    value.isNotEmpty &&
    value.codeUnits.every((unit) => unit >= 0x21 && unit <= 0x7e);

bool _isResponseFor(JsonRpcMessage message, JsonRpcId expectedId) =>
    switch (message) {
      JsonRpcSuccessResponse(id: final responseId) ||
      JsonRpcErrorResponse(id: final responseId) =>
        responseId == expectedId,
      _ => false,
    };
