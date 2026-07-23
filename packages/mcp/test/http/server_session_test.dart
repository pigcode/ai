import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'endpoint_support.dart';

void main() {
  test('POST SSE carries reverse request and original response', () async {
    late McpServer server;
    final endpoint = McpHttpEndpoint(
      path: '/mcp',
      allowedHosts: const <String>['mcp.test'],
      createSessionId: () => 'reverse-session',
      serverFactory: (transport) {
        server = McpServer(
          transport: transport,
          capabilities: McpServerCapabilities(tools: true),
          handlers: McpHandlerSet(
            requests: <String, McpRequestHandler>{
              'tools/list': (_) =>
                  const <String, Object?>{'tools': <Object?>[]},
              'tools/call': (_) async {
                final roots = await server.listRoots();
                return <String, Object?>{
                  'content': <Object?>[
                    <String, Object?>{
                      'type': 'text',
                      'text': roots.toJson().toString(),
                    },
                  ],
                };
              },
            },
          ),
          serverInfo: const <String, Object?>{
            'name': 'reverse-server',
            'version': '1.0.0',
          },
        );
        return server;
      },
    );
    final sessionId = await _initialize(
      endpoint,
      clientCapabilities: const <String, Object?>{
        'roots': <String, Object?>{},
      },
    );

    final response = await endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: initializedHeaders(sessionId),
        json: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': <String, Object?>{'name': 'inspect'},
        },
      ),
    );
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], 'text/event-stream');
    final iterator = StreamIterator<List<int>>(response.body);
    expect(await iterator.moveNext(), isTrue);
    final reverse = _decodeSseMessage(iterator.current);
    expect(reverse, isA<JsonRpcRequest>());
    expect((reverse as JsonRpcRequest).method, 'roots/list');

    final accepted = await endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: initializedHeaders(sessionId),
        json: <String, Object?>{
          'jsonrpc': '2.0',
          'id': reverse.id.toJson(),
          'result': <String, Object?>{
            'roots': <Object?>[
              <String, Object?>{'uri': 'file:///workspace'},
            ],
          },
        },
      ),
    );
    expect(accepted.statusCode, 202);
    expect(await iterator.moveNext(), isTrue);
    final original = _decodeSseMessage(iterator.current);
    expect(original, isA<JsonRpcSuccessResponse>());
    expect((original as JsonRpcSuccessResponse).id.toJson(), 2);
    expect(await iterator.moveNext(), isFalse);
    await endpoint.close();
  });

  test('reverse request prefers an open GET side channel', () async {
    late McpServer server;
    final endpoint = McpHttpEndpoint(
      path: '/mcp',
      allowedHosts: const <String>['mcp.test'],
      createSessionId: () => 'side-channel-session',
      serverFactory: (transport) {
        server = McpServer(
          transport: transport,
          capabilities: McpServerCapabilities(tools: true),
          handlers: McpHandlerSet(
            requests: <String, McpRequestHandler>{
              'tools/list': (_) =>
                  const <String, Object?>{'tools': <Object?>[]},
              'tools/call': (_) async {
                await server.listRoots();
                return const <String, Object?>{
                  'content': <Object?>[
                    <String, Object?>{'type': 'text', 'text': 'done'},
                  ],
                };
              },
            },
          ),
          serverInfo: const <String, Object?>{
            'name': 'side-channel-server',
            'version': '1.0.0',
          },
        );
        return server;
      },
    );
    final sessionId = await _initialize(
      endpoint,
      clientCapabilities: const <String, Object?>{
        'roots': <String, Object?>{},
      },
    );
    final side = await _openGet(endpoint, sessionId);
    final sideIterator = StreamIterator<List<int>>(side.body);
    final reverseReady = sideIterator.moveNext();
    final originalFuture = endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: initializedHeaders(sessionId),
        json: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': <String, Object?>{'name': 'inspect'},
        },
      ),
    );

    expect(await reverseReady, isTrue);
    final reverse = _decodeSseMessage(sideIterator.current) as JsonRpcRequest;
    expect(reverse.method, 'roots/list');
    final accepted = await endpoint.handle(
      endpointRequest(
        method: 'POST',
        headers: initializedHeaders(sessionId),
        json: <String, Object?>{
          'jsonrpc': '2.0',
          'id': reverse.id.toJson(),
          'result': <String, Object?>{'roots': <Object?>[]},
        },
      ),
    );
    expect(accepted.statusCode, 202);
    final original = await originalFuture;
    expect(original.headers['content-type'], 'application/json');
    expect(
      jsonDecode(await responseText(original)),
      containsPair('id', 2),
    );
    await sideIterator.cancel();
    await endpoint.close();
  });

  test('multiple GET streams receive each message once', () async {
    late McpServer server;
    final endpoint = _endpoint(
      createSessionId: () => 'multi-session',
      onServer: (value) => server = value,
    );
    final sessionId = await _initialize(endpoint);
    final first = await _openGet(endpoint, sessionId);
    final second = await _openGet(endpoint, sessionId);
    final firstIterator = StreamIterator<List<int>>(first.body);
    final secondIterator = StreamIterator<List<int>>(second.body);
    final firstReady = firstIterator.moveNext();
    final secondReady = secondIterator.moveNext();

    await server.notifyClient(
      'notifications/progress',
      const <String, Object?>{'progressToken': 'one', 'progress': 1},
    );
    await server.notifyClient(
      'notifications/progress',
      const <String, Object?>{'progressToken': 'two', 'progress': 1},
    );
    expect(await firstReady, isTrue);
    expect(await secondReady, isTrue);
    final tokens = <Object?>{
      _progressToken(firstIterator.current),
      _progressToken(secondIterator.current),
    };
    expect(tokens, <Object?>{'one', 'two'});
    await firstIterator.cancel();
    await secondIterator.cancel();
    await endpoint.close();
  });

  test('polling resumes one stream and bounded retention rejects stale ID',
      () async {
    late McpServer server;
    final endpoint = _endpoint(
      createSessionId: () => 'poll-session',
      onServer: (value) => server = value,
      maxEventsPerSession: 1,
      maxSseEventsPerResponse: 1,
    );
    final sessionId = await _initialize(endpoint);
    final initial = await _openGet(endpoint, sessionId);
    final iterator = StreamIterator<List<int>>(initial.body);
    final ready = iterator.moveNext();
    await server.notifyClient(
      'notifications/progress',
      const <String, Object?>{'progressToken': 'first', 'progress': 1},
    );
    expect(await ready, isTrue);
    final firstChunk = utf8.decode(iterator.current);
    final firstId = _eventId(firstChunk);
    expect(await iterator.moveNext(), isTrue);
    expect(utf8.decode(iterator.current), contains('retry: 100'));
    expect(await iterator.moveNext(), isFalse);

    final resumed = await _openGet(
      endpoint,
      sessionId,
      lastEventId: firstId,
    );
    final resumedIterator = StreamIterator<List<int>>(resumed.body);
    final resumedReady = resumedIterator.moveNext();
    await server.notifyClient(
      'notifications/progress',
      const <String, Object?>{'progressToken': 'second', 'progress': 1},
    );
    expect(await resumedReady, isTrue);
    expect(_progressToken(resumedIterator.current), 'second');
    await resumedIterator.cancel();

    final stale = await _openGet(
      endpoint,
      sessionId,
      lastEventId: firstId,
    );
    expect(stale.statusCode, 400);
    await endpoint.close();
  });

  test('endpoint close gracefully terminates sessions and streams', () async {
    late McpServer server;
    final endpoint = _endpoint(
      createSessionId: () => 'close-session',
      onServer: (value) => server = value,
    );
    final sessionId = await _initialize(endpoint);
    final response = await _openGet(endpoint, sessionId);
    final done = response.body.drain<void>();

    await endpoint.close();
    await done;
    expect(endpoint.sessionCount, 0);
    expect(server.state, McpConnectionState.closed);
    expect(
      (await endpoint.handle(
        endpointRequest(method: 'GET'),
      ))
          .statusCode,
      503,
    );
  });
}

