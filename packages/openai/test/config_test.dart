import 'dart:async';
import 'dart:io';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_openai/src/internal/web_socket_channel_connector_default.dart'
    as default_web_socket_connector;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('OpenAiConfig', () {
    test('exposes providerName/baseUrl/headers/client as constructed', () {
      final client = http.Client();
      addTearDown(client.close);

      Map<String, String> headers() => <String, String>{
            'Authorization': 'Bearer sk-test',
          };

      final config = OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        headers: headers,
        client: client,
      );

      expect(config.providerName, 'openai');
      expect(config.baseUrl, 'https://api.openai.com/v1');
      expect(config.headers(),
          <String, String>{'Authorization': 'Bearer sk-test'});
      expect(config.client, same(client));
    });

    test('client is optional and defaults to null', () {
      final config = OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        headers: () => const <String, String>{},
      );

      expect(config.client, isNull);
    });

    test('headers is evaluated per call, not cached at construction', () {
      var callCount = 0;
      final config = OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        headers: () {
          callCount += 1;
          return <String, String>{'X-Call-Count': '$callCount'};
        },
      );

      expect(config.headers(), <String, String>{'X-Call-Count': '1'});
      expect(config.headers(), <String, String>{'X-Call-Count': '2'});
      expect(callCount, 2);
    });

    test('default WebSocket connector forwards headers and protocols',
        () async {
      final observedHeaders = Completer<HttpHeaders>();
      final observedProtocols = Completer<List<String>>();
      final observedProtocol = Completer<String?>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      unawaited(() async {
        await for (final request in server) {
          observedHeaders.complete(request.headers);
          final socket = await WebSocketTransformer.upgrade(
            request,
            protocolSelector: (protocols) {
              observedProtocols.complete([...protocols]);
              return protocols.contains('realtime') ? 'realtime' : null;
            },
          );
          observedProtocol.complete(socket.protocol);
          await socket.close();
          break;
        }
      }());

      final connection = connectOpenAiWebSocket(
        Uri.parse('ws://${server.address.host}:${server.port}/realtime'),
        protocols: const [
          'realtime',
          'openai-insecure-api-key.test-key',
          'openai-organization.org-1',
          'openai-project.proj-1',
        ],
        headers: const {
          'Authorization': 'Bearer test-key',
          'OpenAI-Organization': 'org-1',
          'OpenAI-Project': 'proj-1',
          'X-Custom': 'v',
        },
      );

      await connection.ready;

      expect((await observedHeaders.future).value('x-custom'), 'v');
      expect(await observedProtocols.future, ['realtime']);
      expect(await observedProtocol.future, 'realtime');
      await connection.close();
    });

    test('non-IO WebSocket connector rejects unsupported headers', () {
      expect(
        () => default_web_socket_connector.connectWebSocketChannel(
          Uri.parse('ws://localhost/realtime'),
          headers: const {
            'Authorization': 'Bearer test-key',
            'User-Agent': 'pigcode_ai_openai/0.0.1',
            'OpenAI-Project': 'proj-1',
            'X-Custom': 'v',
          },
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('X-Custom'),
          ),
        ),
      );
    });
  });
}
