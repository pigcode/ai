import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';

typedef McpHttpResponder = FutureOr<McpHttpResponse> Function(
  McpHttpRequest request,
);

final class ScriptedHttpClient implements McpHttpClient {
  ScriptedHttpClient(Iterable<McpHttpResponder> responders)
      : responders = Queue<McpHttpResponder>.of(responders);

  final Queue<McpHttpResponder> responders;
  final List<McpHttpRequest> requests = <McpHttpRequest>[];

  @override
  Future<McpHttpResponse> send(McpHttpRequest request) async {
    requests.add(request);
    if (responders.isEmpty) {
      throw StateError('No scripted HTTP response remains.');
    }
    return responders.removeFirst()(request);
  }
}

McpHttpResponse byteResponse(
  int statusCode, {
  Map<String, String> headers = const <String, String>{},
  List<int> body = const <int>[],
  Iterable<List<int>>? chunks,
}) =>
    McpHttpResponse(
      statusCode: statusCode,
      headers: headers,
      body: Stream<List<int>>.fromIterable(chunks ?? <List<int>>[body]),
    );

McpHttpResponse jsonResponse(
  Object? value, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{},
}) =>
    byteResponse(
      statusCode,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        ...headers,
      },
      body: utf8.encode(jsonEncode(value)),
    );

McpHttpResponse sseResponse(
  String events, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{},
}) =>
    byteResponse(
      statusCode,
      headers: <String, String>{
        'content-type': 'text/event-stream; charset=utf-8',
        ...headers,
      },
      body: utf8.encode(events),
    );

Map<String, Object?> requestJson(McpHttpRequest request) =>
    jsonDecode(utf8.decode(request.body))! as Map<String, Object?>;

final class RecordingClock implements McpHttpClock {
  final List<Duration> delays = <Duration>[];
  DateTime current = DateTime.utc(2026, 7, 23);

  @override
  Future<void> delay(Duration duration) async {
    delays.add(duration);
    current = current.add(duration);
  }

  @override
  DateTime now() => current;
}

final class FixedAuthorizationProvider implements McpHttpAuthorizationProvider {
  const FixedAuthorizationProvider(this.headers);

  final Map<String, String> headers;

  @override
  Future<Map<String, String>> headersFor(Uri target) async => headers;
}