McpHttpEndpoint _endpoint({
  required String Function() createSessionId,
  required void Function(McpServer server) onServer,
  int maxEventsPerSession = 16,
  int maxSseEventsPerResponse = 0,
}) =>
    McpHttpEndpoint(
      path: '/mcp',
      allowedHosts: const <String>['mcp.test'],
      createSessionId: createSessionId,
      maxEventsPerSession: maxEventsPerSession,
      maxSseEventsPerResponse: maxSseEventsPerResponse,
      serverFactory: (transport) {
        final server = McpServer(
          transport: transport,
          capabilities: McpServerCapabilities(),
          handlers: McpHandlerSet(),
          serverInfo: const <String, Object?>{
            'name': 'stream-server',
            'version': '1.0.0',
          },
        );
        onServer(server);
        return server;
      },
    );

Future<String> _initialize(
  McpHttpEndpoint endpoint, {
  Map<String, Object?> clientCapabilities = const <String, Object?>{},
}) async {
  final response = await endpoint.handle(
    endpointRequest(
      method: 'POST',
      headers: const <String, String>{
        'accept': 'application/json, text/event-stream',
        'content-type': 'application/json',
      },
      json: <String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': '2025-11-25',
          'capabilities': clientCapabilities,
          'clientInfo': <String, Object?>{
            'name': 'session-test',
            'version': '1.0.0',
          },
        },
      },
    ),
  );
  expect(response.statusCode, 200);
  await response.body.drain<void>();
  final sessionId = response.headers['mcp-session-id']!;
  final initialized = await endpoint.handle(
    endpointRequest(
      method: 'POST',
      headers: initializedHeaders(sessionId),
      json: const <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      },
    ),
  );
  expect(initialized.statusCode, 202);
  return sessionId;
}

Future<McpHttpEndpointResponse> _openGet(
  McpHttpEndpoint endpoint,
  String sessionId, {
  String? lastEventId,
}) =>
    endpoint.handle(
      endpointRequest(
        method: 'GET',
        headers: <String, String>{
          ...initializedHeaders(sessionId),
          'accept': 'text/event-stream',
          if (lastEventId != null) 'last-event-id': lastEventId,
        },
      ),
    );

JsonRpcMessage _decodeSseMessage(List<int> bytes) {
  final events = SseDecoder().add(bytes);
  expect(events, hasLength(1));
  return const JsonRpcCodec().decode(events.single.data);
}

Object? _progressToken(List<int> bytes) {
  final message = _decodeSseMessage(bytes) as JsonRpcNotification;
  return (message.params! as Map<String, Object?>)['progressToken'];
}

String _eventId(String chunk) {
  final idLine = chunk.split('\n').firstWhere(
        (line) => line.startsWith('id: '),
      );
  return idLine.substring(4);
}
