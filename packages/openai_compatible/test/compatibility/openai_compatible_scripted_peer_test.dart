import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  // Compatibility fixture (scripted-peer): P1-COMPAT-01
  // Compatibility fixture (scripted-peer): P1-COMPAT-02
  // Compatibility fixture (scripted-peer): P1-COMPAT-03
  // Compatibility fixture (scripted-peer): P1-COMPAT-04
  test('public adapter preserves configurable HTTP, SSE and embedding behavior',
      () async {
    final peer = _ScriptedCompatiblePeer();
    final provider = createOpenAiCompatible(
      name: 'acme',
      baseUrl: 'https://peer.invalid/v1/',
      apiKey: 'fixture-key',
      headers: const <String, String>{'x-provider-header': 'provider'},
      queryParams: const <String, String>{'tenant': 'fixture'},
      client: peer,
      includeUsage: true,
      embeddingMaxEmbeddingsPerCall: 2,
      metadataExtractor: MetadataExtractor(
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
      ),
    );

    expect(provider.languageModel('chat-model').provider, 'acme.chat');
    expect(provider.chatModel('chat-model').provider, 'acme.chat');
    expect(provider.embeddingModel('embed-model').provider, 'acme.embedding');
    expect(
      () => createOpenAiCompatible(name: 'acme', baseUrl: ''),
      throwsA(
        isA<InvalidArgumentError>().having(
          (error) => error.argument,
          'argument',
          'baseUrl',
        ),
      ),
    );

    final generated = await provider.chatModel('chat-model').doGenerate(
          const LanguageModelCallOptions(
            prompt: <LanguageModelMessage>[
              UserMessage(<UserContentPart>[TextPart('hello')]),
            ],
            headers: <String, String>{'x-call-header': 'generate'},
            providerOptions: <String, JsonObject>{
              'acme': <String, Object?>{
                'user': 'fixture-user',
                'reasoningEffort': 'vendor-deep',
                'future_option': <String, Object?>{'mode': 'enabled'},
              },
              'other-provider': <String, Object?>{'user': 'ignored'},
            },
          ),
        );

    expect(generated.content, const <LanguageModelContent>[
      TextContent('scripted-chat-ok'),
    ]);
    expect(generated.providerMetadata, <String, JsonObject>{
      'acme': const <String, Object?>{},
      'vendor-extension': <String, Object?>{'traceId': 'trace-scripted'},
    });
    final generateRequest = peer.requests.first;
    expect(
      generateRequest.url.toString(),
      'https://peer.invalid/v1/chat/completions?tenant=fixture',
    );
    expect(generateRequest.headers['Authorization'], 'Bearer fixture-key');
    expect(generateRequest.headers['x-provider-header'], 'provider');
    expect(generateRequest.headers['x-call-header'], 'generate');
    expect(peer.bodies.first['user'], 'fixture-user');
    expect(peer.bodies.first['reasoning_effort'], 'vendor-deep');
    expect(peer.bodies.first['future_option'], <String, Object?>{
      'mode': 'enabled',
    });

    final streamed = await provider.chatModel('chat-model').doStream(
          const LanguageModelCallOptions(
            prompt: <LanguageModelMessage>[
              UserMessage(<UserContentPart>[TextPart('stream')]),
            ],
          ),
        );
    final streamParts = await streamed.stream.toList();
    expect(
      streamParts.whereType<TextDelta>().map((part) => part.delta).join(),
      'scripted-stream-ok',
    );
    final finish = streamParts.whereType<FinishPart>().single;
    expect(finish.usage.inputTokens.total, 5);
    expect(finish.usage.outputTokens.total, 2);
    expect(
      finish.providerMetadata?['vendor-extension'],
      <String, Object?>{'chunkCount': 3},
    );
    expect(peer.bodies[1]['stream_options'], <String, Object?>{
      'include_usage': true,
    });

    final failedStream = await provider.chatModel('chat-model').doStream(
          const LanguageModelCallOptions(
            prompt: <LanguageModelMessage>[
              UserMessage(<UserContentPart>[TextPart('stream error')]),
            ],
            headers: <String, String>{'x-fixture': 'stream-error'},
          ),
        );
    final failedParts = await failedStream.stream.toList();
    expect(failedParts.whereType<ErrorPart>().single.error, <String, Object?>{
      'message': 'scripted stream failure',
      'code': 'SCRIPTED_FAILURE',
    });
    expect(failedParts.whereType<FinishPart>(), isEmpty);

    final embedding = await provider.embeddingModel('embed-model').doEmbed(
          const EmbeddingModelCallOptions(
            values: <String>['one', 'two'],
            providerOptions: <String, JsonObject>{
              'acme': <String, Object?>{
                'dimensions': 2,
                'user': 'embedding-user',
              },
            },
          ),
        );
    expect(embedding.embeddings, <List<double>>[
      <double>[0.1, 0.2],
      <double>[0.3, 0.4],
    ]);
    expect(embedding.usage.tokens, 7);
    expect(embedding.providerMetadata, <String, JsonObject>{
      'vendor-extension': <String, Object?>{'region': 'fixture'},
    });
    expect(peer.bodies[3]['dimensions'], 2);
    expect(peer.bodies[3]['user'], 'embedding-user');

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
                'acme': <String, Object?>{'dimensions': true},
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
              'scripted embedding failure',
            )
            .having((error) => error.statusCode, 'statusCode', 429)
            .having((error) => error.isRetryable, 'isRetryable', isTrue),
      ),
    );
  });
}

