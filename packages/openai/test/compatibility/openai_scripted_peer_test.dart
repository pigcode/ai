import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  // Compatibility fixture (scripted-peer): P1-OPENAI-01
  // Compatibility fixture (scripted-peer): P1-OPENAI-02
  // Compatibility fixture (scripted-peer): P1-OPENAI-03
  // Compatibility fixture (scripted-peer): P1-OPENAI-04
  // Compatibility fixture (scripted-peer): P1-OPENAI-05
  // Compatibility fixture (scripted-peer): P1-OPENAI-06
  // Compatibility fixture (scripted-peer): P1-OPENAI-07
  // Compatibility fixture (scripted-peer): P1-OPENAI-08
  test('provider factory, Chat generate and Chat SSE keep their public wire',
      () async {
    final peer = _ScriptedOpenAiPeer();
    final provider = createOpenAi(
      apiKey: 'fixture-key',
      baseUrl: 'https://peer.invalid/v1/',
      organization: 'org-fixture',
      project: 'project-fixture',
      headers: const <String, String>{'x-fixed-peer': 'scripted'},
      client: peer,
    );

    expect(provider.languageModel('gpt-5.4').provider, 'openai.responses');
    expect(provider.chat('gpt-5.4').provider, 'openai.chat');
    expect(provider.responses('gpt-5.4').provider, 'openai.responses');
    expect(
      () => createOpenAi(apiKey: 'fixture-key', baseUrl: ''),
      throwsA(
        isA<InvalidArgumentError>().having(
          (error) => error.argument,
          'argument',
          'baseUrl',
        ),
      ),
    );

    final generated = await provider.chat('gpt-5.4').doGenerate(
          const LanguageModelCallOptions(
            prompt: <LanguageModelMessage>[
              SystemMessage('Be concise.'),
              UserMessage(<UserContentPart>[TextPart('weather')]),
            ],
            tools: <LanguageModelTool>[
              FunctionTool(
                name: 'get_weather',
                description: 'Get weather',
                inputSchema: JsonSchema(<String, Object?>{
                  'type': 'object',
                  'properties': <String, Object?>{
                    'city': <String, Object?>{'type': 'string'},
                  },
                }),
              ),
            ],
            responseFormat: ResponseFormatJson(
              name: 'answer',
              schema: JsonSchema(<String, Object?>{'type': 'object'}),
            ),
          ),
        );

    expect(generated.content, const <LanguageModelContent>[
      TextContent('chat-ok'),
    ]);
    final chatRequest = peer.requests.first;
    expect(
        chatRequest.url.toString(), 'https://peer.invalid/v1/chat/completions');
    expect(chatRequest.headers['Authorization'], 'Bearer fixture-key');
    expect(chatRequest.headers['OpenAI-Organization'], 'org-fixture');
    expect(chatRequest.headers['OpenAI-Project'], 'project-fixture');
    expect(chatRequest.headers['x-fixed-peer'], 'scripted');
    expect(peer.jsonBodies.first['messages'], <Object?>[
      <String, Object?>{'role': 'developer', 'content': 'Be concise.'},
      <String, Object?>{'role': 'user', 'content': 'weather'},
    ]);
    expect(peer.jsonBodies.first['tools'], <Object?>[
      <String, Object?>{
        'type': 'function',
        'function': <String, Object?>{
          'name': 'get_weather',
          'description': 'Get weather',
          'parameters': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'city': <String, Object?>{'type': 'string'},
            },
          },
        },
      },
    ]);
    expect(
      peer.jsonBodies.first['response_format'],
      <String, Object?>{
        'type': 'json_schema',
        'json_schema': <String, Object?>{
          'schema': <String, Object?>{'type': 'object'},
          'strict': true,
          'name': 'answer',
        },
      },
    );

    final streamed = await provider.chat('gpt-5.4').doStream(
          const LanguageModelCallOptions(
            prompt: <LanguageModelMessage>[
              UserMessage(<UserContentPart>[TextPart('stream tool')]),
            ],
          ),
        );
    final parts = await streamed.stream.toList();
    expect(parts.whereType<ToolInputStart>(), hasLength(1));
    expect(
      parts.whereType<ToolCall>().single,
      const ToolCall(
        toolCallId: 'call_weather',
        toolName: 'get_weather',
        input: '{"city":"Shanghai"}',
      ),
    );
    final finish = parts.whereType<FinishPart>().single;
    expect(finish.finishReason.unified, FinishReasonType.toolCalls);
    expect(finish.usage.inputTokens.total, 8);
    expect(finish.usage.outputTokens.total, 4);
  });

  test('Responses items, stored IDs, typed errors and provider tools align',
      () async {
    final peer = _ScriptedOpenAiPeer();
    final provider = createOpenAi(
      apiKey: 'fixture-key',
      baseUrl: 'https://peer.invalid/v1',
      client: peer,
    );
    final model = provider.responses('gpt-5.4');
    final generated = await model.doGenerate(
      LanguageModelCallOptions(
        prompt: const <LanguageModelMessage>[
          UserMessage(<UserContentPart>[TextPart('use computer')]),
        ],
        tools: <LanguageModelTool>[
          openAiTools.webSearch(),
          openAiTools.fileSearch(vectorStoreIds: const <String>['vs_1']),
          openAiTools.codeInterpreter(),
          openAiTools.computer(),
        ],
      ),
    );

    expect(peer.jsonBodies.single['tools'], <Object?>[
      <String, Object?>{'type': 'web_search'},
      <String, Object?>{
        'type': 'file_search',
        'vector_store_ids': <Object?>['vs_1'],
      },
      <String, Object?>{
        'type': 'code_interpreter',
        'container': <String, Object?>{'type': 'auto'},
      },
      <String, Object?>{'type': 'computer'},
    ]);
    final computer = generated.content.whereType<ToolCall>().single;
    expect(computer.toolCallId, 'computer_call_1');
    expect(computer.toolName, 'computer');
    expect(jsonDecode(computer.input), <String, Object?>{
      'actions': <Object?>[
        <String, Object?>{
          'type': 'scroll',
          'x': 10,
          'y': 20,
          'scrollX': 0,
          'scrollY': 100,
        },
        <String, Object?>{'type': 'screenshot'},
      ],
      'pendingSafetyChecks': <Object?>[
        <String, Object?>{
          'id': 'safe_1',
          'code': 'confirm_action',
        },
      ],
      'status': 'completed',
    });
    expect(
      computer.providerMetadata?['openai']?['itemId'],
      'computer_item_1',
    );

    final replay = convertToOpenAiResponsesInput(
      prompt: const <LanguageModelMessage>[
        AssistantMessage(<AssistantContentPart>[
          ToolResultPart(
            toolCallId: 'call_search',
            toolName: 'tool_search',
            output: ToolResultJson(<String, Object?>{
              'tools': <Object?>[],
            }),
            providerOptions: <String, JsonObject>{
              'openai': <String, Object?>{'itemId': 'tso_stored'},
            },
          ),
        ]),
      ],
      systemMessageMode: SystemMessageMode.system,
      store: true,
      tools: <LanguageModelTool>[
        openAiTools.toolSearch(execution: 'client'),
      ],
    );
    expect(replay.input, <JsonObject>[
      <String, Object?>{'type': 'item_reference', 'id': 'tso_stored'},
    ]);

    final screenshot = convertToOpenAiResponsesInput(
      prompt: const <LanguageModelMessage>[
        ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'computer_call_1',
            toolName: 'computer',
            output: ToolResultJson(<String, Object?>{
              'output': <String, Object?>{
                'type': 'computer_screenshot',
                'fileId': 'file_screen_1',
              },
            }),
          ),
        ]),
      ],
      systemMessageMode: SystemMessageMode.system,
      store: false,
      tools: <LanguageModelTool>[openAiTools.computer()],
    );
    expect(screenshot.input.single, <String, Object?>{
      'type': 'computer_call_output',
      'call_id': 'computer_call_1',
      'output': <String, Object?>{
        'type': 'computer_screenshot',
        'file_id': 'file_screen_1',
      },
    });

    await expectLater(
      model.doGenerate(
        const LanguageModelCallOptions(
          prompt: <LanguageModelMessage>[
            UserMessage(<UserContentPart>[TextPart('wrong endpoint')]),
          ],
          headers: <String, String>{'x-fixture': 'missing-output'},
        ),
      ),
      throwsA(
        isA<ApiCallError>()
            .having((error) => error.statusCode, 'statusCode', 200)
            .having((error) => error.isRetryable, 'isRetryable', isFalse),
      ),
    );

    final streamed = await model.doStream(
      const LanguageModelCallOptions(
        prompt: <LanguageModelMessage>[
          UserMessage(<UserContentPart>[TextPart('responses stream')]),
        ],
      ),
    );
    final parts = await streamed.stream.toList();
    expect(
      parts.whereType<TextDelta>().map((part) => part.delta).join(),
      'responses-ok',
    );
    expect(parts.last, isA<FinishPart>());
  });

  test('embedding, image, speech, transcription, files and skills round-trip',
      () async {
    final peer = _ScriptedOpenAiPeer();
    final provider = createOpenAi(
      apiKey: 'fixture-key',
      baseUrl: 'https://peer.invalid/v1',
      client: peer,
    );

    final embeddings =
        await provider.embeddingModel('text-embedding-3-small').doEmbed(
              const EmbeddingModelCallOptions(values: <String>['one', 'two']),
            );
    final image = await provider.imageModel('gpt-image-1').doGenerate(
          const ImageModelCallOptions(prompt: 'draw', n: 1),
        );
    final speech = await provider.speechModel('tts-1').doGenerate(
          const SpeechModelCallOptions(text: 'hello'),
        );
    final transcription =
        await provider.transcriptionModel('whisper-1').doGenerate(
              TranscriptionModelCallOptions(
                audio: TranscriptionAudioBytes(
                  Uint8List.fromList(<int>[1, 2, 3]),
                ),
                mediaType: 'audio/wav',
              ),
            );
    final file = await provider.files().uploadFile(
          const FilesUploadOptions(
            data: FileDataText('fixture'),
            mediaType: 'text/plain',
            filename: 'fixture.txt',
          ),
        );
    final skill = await provider.skills().uploadSkill(
          const SkillsUploadOptions(
            files: <SkillFile>[
              SkillFile(path: 'SKILL.md', data: FileDataText('# Fixture')),
            ],
          ),
        );

    expect(embeddings.embeddings, <List<double>>[
      <double>[0.1, 0.2],
      <double>[0.3, 0.4],
    ]);
    expect(image.images.single, Uint8List.fromList(<int>[1, 2, 3]));
    expect(speech.audio, Uint8List.fromList(<int>[4, 5, 6]));
    expect(transcription.text, 'scripted transcript');
    expect(file.providerReference, <String, String>{'openai': 'file_fixture'});
    expect(
      skill.providerReference,
      <String, String>{'openai': 'skill_fixture'},
    );
    expect(
      peer.requests.map((request) => request.url.path),
      containsAll(<String>[
        '/v1/embeddings',
        '/v1/images/generations',
        '/v1/audio/speech',
        '/v1/audio/transcriptions',
        '/v1/files',
        '/v1/skills',
      ]),
    );
  });

  test('realtime transcription preserves auth, frame order and cancellation',
      () async {
    final connector = _ScriptedWebSocketConnector();
    final model = OpenAiTranscriptionModel(
      'gpt-realtime-whisper',
      config: OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://peer.invalid/v1',
        headers: () => const <String, String>{
          'Authorization': 'Bearer original-key',
        },
        webSocketConnector: connector.call,
      ),
    );
    final result = await model.doStream(
      TranscriptionModelStreamOptions(
        audio: Stream<TranscriptionAudio>.fromIterable(
          <TranscriptionAudio>[
            TranscriptionAudioBytes(Uint8List.fromList(<int>[1, 2, 3])),
          ],
        ),
        inputAudioFormat: const TranscriptionInputAudioFormat(
          type: 'audio/pcm',
          rate: 24000,
        ),
        headers: const <String, String>{
          'authorization': 'Bearer rotated-key',
        },
        providerOptions: const <String, JsonObject>{
          'openai': <String, Object?>{'language': 'en'},
        },
      ),
    );
    final parts = await result.stream.toList();

    expect(connector.url.toString(),
        'wss://peer.invalid/v1/realtime?intent=transcription');
    expect(connector.protocols, <String>[
      'realtime',
      'openai-insecure-api-key.rotated-key',
    ]);
    expect(
      connector.headers.entries
          .where((entry) => entry.key.toLowerCase() == 'authorization')
          .single
          .value,
      'Bearer rotated-key',
    );
    expect(
      connector.connection.clientMessages.map(
        (message) => jsonDecode(message)['type'],
      ),
      <Object?>[
        'session.update',
        'input_audio_buffer.append',
        'input_audio_buffer.commit',
      ],
    );
    expect(parts.whereType<TranscriptionDelta>().single.delta, 'scripted ');
    expect(parts.whereType<TranscriptionFinish>().single.text,
        'scripted transcript');
    expect(connector.connection.closeCode, 1000);

    final cancelConnector = _ScriptedWebSocketConnector(autoComplete: false);
    final cancelModel = OpenAiTranscriptionModel(
      'gpt-realtime-whisper',
      config: OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://peer.invalid/v1',
        headers: () => const <String, String>{
          'Authorization': 'Bearer fixture-key',
        },
        webSocketConnector: cancelConnector.call,
      ),
    );
    var audioCancelled = false;
    final audio = StreamController<TranscriptionAudio>(
      onCancel: () {
        audioCancelled = true;
      },
    );
    final cancelled = await cancelModel.doStream(
      TranscriptionModelStreamOptions(
        audio: audio.stream,
        inputAudioFormat:
            const TranscriptionInputAudioFormat(type: 'audio/pcm'),
      ),
    );
    final subscription = cancelled.stream.listen((_) {});
    await cancelConnector.connection.waitForMessages(1);
    await subscription.cancel();
    expect(audioCancelled, isTrue);
    expect(cancelConnector.connection.closed, isTrue);
  });
}

