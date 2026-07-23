import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// A non-success HTTP response from an MCP endpoint.
///
/// Response headers are retained so OAuth challenge handling can proceed, but
/// the response body is consumed within the configured transport bound and is
/// never included in diagnostics or [toString].
final class McpHttpStatusException extends ProtocolException {
  McpHttpStatusException({
    required this.statusCode,
    required Map<String, String> headers,
  })  : headers = Map<String, String>.unmodifiable(headers),
        super(
          'mcp_http_status_error',
          'MCP HTTP server returned status $statusCode.',
        );

  final int statusCode;
  final Map<String, String> headers;

  String? header(String name) => headers[name.toLowerCase()];

  @override
  String toString() => 'McpHttpStatusException($statusCode)';
}

/// One portable HTTP request. Redirects are deliberately disabled at this
/// boundary so MCP credential policy remains observable and enforceable.
final class McpHttpRequest {
  McpHttpRequest({
    required this.method,
    required this.uri,
    Map<String, String> headers = const <String, String>{},
    List<int> body = const <int>[],
  })  : headers = Map<String, String>.unmodifiable(headers),
        body = List<int>.unmodifiable(body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;
}

/// One streaming portable HTTP response.
final class McpHttpResponse {
  McpHttpResponse({
    required this.statusCode,
    Map<String, String> headers = const <String, String>{},
    required this.body,
  }) : headers = Map<String, String>.unmodifiable(
          headers.map(
            (name, value) => MapEntry(name.toLowerCase(), value),
          ),
        );

  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> body;

  String? header(String name) => headers[name.toLowerCase()];
}

abstract interface class McpHttpClient {
  Future<McpHttpResponse> send(McpHttpRequest request);
}

/// Supplies target-scoped HTTP authorization headers.
abstract interface class McpHttpAuthorizationProvider {
  Future<Map<String, String>> headersFor(Uri target);
}

/// Injectable portable clock used for SSE reconnect delays.
abstract interface class McpHttpClock {
  DateTime now();
  Future<void> delay(Duration duration);
}

final class McpSystemHttpClock implements McpHttpClock {
  const McpSystemHttpClock();

  @override
  DateTime now() => DateTime.now().toUtc();

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}

/// Portable adapter for a caller-owned `package:http` client.
final class McpPackageHttpClient implements McpHttpClient {
  const McpPackageHttpClient(this.client);

  final http.Client client;

  @override
  Future<McpHttpResponse> send(McpHttpRequest request) async {
    final outbound = http.Request(request.method, request.uri)
      ..followRedirects = false
      ..headers.addAll(request.headers)
      ..bodyBytes = request.body;
    final response = await client.send(outbound);
    return McpHttpResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.stream,
    );
  }
}
