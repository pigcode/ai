import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'contracts.dart';
import 'event_store.dart';
import 'session.dart';

/// Portable MCP Streamable HTTP client transport.
final class McpHttpClientTransport
    implements ProtocolMessageTransport<JsonRpcMessage> {
  McpHttpClientTransport({
    required this.httpClient,
    required Uri endpoint,
    this.authorizationProvider,
    McpHttpEventStore? eventStore,
    this.clock = const McpSystemHttpClock(),
    ProtocolLimits? limits,
    this.maxRedirects = 3,
    this.maxRetryDelay = const Duration(seconds: 30),
  })  : eventStore = eventStore ?? McpMemoryHttpEventStore(),
        limits = limits ?? ProtocolLimits.defaults,
        session = McpHttpSession(endpoint: endpoint) {
    if (maxRedirects < 0 || maxRedirects > 16) {
      throw ArgumentError.value(
        maxRedirects,
        'maxRedirects',
        'Must be between 0 and 16.',
      );
    }
    if (maxRetryDelay.isNegative) {
      throw ArgumentError.value(
        maxRetryDelay,
        'maxRetryDelay',
        'Must not be negative.',
      );
    }
    _incoming = StreamController<JsonRpcMessage>(
      sync: true,
      onPause: () => _paused = true,
      onResume: _resumeDelivery,
      onCancel: () {
        _paused = false;
        _queuedMessages.clear();
      },
    );
  }

  final McpHttpClient httpClient;
  final McpHttpAuthorizationProvider? authorizationProvider;
  final McpHttpEventStore eventStore;
  final McpHttpClock clock;
  final ProtocolLimits limits;
  final int maxRedirects;
  final Duration maxRetryDelay;
  final McpHttpSession session;
  final JsonRpcCodec _codec = const JsonRpcCodec();
  final Queue<JsonRpcMessage> _queuedMessages = Queue<JsonRpcMessage>();
  late final StreamController<JsonRpcMessage> _incoming;
  var _paused = false;
  var _closed = false;
  var _nextStreamId = 1;
  final Set<Future<void>> _activeStreams = <Future<void>>{};

  @override
  Stream<JsonRpcMessage> get incomingMessages => _incoming.stream;

  @override
  Future<void> sendMessage(JsonRpcMessage message) async {
    _ensureOpen();
    final encoded = utf8.encode(_codec.encode(message));
    if (encoded.length > limits.maxMessageBytes) {
      throw const ProtocolTransportException(
        'mcp_http_outbound_body_too_large',
        'MCP HTTP request body exceeds the configured limit.',
      );
    }
    final isInitialize =
        message is JsonRpcRequest && message.method == 'initialize';
    final response = await _sendHttp(
      method: 'POST',
      headers: <String, String>{
        'accept': 'application/json, text/event-stream',
        'content-type': 'application/json',
        ...session.protocolHeaders(),
      },
      body: encoded,
      sideEffecting: true,
    );
    if (response.statusCode == 404 && session.sessionId != null) {
      session.markExpired();
      await _readBoundedBody(response.body);
      throw const ProtocolTransportException(
        'mcp_http_session_expired',
        'MCP HTTP session is no longer available.',
      );
    }
    if (message is JsonRpcNotification ||
        message is JsonRpcSuccessResponse ||
        message is JsonRpcErrorResponse) {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _throwStatus(response);
      }
      // The MCP transport contract prescribes 202 with no body. Some
      // otherwise interoperable peers return another 2xx and an ignorable
      // JSON acknowledgement. Consume it within the normal response bound so
      // a notification acknowledgement can never enter JSON-RPC correlation.
      await _readBoundedBody(response.body);
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _throwStatus(response);
    }
    if (isInitialize) {
      session.acceptInitializeResponse(response.headers);
    }
    final contentType = _contentType(response);
    if (contentType == 'application/json') {
      final bytes = await _readBoundedBody(response.body);
      if (bytes.isEmpty) {
        throw const ProtocolTransportException(
          'mcp_http_empty_json_response',
          'MCP HTTP JSON response body is empty.',
        );
      }
      _deliver(_codec.decode(utf8.decode(bytes, allowMalformed: false)));
      return;
    }
    if (contentType == 'text/event-stream') {
      final streamKey = 'post-${_nextStreamId++}';
      final requestId = (message as JsonRpcRequest).id;
      _trackStream(
        _consumeSse(
          response.body,
          streamKey: streamKey,
          expectedResponseId: requestId,
        ),
      );
      return;
    }
    await _readBoundedBody(response.body);
    throw const ProtocolTransportException(
      'mcp_http_unsupported_content_type',
      'MCP HTTP response must be JSON or an SSE stream.',
    );
  }

  /// Opens the optional server-to-client SSE stream.
  Future<bool> openServerStream({
    String? resumeStreamKey,
    JsonRpcId? expectedResponseId,
  }) async {
    _ensureOpen();
    final cursor =
        resumeStreamKey == null ? null : eventStore.read(resumeStreamKey);
    final response = await _sendHttp(
      method: 'GET',
      headers: <String, String>{
        'accept': 'text/event-stream',
        ...session.protocolHeaders(lastEventId: cursor?.lastEventId),
      },
      sideEffecting: false,
    );
    if (response.statusCode == 405 || response.statusCode == 204) {
      await _readBoundedBody(response.body);
      return false;
    }
    if (response.statusCode == 404 && session.sessionId != null) {
      session.markExpired();
      await _readBoundedBody(response.body);
      throw const ProtocolTransportException(
        'mcp_http_session_expired',
        'MCP HTTP session is no longer available.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _throwStatus(response);
    }
    if (_contentType(response) != 'text/event-stream') {
      await _readBoundedBody(response.body);
      throw const ProtocolTransportException(
        'mcp_http_invalid_sse_content_type',
        'MCP HTTP GET response must be text/event-stream.',
      );
    }
    final streamKey = resumeStreamKey ?? 'get-${_nextStreamId++}';
    _trackStream(
      _consumeSse(
        response.body,
        streamKey: streamKey,
        expectedResponseId: expectedResponseId,
      ),
    );
    return true;
  }

  /// Explicitly terminates the current HTTP session when one was assigned.
  Future<bool> terminateSession() async {
    if (session.sessionId == null) {
      return false;
    }
    final response = await _sendHttp(
      method: 'DELETE',
      headers: <String, String>{
        'accept': 'application/json',
        ...session.protocolHeaders(),
      },
      sideEffecting: true,
    );
    if (response.statusCode == 405) {
      await _readBoundedBody(response.body);
      return false;
    }
    if (response.statusCode != 200 &&
        response.statusCode != 202 &&
        response.statusCode != 204) {
      await _throwStatus(response);
    }
    await _drainEmptyResponse(response.body);
    session.clear();
    return true;
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    try {
      await terminateSession();
    } on Object {
      // Transport close is best-effort; the caller owns the HTTP client.
    }
    _closed = true;
    if (!_incoming.isClosed) {
      unawaited(_incoming.close());
    }
  }

  Future<McpHttpResponse> _sendHttp({
    required String method,
    required Map<String, String> headers,
    List<int> body = const <int>[],
    required bool sideEffecting,
  }) async {
    var uri = session.endpoint;
    var redirects = 0;
    var requestHeaders = await _requestHeaders(uri, headers);
    while (true) {
      late final McpHttpResponse response;
      try {
        response = await httpClient.send(
          McpHttpRequest(
            method: method,
            uri: uri,
            headers: requestHeaders,
            body: body,
          ),
        );
      } on ProtocolException {
        rethrow;
      } on Object catch (error) {
        throw ProtocolTransportException(
          sideEffecting
              ? 'mcp_http_unknown_outcome'
              : 'mcp_http_request_failed',
          sideEffecting
              ? 'MCP HTTP side-effecting request outcome is unknown; '
                  'it was not replayed.'
              : 'MCP HTTP request failed.',
          cause: error,
        );
      }
      if (!_isRedirect(response.statusCode)) {
        return response;
      }
      final location = response.header('location');
      if (location == null) {
        return response;
      }
      await _readBoundedBody(response.body);
      if (sideEffecting) {
        throw const ProtocolTransportException(
          'mcp_http_redirect_replay_refused',
          'MCP HTTP side-effecting request was not replayed after redirect.',
        );
      }
      if (redirects++ >= maxRedirects) {
        throw const ProtocolTransportException(
          'mcp_http_redirect_limit',
          'MCP HTTP redirect limit exceeded.',
        );
      }
      final redirected = uri.resolve(location);
      if (!_sameOrigin(uri, redirected)) {
        if (_hasCredentials(requestHeaders)) {
          throw const ProtocolTransportException(
            'mcp_http_cross_origin_credentials',
            'Credential-bearing MCP HTTP redirect was rejected.',
          );
        }
        throw const ProtocolTransportException(
          'mcp_http_cross_origin_redirect',
          'Cross-origin MCP HTTP redirect was rejected.',
        );
      }
      uri = redirected;
      requestHeaders = <String, String>{...requestHeaders};
    }
  }

  Future<Map<String, String>> _requestHeaders(
    Uri target,
    Map<String, String> requiredHeaders,
  ) async {
    final normalized = <String, String>{};
    if (authorizationProvider != null) {
      late final Map<String, String> authorizationHeaders;
      try {
        authorizationHeaders = await authorizationProvider!.headersFor(target);
      } on ProtocolException {
        rethrow;
      } on Object catch (error) {
        throw ProtocolTransportException(
          'mcp_http_authorization_failed',
          'MCP HTTP authorization headers could not be obtained.',
          cause: error,
        );
      }
      for (final entry in authorizationHeaders.entries) {
        final name = entry.key.toLowerCase();
        if (!_validHeaderName(name) ||
            entry.value.contains('\r') ||
            entry.value.contains('\n') ||
            _reservedTransportHeaders.contains(name) ||
            normalized.containsKey(name)) {
          throw const ProtocolTransportException(
            'mcp_http_invalid_authorization_headers',
            'MCP HTTP authorization provider returned unsafe headers.',
          );
        }
        normalized[name] = entry.value;
      }
    }
    return <String, String>{
      ...normalized,
      ...requiredHeaders.map(
        (name, value) => MapEntry(name.toLowerCase(), value),
      ),
    };
  }

  Future<void> _consumeSse(
    Stream<List<int>> body, {
    required String streamKey,
    required JsonRpcId? expectedResponseId,
  }) async {
    final decoder = SseDecoder(limits: limits);
    var terminalResponseSeen = false;
    if (eventStore.read(streamKey) == null) {
      eventStore.write(
        McpHttpEventCursor(
          streamKey: streamKey,
          lastEventId: null,
          retry: null,
        ),
      );
    }
    try {
      await for (final bytes in body) {
        for (final event in decoder.add(bytes)) {
          final eventId = event.id;
          if (eventId != null) {
            final previous = eventStore.read(streamKey);
            eventStore.write(
              McpHttpEventCursor(
                streamKey: streamKey,
                lastEventId: eventId,
                retry:
                    event.retry ?? decoder.reconnectionDelay ?? previous?.retry,
              ),
            );
          }
          if (event.data.isEmpty) {
            continue;
          }
          final message = _codec.decode(event.data);
          if (expectedResponseId != null &&
              _isResponseFor(message, expectedResponseId)) {
            terminalResponseSeen = true;
          }
          _deliver(message);
        }
      }
      decoder.close();
    } on Object catch (error, stackTrace) {
      _failIncoming(error, stackTrace);
      return;
    }
    final saved = eventStore.read(streamKey);
    final delay = decoder.reconnectionDelay;
    if (saved != null && delay != null) {
      eventStore.write(
        McpHttpEventCursor(
          streamKey: streamKey,
          lastEventId: saved.lastEventId,
          retry: delay,
        ),
      );
    }
    if (terminalResponseSeen || _closed) {
      eventStore.remove(streamKey);
      return;
    }
    final cursor = eventStore.read(streamKey);
    if (cursor == null) {
      return;
    }
    final retry = cursor.retry ?? Duration.zero;
    await clock.delay(
      retry > maxRetryDelay ? maxRetryDelay : retry,
    );
    if (!_closed) {
      try {
        await openServerStream(
          resumeStreamKey: streamKey,
          expectedResponseId: expectedResponseId,
        );
      } on Object catch (error, stackTrace) {
        _failIncoming(error, stackTrace);
      }
    }
  }

  void _trackStream(Future<void> stream) {
    _activeStreams.add(stream);
    unawaited(
      stream.whenComplete(() {
        _activeStreams.remove(stream);
      }),
    );
  }

  void _deliver(JsonRpcMessage message) {
    if (_closed || _incoming.isClosed) {
      return;
    }
    if (_paused) {
      if (_queuedMessages.length >= limits.maxInboundRequests) {
        _failIncoming(
          const ProtocolTransportException(
            'mcp_http_inbound_queue_limit',
            'MCP HTTP inbound message queue limit reached.',
          ),
          StackTrace.current,
        );
        return;
      }
      _queuedMessages.addLast(message);
      return;
    }
    _incoming.add(message);
  }

  void _resumeDelivery() {
    _paused = false;
    while (!_paused && _queuedMessages.isNotEmpty && !_incoming.isClosed) {
      _incoming.add(_queuedMessages.removeFirst());
    }
  }

  void _failIncoming(Object error, StackTrace stackTrace) {
    if (_closed || _incoming.isClosed) {
      return;
    }
    _incoming.addError(error, stackTrace);
  }

  Future<List<int>> _readBoundedBody(Stream<List<int>> body) async {
    final bytes = <int>[];
    await for (final chunk in body) {
      if (bytes.length + chunk.length > limits.maxMessageBytes) {
        throw const ProtocolTransportException(
          'mcp_http_response_body_too_large',
          'MCP HTTP response body exceeds the configured limit.',
        );
      }
      bytes.addAll(chunk);
    }
    return List<int>.unmodifiable(bytes);
  }

  Future<void> _drainEmptyResponse(Stream<List<int>> body) async {
    var length = 0;
    await for (final chunk in body) {
      length += chunk.length;
      if (length > limits.maxMessageBytes) {
        throw const ProtocolTransportException(
          'mcp_http_response_body_too_large',
          'MCP HTTP response body exceeds the configured limit.',
        );
      }
    }
    if (length != 0) {
      throw const ProtocolTransportException(
        'mcp_http_unexpected_response_body',
        'MCP HTTP accepted response must not contain a body.',
      );
    }
  }

  String _contentType(McpHttpResponse response) {
    final value = response.header('content-type');
    return value?.split(';').first.trim().toLowerCase() ?? '';
  }

  Future<Never> _throwStatus(McpHttpResponse response) async {
    await _readBoundedBody(response.body);
    throw McpHttpStatusException(
      statusCode: response.statusCode,
      headers: response.headers,
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw const ProtocolTransportException(
        'transport_closed',
        'MCP HTTP transport is closed.',
      );
    }
  }
}

bool _isRedirect(int status) =>
    status == 301 ||
    status == 302 ||
    status == 303 ||
    status == 307 ||
    status == 308;

bool _sameOrigin(Uri left, Uri right) =>
    left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
    left.host.toLowerCase() == right.host.toLowerCase() &&
    left.port == right.port;

const _reservedTransportHeaders = <String>{
  'accept',
  'content-type',
  'host',
  'last-event-id',
  'mcp-protocol-version',
  'mcp-session-id',
};

bool _validHeaderName(String value) =>
    value.isNotEmpty && RegExp(r"^[!#$%&'*+\-.^_`|~0-9a-z]+$").hasMatch(value);

bool _hasCredentials(Map<String, String> headers) => headers.keys.any(
      (name) =>
          name.toLowerCase() == 'authorization' ||
          name.toLowerCase() == 'proxy-authorization' ||
          name.toLowerCase() == 'cookie',
    );

bool _isResponseFor(JsonRpcMessage message, JsonRpcId expectedId) =>
    switch (message) {
      JsonRpcSuccessResponse(id: final responseId) ||
      JsonRpcErrorResponse(id: final responseId) =>
        responseId == expectedId,
      _ => false,
    };