final class _ScriptedOpenAiPeer extends http.BaseClient {
  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  final List<JsonObject> jsonBodies = <JsonObject>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    JsonObject? body;
    if (request is http.Request && request.body.isNotEmpty) {
      body = jsonDecode(request.body) as JsonObject;
      jsonBodies.add(body);
    }

    switch (request.url.path) {
      case '/v1/chat/completions':
        if (body?['stream'] == true) {
          return _sse(_chatToolStream);
        }
        return _json(<String, Object?>{
          'id': 'chatcmpl_fixture',
          'created': 1700000000,
          'model': 'gpt-5.4',
          'choices': <Object?>[
            <String, Object?>{
              'index': 0,
              'message': <String, Object?>{
                'role': 'assistant',
                'content': 'chat-ok',
              },
              'finish_reason': 'stop',
            },
          ],
          'usage': <String, Object?>{
            'prompt_tokens': 4,
            'completion_tokens': 1,
            'total_tokens': 5,
          },
        });
      case '/v1/responses':
        if (request.headers['x-fixture'] == 'missing-output') {
          return _json(<String, Object?>{
            'id': 'chatcmpl_wrong',
            'object': 'chat.completion',
            'choices': <Object?>[],
          });
        }
        if (body?['stream'] == true) {
          return _sse(_responsesTextStream);
        }
        return _json(<String, Object?>{
          'id': 'resp_fixture',
          'created_at': 1700000000,
          'model': 'gpt-5.4',
          'output': <Object?>[
            <String, Object?>{
              'type': 'computer_call',
              'id': 'computer_item_1',
              'call_id': 'computer_call_1',
              'status': 'completed',
              'actions': <Object?>[
                <String, Object?>{
                  'type': 'scroll',
                  'x': 10,
                  'y': 20,
                  'scroll_x': 0,
                  'scroll_y': 100,
                },
                <String, Object?>{'type': 'screenshot'},
              ],
              'pending_safety_checks': <Object?>[
                <String, Object?>{
                  'id': 'safe_1',
                  'code': 'confirm_action',
                },
              ],
            },
          ],
          'usage': <String, Object?>{
            'input_tokens': 4,
            'output_tokens': 2,
          },
        });
      case '/v1/embeddings':
        return _json(<String, Object?>{
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
            'prompt_tokens': 2,
            'total_tokens': 2,
          },
        });
      case '/v1/images/generations':
        return _json(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'b64_json': base64Encode(<int>[1, 2, 3])
            },
          ],
        });
      case '/v1/audio/speech':
        return _bytes(<int>[4, 5, 6], contentType: 'audio/mpeg');
      case '/v1/audio/transcriptions':
        return _json(<String, Object?>{
          'text': 'scripted transcript',
          'language': 'english',
          'duration': 1.0,
          'segments': <Object?>[],
        });
      case '/v1/files':
        return _json(<String, Object?>{
          'id': 'file_fixture',
          'filename': 'fixture.txt',
          'purpose': 'assistants',
          'bytes': 7,
          'created_at': 1700000000,
          'status': 'processed',
        });
      case '/v1/skills':
        return _json(<String, Object?>{
          'id': 'skill_fixture',
          'name': 'fixture',
          'description': 'Fixture skill',
          'latest_version': 'v1',
          'default_version': 'v1',
          'created_at': 1700000000,
          'updated_at': 1700000001,
        });
      default:
        return _json(
          <String, Object?>{'error': 'unknown path ${request.url.path}'},
          statusCode: 404,
        );
    }
  }
}