final class _ScriptedCompatiblePeer extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final bodies = <JsonObject>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = request is http.Request
        ? jsonDecode(request.body) as JsonObject
        : <String, Object?>{};
    bodies.add(body);

    if (request.url.path == '/v1/chat/completions') {
      if (request.headers['x-fixture'] == 'stream-error') {
        return _sseResponse(
          'data: {"error":{"message":"scripted stream failure",'
          '"code":"SCRIPTED_FAILURE"}}\n\n',
        );
      }
      if (body['stream'] == true) {
        return _sseResponse(
          'data: {"id":"chatcmpl-stream","created":1700000000,'
          '"model":"chat-model","choices":[{"index":0,"delta":'
          '{"role":"assistant","content":"scripted-stream-ok"}}]}\n\n'
          'data: {"id":"chatcmpl-stream","created":1700000000,'
          '"model":"chat-model","choices":[{"index":0,"delta":{},'
          '"finish_reason":"stop"}]}\n\n'
          'data: {"id":"chatcmpl-stream","created":1700000000,'
          '"model":"chat-model","choices":[],"usage":{"prompt_tokens":5,'
          '"completion_tokens":2,"total_tokens":7}}\n\n'
          'data: [DONE]\n\n',
        );
      }
      return _jsonResponse(<String, Object?>{
        'id': 'chatcmpl-scripted',
        'created': 1700000000,
        'model': 'chat-model',
        'vendor_trace': 'trace-scripted',
        'choices': <Object?>[
          <String, Object?>{
            'index': 0,
            'message': <String, Object?>{
              'role': 'assistant',
              'content': 'scripted-chat-ok',
            },
            'finish_reason': 'stop',
          },
        ],
        'usage': <String, Object?>{
          'prompt_tokens': 3,
          'completion_tokens': 1,
          'total_tokens': 4,
        },
      });
    }

    if (request.url.path == '/v1/embeddings') {
      if (request.headers['x-fixture'] == 'embedding-error') {
        return _jsonResponse(
          <String, Object?>{
            'error': <String, Object?>{
              'message': 'scripted embedding failure',
              'code': 'RATE_LIMITED',
            },
          },
          statusCode: 429,
        );
      }
      return _jsonResponse(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'index': 0,
            'embedding': <Object?>[0.1, 0.2],
          },
          <String, Object?>{
            'index': 1,
            'embedding': <Object?>[0.3, 0.4],
          },
        ],
        'usage': <String, Object?>{
          'prompt_tokens': 7,
          'total_tokens': 7,
        },
        'providerMetadata': <String, Object?>{
          'vendor-extension': <String, Object?>{'region': 'fixture'},
        },
      });
    }

    return _jsonResponse(
      <String, Object?>{'error': 'unknown path'},
      statusCode: 404,
    );
  }
}

http.StreamedResponse _jsonResponse(
  JsonObject body, {
  int statusCode = 200,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

http.StreamedResponse _sseResponse(String body) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(body)),
    200,
    headers: const <String, String>{'content-type': 'text/event-stream'},
  );
}
