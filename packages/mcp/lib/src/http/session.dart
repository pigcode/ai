import '../version.dart';

const mcpHttpSessionHeader = 'mcp-session-id';
const mcpHttpProtocolVersionHeader = 'mcp-protocol-version';

/// Client-side Streamable HTTP session metadata.
final class McpHttpSession {
  McpHttpSession({
    required this.endpoint,
    this.protocolVersion = mcpProtocolVersion,
  }) {
    if (endpoint.scheme != 'http' && endpoint.scheme != 'https') {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'MCP HTTP endpoint must use http or https.',
      );
    }
    if (endpoint.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'MCP HTTP endpoint must not contain embedded credentials.',
      );
    }
  }

  final Uri endpoint;
  final String protocolVersion;
  String? _sessionId;
  var _initialized = false;
  var _expired = false;

  String? get sessionId => _sessionId;
  bool get isInitialized => _initialized;
  bool get isExpired => _expired;

  Map<String, String> protocolHeaders({
    String? lastEventId,
  }) =>
      <String, String>{
        if (_initialized) mcpHttpProtocolVersionHeader: protocolVersion,
        if (_sessionId != null) mcpHttpSessionHeader: _sessionId!,
        if (lastEventId != null) 'last-event-id': lastEventId,
      };

  void acceptInitializeResponse(Map<String, String> headers) {
    if (_initialized) {
      throw StateError('MCP HTTP session was already initialized.');
    }
    final sessionId = headers[mcpHttpSessionHeader];
    if (sessionId != null) {
      _validateSessionId(sessionId);
      _sessionId = sessionId;
    }
    _initialized = true;
    _expired = false;
  }

  void markExpired() {
    _expired = true;
  }

  void clear() {
    _sessionId = null;
    _initialized = false;
    _expired = false;
  }
}

void _validateSessionId(String value) {
  if (value.isEmpty ||
      value.codeUnits.any((unit) => unit < 0x21 || unit > 0x7e)) {
    throw const FormatException(
      'MCP HTTP session ID must contain visible ASCII only.',
    );
  }
}