http.StreamedResponse _json(
  JsonObject value, {
  int statusCode = 200,
}) {
  return _bytes(
    utf8.encode(jsonEncode(value)),
    statusCode: statusCode,
    contentType: 'application/json',
  );
}

http.StreamedResponse _sse(String value) {
  return _bytes(
    utf8.encode(value),
    contentType: 'text/event-stream',
  );
}

http.StreamedResponse _bytes(
  List<int> value, {
  int statusCode = 200,
  required String contentType,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(value),
    statusCode,
    headers: <String, String>{'content-type': contentType},
  );
}

const _chatToolStream = '''
data: {"id":"chatcmpl_stream","created":1700000000,"model":"gpt-5.4","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_weather","type":"function","function":{"name":"get_weather","arguments":""}}]}}]}

data: {"id":"chatcmpl_stream","created":1700000000,"model":"gpt-5.4","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"city\\":\\"Shanghai\\"}"}}]}}]}

data: {"id":"chatcmpl_stream","created":1700000000,"model":"gpt-5.4","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: {"choices":[],"usage":{"prompt_tokens":8,"completion_tokens":4,"total_tokens":12}}

data: [DONE]

''';

const _responsesTextStream = '''
data: {"type":"response.created","response":{"id":"resp_stream","created_at":1700000000,"model":"gpt-5.4"}}

data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_stream"}}

data: {"type":"response.output_text.delta","item_id":"msg_stream","delta":"responses-ok"}

data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_stream"}}

data: {"type":"response.completed","response":{"usage":{"input_tokens":3,"output_tokens":1}}}

''';

