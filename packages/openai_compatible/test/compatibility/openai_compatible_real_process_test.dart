import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

const _peerVersion = 'phase1-openai-compatible-peer-v1';
const _deadline = Duration(seconds: 5);

void main() {
  // Compatibility fixture (real-process): P1-COMPAT-01
  // Compatibility fixture (real-process): P1-COMPAT-02
  // Compatibility fixture (real-process): P1-COMPAT-03
  // Compatibility fixture (real-process): P1-COMPAT-04
  test(
    'fixed child peer covers configurable HTTP, SSE and embedding boundaries',
    () async {
      final peer = await _PeerProcess.start();
      final client = http.Client();
      final inspectionClient = HttpClient();
      try {
        final provider = createOpenAiCompatible(
          name: 'acme-real',
          baseUrl: 'http://${peer.host}:${peer.port}/v1/',
          apiKey: 'real-key',
          headers: const <String, String>{'x-provider-header': 'real'},
          queryParams: const <String, String>{'tenant': 'real'},
          client: client,
          includeUsage: true,
          embeddingMaxEmbeddingsPerCall: 2,
          metadataExtractor: _metadataExtractor(),
        );

        expect(provider.languageModel('chat-model').provider, 'acme-real.chat');
        expect(
          provider.embeddingModel('embed-model').provider,
          'acme-real.embedding',
        );
        expect(
          () => createOpenAiCompatible(name: 'acme-real', baseUrl: ''),
          throwsA(isA<InvalidArgumentError>()),
        );

        final chat = await provider.chatModel('chat-model').doGenerate(
              const LanguageModelCallOptions(
                prompt: <LanguageModelMessage>[
                  UserMessage(<UserContentPart>[TextPart('chat')]),
                ],
                providerOptions: <String, JsonObject>{
                  'acme-real': <String, Object?>{
                    'user': 'real-user',
                    'reasoningEffort': 'vendor-real',
                    'future_option': 'real-passthrough',
                  },
                },
              ),
            );
        expect(chat.content, const <LanguageModelContent>[
          TextContent('real-chat-ok'),
        ]);
        expect(chat.providerMetadata?['acme-real'], const <String, Object?>{});
        expect(
          chat.providerMetadata?['vendor-extension'],
          <String, Object?>{'traceId': 'trace-real'},
        );

        final stream = await provider.chatModel('chat-model').doStream(
              const LanguageModelCallOptions(
                prompt: <LanguageModelMessage>[
                  UserMessage(<UserContentPart>[TextPart('stream')]),
                ],
              ),
            );
        final streamParts = await stream.stream.toList().timeout(_deadline);
        expect(
          streamParts.whereType<TextDelta>().map((part) => part.delta).join(),
          'real-stream-ok',
        );
        final finish = streamParts.whereType<FinishPart>().single;
        expect(finish.usage.inputTokens.total, 6);
        expect(finish.usage.outputTokens.total, 2);
        expect(
          finish.providerMetadata?['vendor-extension'],
          <String, Object?>{'chunkCount': 3},
        );

        final failedStream = await provider.chatModel('chat-model').doStream(
              const LanguageModelCallOptions(
                prompt: <LanguageModelMessage>[
                  UserMessage(<UserContentPart>[TextPart('stream error')]),
                ],
                headers: <String, String>{'x-fixture': 'stream-error'},
              ),
            );
        final failedParts =
            await failedStream.stream.toList().timeout(_deadline);
        expect(
          failedParts.whereType<ErrorPart>().single.error,
          <String, Object?>{
            'message': 'real stream failure',
            'code': 'REAL_STREAM_FAILURE',
            'detail': <String, Object?>{'retry': false},
          },
        );
        expect(failedParts.whereType<FinishPart>(), isEmpty);

        final embedding = await provider.embeddingModel('embed-model').doEmbed(
              const EmbeddingModelCallOptions(
                values: <String>['one', 'two'],
                providerOptions: <String, JsonObject>{
                  'acme-real': <String, Object?>{
                    'dimensions': 2,
                    'user': 'embedding-user',
                  },
                },
              ),
            );
        expect(embedding.embeddings, <List<double>>[
          <double>[0.5, 0.6],
          <double>[0.7, 0.8],
        ]);
        expect(embedding.usage.tokens, 9);
        expect(
          embedding.providerMetadata?['vendor-extension'],
          <String, Object?>{'region': 'real'},
        );

        await expectLater(
          provider.embeddingModel('embed-model').doEmbed(
                const EmbeddingModelCallOptions(
                  values: <String>['one', 'two', 'three'],
                ),
              ),
          throwsA(isA<TooManyEmbeddingValuesForCallError>()),
        );
        await expectLater(
          provider.embeddingModel('embed-model').doEmbed(
                const EmbeddingModelCallOptions(
                  values: <String>['one', 'two', 'three'],
                  providerOptions: <String, JsonObject>{
                    'acme-real': <String, Object?>{'dimensions': true},
                  },
                ),
              ),
          throwsA(isA<TypeValidationError>()),
        );
        await expectLater(
          provider.embeddingModel('embed-model').doEmbed(
                const EmbeddingModelCallOptions(
                  values: <String>['one'],
                  headers: <String, String>{'x-fixture': 'embedding-error'},
                ),
              ),
          throwsA(
            isA<ApiCallError>()
                .having(
                  (error) => error.message,
                  'message',
                  'real embedding failure',
                )
                .having((error) => error.statusCode, 'statusCode', 429)
                .having((error) => error.isRetryable, 'isRetryable', isTrue),
          ),
        );

        final observations = await _readJson(
          inspectionClient,
          Uri.parse('http://${peer.host}:${peer.port}/observations'),
        );
        expect(observations['authorizationHeaderSeen'], isTrue);
        expect(observations['providerHeaderSeen'], isTrue);
        expect(observations['querySeen'], isTrue);
        expect(observations['unknownOptionSeen'], isTrue);
        expect(observations['customOptionsSeen'], isTrue);
        expect(observations['streamRequestCount'], 1);
        expect(observations['paths'], <Object?>[
          '/observations',
          '/v1/chat/completions',
          '/v1/embeddings',
        ]);
      } finally {
        client.close();
        inspectionClient.close(force: true);
        await peer.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

MetadataExtractor _metadataExtractor() {
  return MetadataExtractor(
    extractMetadata: (parsedBody) async {
      final body = parsedBody! as JsonObject;
      return <String, JsonObject>{
        'vendor-extension': <String, Object?>{
          'traceId': body['vendor_trace'],
        },
      };
    },
    createStreamExtractor: () {
      var chunkCount = 0;
      return StreamMetadataExtractor(
        processChunk: (_) => chunkCount += 1,
        buildMetadata: () => <String, JsonObject>{
          'vendor-extension': <String, Object?>{
            'chunkCount': chunkCount,
          },
        },
      );
    },
  );
}

Future<Map<String, Object?>> _readJson(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri).timeout(_deadline);
  final response = await request.close().timeout(_deadline);
  final text = await utf8.decoder.bind(response).join().timeout(_deadline);
  expect(response.statusCode, HttpStatus.ok);
  return jsonDecode(text) as Map<String, Object?>;
}

final class _PeerProcess {
  _PeerProcess._(
    this.process,
    this._lines,
    this.stderrOutput, {
    required this.host,
    required this.port,
  });

  final Process process;
  final StreamIterator<String> _lines;
  final Future<String> stderrOutput;
  final String host;
  final int port;
  var _shutdown = false;

  static Future<_PeerProcess> start() async {
    final repositoryRoot = Directory.current.parent.parent;
    final peerFile = File.fromUri(
      repositoryRoot.uri.resolve(
        'tool/fixtures/openai_compatible_peer.dart',
      ),
    );
    final expectedHashResult = Process.runSync(
      'git',
      <String>['hash-object', '--', peerFile.path],
      workingDirectory: repositoryRoot.path,
    );
    expect(expectedHashResult.exitCode, 0);
    final expectedHash = (expectedHashResult.stdout as String).trim();
    final environment = <String, String>{
      for (final key in const <String>[
        'PATH',
        'SystemRoot',
        'TEMP',
        'TMP',
        'TMPDIR',
      ])
        if (Platform.environment[key] case final String value) key: value,
    };
    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>[peerFile.path],
      workingDirectory: repositoryRoot.path,
      environment: environment,
      includeParentEnvironment: false,
    );
    final lines = StreamIterator<String>(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final stderrOutput = process.stderr.transform(utf8.decoder).join();
    expect(await lines.moveNext().timeout(_deadline), isTrue);
    final ready = jsonDecode(lines.current) as Map<String, Object?>;
    expect(ready['type'], 'ready');
    expect(ready['version'], _peerVersion);
    expect(ready['sourceBlobHash'], expectedHash);
    expect(ready['host'], InternetAddress.loopbackIPv4.address);
    expect(
      ready['transports'],
      <Object?>['loopback-http', 'loopback-sse'],
    );
    return _PeerProcess._(
      process,
      lines,
      stderrOutput,
      host: ready['host']! as String,
      port: ready['port']! as int,
    );
  }

  Future<void> shutdown() async {
    if (_shutdown) {
      return;
    }
    process.stdin.writeln(jsonEncode(<String, Object?>{
      'id': 'shutdown',
      'op': 'shutdown',
    }));
    await process.stdin.flush();
    expect(await _lines.moveNext().timeout(_deadline), isTrue);
    final response = jsonDecode(_lines.current) as Map<String, Object?>;
    expect(response['ok'], isTrue);
    _shutdown = true;
  }

  Future<void> dispose() async {
    if (!_shutdown) {
      try {
        await shutdown();
      } on Object {
        process.kill();
      }
    }
    await _lines.cancel();
    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
    }
    expect(await stderrOutput, isEmpty);
  }
}
