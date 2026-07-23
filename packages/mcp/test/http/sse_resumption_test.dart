import 'dart:async';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('POST SSE resumes via GET with Last-Event-ID and retry', () async {
    final clock = RecordingClock();
    final resumed = Completer<void>();
    final http = ScriptedHttpClient(<McpHttpResponder>[
      (request) {
        expect(request.method, 'POST');
        return sseResponse(
          'id: post-stream:1\n'
          'retry: 25\n'
          'data:\n'
          '\n',
        );
      },
      (request) {
        expect(request.method, 'GET');
        expect(request.headers['last-event-id'], 'post-stream:1');
        resumed.complete();
        return sseResponse(
          'id: post-stream:2\n'
          'data: {"jsonrpc":"2.0","id":9,"result":{"tools":[]}}\n'
          '\n',
        );
      },
    ]);
    final store = McpMemoryHttpEventStore(maxStreams: 4);
    final transport = McpHttpClientTransport(
      httpClient: http,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
      eventStore: store,
      clock: clock,
    );
    final response = transport.incomingMessages.first;

    await transport.sendMessage(
      JsonRpcRequest(
        id: JsonRpcIntegerId(9),
        method: 'tools/list',
        params: const <String, Object?>{},
      ),
    );
    await resumed.future;
    final message = await response;
    expect(message, isA<JsonRpcSuccessResponse>());
    await _waitFor(() => store.length == 0);
    expect(clock.delays, <Duration>[const Duration(milliseconds: 25)]);
    expect(http.requests, hasLength(2));
    await transport.close();
  });

  test('GET polling preserves event ID and stops on 204', () async {
    final clock = RecordingClock();
    final notification = Completer<JsonRpcMessage>();
    final http = ScriptedHttpClient(<McpHttpResponder>[
      (_) => sseResponse(
            'id: get-stream:1\n'
            'retry: 10\n'
            'data:\n'
            '\n',
          ),
      (request) {
        expect(request.headers['last-event-id'], 'get-stream:1');
        return sseResponse(
          'id: get-stream:2\n'
          'data: {"jsonrpc":"2.0","method":"notifications/message",'
          '"params":{"level":"info","data":"ready"}}\n'
          '\n',
        );
      },
      (request) {
        expect(request.headers['last-event-id'], 'get-stream:2');
        return byteResponse(204);
      },
    ]);
    final transport = McpHttpClientTransport(
      httpClient: http,
      endpoint: Uri.parse('https://mcp.example.test/rpc'),
      clock: clock,
    );
    transport.incomingMessages.listen((message) {
      if (!notification.isCompleted) {
        notification.complete(message);
      }
    });

    expect(await transport.openServerStream(), isTrue);
    expect(await notification.future, isA<JsonRpcNotification>());
    await _waitFor(() => http.requests.length == 3);
    expect(
      clock.delays,
      <Duration>[
        const Duration(milliseconds: 10),
        const Duration(milliseconds: 10),
      ],
    );
    await transport.close();
  });

  test('event store is bounded by stream count', () {
    final store = McpMemoryHttpEventStore(maxStreams: 2)
      ..write(
        const McpHttpEventCursor(
          streamKey: 'one',
          lastEventId: '1',
          retry: null,
        ),
      )
      ..write(
        const McpHttpEventCursor(
          streamKey: 'two',
          lastEventId: '2',
          retry: null,
        ),
      )
      ..write(
        const McpHttpEventCursor(
          streamKey: 'three',
          lastEventId: '3',
          retry: null,
        ),
      );

    expect(store.length, 2);
    expect(store.read('one'), isNull);
    expect(store.read('three')?.lastEventId, '3');
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition was not reached.');
}