final class _ScriptedWebSocketConnector {
  _ScriptedWebSocketConnector({this.autoComplete = true});

  final bool autoComplete;
  late Uri url;
  late List<String> protocols;
  late Map<String, String> headers;
  late final _ScriptedWebSocketConnection connection =
      _ScriptedWebSocketConnection(autoComplete: autoComplete);

  OpenAiWebSocketConnection call(
    Uri url, {
    Iterable<String>? protocols,
    Map<String, String>? headers,
  }) {
    this.url = url;
    this.protocols = <String>[...?protocols];
    this.headers = <String, String>{...?headers};
    return connection;
  }
}

final class _ScriptedWebSocketConnection implements OpenAiWebSocketConnection {
  _ScriptedWebSocketConnection({required this.autoComplete});

  final bool autoComplete;
  final StreamController<Object?> _server = StreamController<Object?>();
  final List<String> clientMessages = <String>[];
  final Completer<void> _messageChanged = Completer<void>();
  bool closed = false;
  int? closeCode;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<Object?> get stream => _server.stream;

  @override
  void add(Object? data) {
    final message = data! as String;
    clientMessages.add(message);
    if (!_messageChanged.isCompleted) {
      _messageChanged.complete();
    }
    final decoded = jsonDecode(message) as JsonObject;
    if (autoComplete && decoded['type'] == 'input_audio_buffer.commit') {
      scheduleMicrotask(() {
        if (!_server.isClosed) {
          _server
            ..add(jsonEncode(<String, Object?>{
              'type': 'conversation.item.input_audio_transcription.delta',
              'item_id': 'item_fixture',
              'delta': 'scripted ',
            }))
            ..add(jsonEncode(<String, Object?>{
              'type': 'conversation.item.input_audio_transcription.completed',
              'item_id': 'item_fixture',
              'transcript': 'scripted transcript',
            }));
        }
      });
    }
  }

  Future<void> waitForMessages(int count) async {
    while (clientMessages.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    this.closeCode = closeCode;
    if (!_server.isClosed) {
      await _server.close();
    }
  }
}
