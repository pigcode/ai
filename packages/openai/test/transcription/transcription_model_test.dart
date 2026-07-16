import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

http.StreamedResponse _jsonResponse(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const {'content-type': 'application/json'},
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    headers: headers,
  );
}

final class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;

  http.BaseRequest? lastRequest;
  Map<String, String>? lastFields;
  List<http.MultipartFile>? lastFiles;
  List<int>? lastFileBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    if (request is http.MultipartRequest) {
      lastFields = Map<String, String>.of(request.fields);
      lastFiles = List<http.MultipartFile>.of(request.files);
      lastFileBytes = await request.files
          .singleWhere((file) => file.field == 'file')
          .finalize()
          .toBytes();
    }
    return handler(request);
  }
}

OpenAiConfig _config(
  http.Client client, {
  String providerName = 'openai',
  OpenAiWebSocketConnector? webSocketConnector,
}) {
  return OpenAiConfig(
    providerName: providerName,
    baseUrl: 'https://api.openai.com/v1',
    headers: () => {'Authorization': 'Bearer test-key'},
    client: client,
    webSocketConnector: webSocketConnector ?? connectOpenAiWebSocket,
  );
}

String _successBody() {
  return jsonEncode({
    'text': 'hello world',
    'language': 'english',
    'duration': 1.5,
    'segments': [
      {
        'id': 0,
        'seek': 0,
        'start': 0,
        'end': 1.5,
        'text': 'hello world',
        'tokens': [1, 2],
        'temperature': 0,
        'avg_logprob': -0.1,
        'compression_ratio': 1.0,
        'no_speech_prob': 0.01,
      },
    ],
  });
}

void main() {
  group('OpenAiTranscriptionModel — 基础字段', () {
    test('provider/modelId/specificationVersion', () {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiTranscriptionModel(
        'whisper-1',
        config: _config(client),
      );

      expect(model.specificationVersion, 'v4');
      expect(model.provider, 'openai.transcription');
      expect(model.modelId, 'whisper-1');
      expect(model, isA<TranscriptionModel>());
    });
  });

  group('OpenAiTranscriptionModel.doGenerate — 请求侧', () {
    test('bytes audio 发送 multipart 到 /audio/transcriptions', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiTranscriptionModel(
        'whisper-1',
        config: _config(client),
      );
      final audio = Uint8List.fromList([1, 2, 3]);

      await model.doGenerate(
        TranscriptionModelCallOptions(
          audio: TranscriptionAudioBytes(audio),
          mediaType: 'audio/wav',
          headers: const {'x-custom': 'v'},
        ),
      );

      expect(
        client.lastRequest!.url.toString(),
        'https://api.openai.com/v1/audio/transcriptions',
      );
      expect(client.lastRequest!.method, 'POST');
      expect(client.lastRequest!.headers['Authorization'], 'Bearer test-key');
      expect(client.lastRequest!.headers['x-custom'], 'v');
      expect(client.lastFields, {
        'model': 'whisper-1',
        'response_format': 'verbose_json',
      });
      expect(client.lastFiles, hasLength(1));
      expect(client.lastFiles!.single.field, 'file');
      expect(client.lastFiles!.single.filename, 'audio.wav');
      expect(client.lastFileBytes, [1, 2, 3]);
    });

    test('base64 audio 会解码为 multipart file bytes', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiTranscriptionModel(
        'whisper-1',
        config: _config(client),
      );

      await model.doGenerate(
        TranscriptionModelCallOptions(
          audio: TranscriptionAudioBase64(base64Encode([4, 5, 6])),
          mediaType: 'audio/mp3',
        ),
      );

      expect(client.lastFiles!.single.filename, 'audio.mp3');
      expect(client.lastFileBytes, [4, 5, 6]);
    });

    test('providerOptions.openai 常用字段进入 multipart fields', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiTranscriptionModel(
        'gpt-4o-transcribe',
        config: _config(client),
      );

      await model.doGenerate(
        TranscriptionModelCallOptions(
          audio: TranscriptionAudioBytes(Uint8List.fromList([1])),
          mediaType: 'audio/wav',
          providerOptions: const {
            'openai': {
              'language': 'en',
              'prompt': 'domain words',
              'temperature': 0.2,
            },
          },
        ),
      );

      expect(client.lastFields, {
        'model': 'gpt-4o-transcribe',
        'response_format': 'json',
        'language': 'en',
        'prompt': 'domain words',
        'temperature': '0.2',
      });
    });

    test('dated gpt-4o transcribe model with openai options uses json format',
        () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiTranscriptionModel(
        'gpt-4o-mini-transcribe-2025-12-15',
        config: _config(client),
      );

      await model.doGenerate(
        TranscriptionModelCallOptions(
          audio: TranscriptionAudioBytes(Uint8List.fromList([1])),
          mediaType: 'audio/wav',
          providerOptions: const {
            'openai': {
              'include': ['logprobs'],
            },
          },
        ),
      );

      expect(client.lastFields, {
        'model': 'gpt-4o-mini-transcribe-2025-12-15',
        'response_format': 'json',
      });
      expect(client.lastFiles, hasLength(2));
      expect(client.lastFiles!.last.field, 'include[]');
    });

    test(
        'timestamp granularities on gpt transcribe are rejected before request',
        () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiTranscriptionModel(
        'gpt-4o-transcribe',
        config: _config(client),
      );

      await expectLater(
        model.doGenerate(
          TranscriptionModelCallOptions(
            audio: TranscriptionAudioBytes(Uint8List.fromList([1])),
            mediaType: 'audio/wav',
            providerOptions: const {
              'openai': {
                'timestampGranularities': ['word'],
              },
            },
          ),
        ),
        throwsA(
          isA<UnsupportedFunctionalityError>().having(
            (e) => e.functionality,
            'functionality',
            'timestamp granularities with gpt-4o-transcribe',
          ),
        ),
      );
      expect(client.lastRequest, isNull);
    });
  });

  group('OpenAiTranscriptionModel.doGenerate — 响应侧', () {
    test('成功响应解码 transcript、segments、language、duration 与 response', () async {
      final body = _successBody();
      final client = _RecordingClient(
        (request) async => _jsonResponse(
          body,
          headers: {
            'content-type': 'application/json',
            'x-request-id': 'req-1',
          },
        ),
      );
      final model = OpenAiTranscriptionModel(
        'whisper-1',
        config: _config(client),
      );

      final result = await model.doGenerate(
        TranscriptionModelCallOptions(
          audio: TranscriptionAudioBytes(Uint8List.fromList([1])),
          mediaType: 'audio/wav',
        ),
      );

      expect(result.text, 'hello world');
      expect(result.segments.single.text, 'hello world');
      expect(result.segments.single.startSecond, 0);
      expect(result.segments.single.endSecond, 1.5);
      expect(result.language, 'en');
      expect(result.durationInSeconds, 1.5);
      expect(result.warnings, isEmpty);
      expect(result.response!.modelId, 'whisper-1');
      expect(result.response!.headers!['x-request-id'], 'req-1');
      expect(result.response!.body, jsonDecode(body));
    });

    test('错误响应经 openAiFailedResponseHandler 抛 ApiCallError', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(
          '{"error":{"message":"bad audio"}}',
          statusCode: 400,
          headers: const {'content-type': 'application/json'},
        ),
      );
      final model = OpenAiTranscriptionModel(
        'whisper-1',
        config: _config(client),
      );

      await expectLater(
        model.doGenerate(
          TranscriptionModelCallOptions(
            audio: TranscriptionAudioBytes(Uint8List.fromList([1])),
            mediaType: 'audio/wav',
          ),
        ),
        throwsA(
          isA<ApiCallError>()
              .having((e) => e.message, 'message', 'bad audio')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('成功响应结构错误原样抛 TypeValidationError,不包装成 ApiCallError', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse('{"language":"english"}'),
      );
      final model = OpenAiTranscriptionModel(
        'whisper-1',
        config: _config(client),
      );

      await expectLater(
        model.doGenerate(
          TranscriptionModelCallOptions(
            audio: TranscriptionAudioBytes(Uint8List.fromList([1])),
            mediaType: 'audio/wav',
          ),
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('发送阶段传输错误会映射为 ApiCallError', () async {
      final client = _RecordingClient(
        (request) async => throw http.ClientException('network down'),
      );
      final model = OpenAiTranscriptionModel(
        'whisper-1',
        config: _config(client),
      );

      await expectLater(
        model.doGenerate(
          TranscriptionModelCallOptions(
            audio: TranscriptionAudioBytes(Uint8List.fromList([1])),
            mediaType: 'audio/wav',
          ),
        ),
        throwsA(
          isA<ApiCallError>()
              .having((e) => e.statusCode, 'statusCode', isNull)
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });
  });

  group('OpenAiTranscriptionModel.doStream — 请求侧', () {
    test('gpt-realtime-whisper exposes streaming transcription', () {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiTranscriptionModel(
        'gpt-realtime-whisper',
        config: _config(client),
      );

      expect(model, isA<StreamableTranscriptionModel>());
    });

    test('gpt-realtime-whisper streams realtime transcription events',
        () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final connector = _FakeOpenAiWebSocketConnector();
      final model = OpenAiTranscriptionModel(
        'gpt-realtime-whisper',
        config: _config(client, webSocketConnector: connector.call),
      );

      final result = await model.doStream(
        TranscriptionModelStreamOptions(
          audio: Stream<TranscriptionAudio>.fromIterable([
            TranscriptionAudioBytes(Uint8List.fromList([1, 2, 3])),
            const TranscriptionAudioBase64('BAUG'),
          ]),
          inputAudioFormat: const TranscriptionInputAudioFormat(
            type: 'audio/pcm',
            rate: 24000,
          ),
          providerOptions: const {
            'openai': {
              'language': 'en',
              'streaming': {
                'delay': 'low',
                'include': ['logprobs'],
              },
            },
          },
          includeRawChunks: true,
          headers: const {
            'authorization': 'Bearer rotated-key',
            'OpenAI-Organization': 'org-1',
            'OpenAI-Project': 'proj-1',
          },
        ),
      );

      expect(
        connector.url.toString(),
        'wss://api.openai.com/v1/realtime?intent=transcription',
      );
      expect(connector.protocols, [
        'realtime',
        'openai-insecure-api-key.rotated-key',
        'openai-organization.org-1',
        'openai-project.proj-1',
      ]);
      expect(connector.headers, {
        'Authorization': 'Bearer rotated-key',
        'OpenAI-Organization': 'org-1',
        'OpenAI-Project': 'proj-1',
      });
      expect(result.request!.body, {
        'type': 'session.update',
        'session': {
          'type': 'transcription',
          'audio': {
            'input': {
              'format': {'type': 'audio/pcm', 'rate': 24000},
              'transcription': {
                'model': 'gpt-realtime-whisper',
                'language': 'en',
                'delay': 'low',
              },
              'turn_detection': null,
            },
          },
          'include': ['logprobs'],
        },
      });

      final partsFuture = result.stream.toList();
      await connector.connection.waitForClientMessages(4);
      expect(connector.connection.clientMessages, [
        jsonEncode(result.request!.body),
        jsonEncode({
          'type': 'input_audio_buffer.append',
          'audio': 'AQID',
        }),
        jsonEncode({
          'type': 'input_audio_buffer.append',
          'audio': 'BAUG',
        }),
        jsonEncode({'type': 'input_audio_buffer.commit'}),
      ]);

      connector.connection.serverAdd(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.delta',
        'item_id': 'item_1',
        'delta': 'hel',
      }));
      connector.connection.serverAdd(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': 'item_1',
        'transcript': 'hello',
      }));

      expect(await partsFuture, [
        const TranscriptionStreamStart([]),
        const TranscriptionRaw({
          'type': 'conversation.item.input_audio_transcription.delta',
          'item_id': 'item_1',
          'delta': 'hel',
        }),
        const TranscriptionDelta(id: 'item_1', delta: 'hel'),
        const TranscriptionRaw({
          'type': 'conversation.item.input_audio_transcription.completed',
          'item_id': 'item_1',
          'transcript': 'hello',
        }),
        const TranscriptionFinal(id: 'item_1', text: 'hello'),
        const TranscriptionFinish(
          text: 'hello',
          segments: [],
          language: 'en',
        ),
      ]);
      expect(connector.connection.closeCode, 1000);
    });

    test('gpt-realtime-whisper maps failed transcription events', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final connector = _FakeOpenAiWebSocketConnector();
      final model = OpenAiTranscriptionModel(
        'gpt-realtime-whisper',
        config: _config(client, webSocketConnector: connector.call),
      );

      final result = await model.doStream(
        const TranscriptionModelStreamOptions(
          audio: Stream<TranscriptionAudio>.empty(),
          inputAudioFormat: TranscriptionInputAudioFormat(
            type: 'audio/pcm',
          ),
        ),
      );

      final partsFuture = result.stream.toList();
      await connector.connection.waitForClientMessages(2);
      connector.connection.serverAdd(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.failed',
        'item_id': 'item_1',
        'error': {'message': 'audio could not be decoded'},
      }));

      final parts = await partsFuture;
      expect(parts, hasLength(2));
      expect(parts.first, const TranscriptionStreamStart([]));
      expect(
        parts.last,
        isA<TranscriptionStreamError>().having(
          (part) => part.error.toString(),
          'error',
          'Exception: audio could not be decoded',
        ),
      );
    });

    test('gpt-realtime-whisper reports an early WebSocket close', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final connector = _FakeOpenAiWebSocketConnector();
      final model = OpenAiTranscriptionModel(
        'gpt-realtime-whisper',
        config: _config(client, webSocketConnector: connector.call),
      );

      final result = await model.doStream(
        const TranscriptionModelStreamOptions(
          audio: Stream<TranscriptionAudio>.empty(),
          inputAudioFormat: TranscriptionInputAudioFormat(
            type: 'audio/pcm',
          ),
        ),
      );

      final partsFuture = result.stream.toList();
      await connector.connection.waitForClientMessages(2);
      await connector.connection.serverClose();

      final parts = await partsFuture;
      expect(parts, hasLength(2));
      expect(parts.first, const TranscriptionStreamStart([]));
      expect(
        parts.last,
        isA<TranscriptionStreamError>().having(
          (part) => part.error.toString(),
          'error',
          'Bad state: OpenAI realtime transcription connection closed before '
              'completion',
        ),
      );
      expect(connector.connection.closed, isTrue);
    });

    test('non-realtime transcription models reject streaming calls', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiTranscriptionModel(
        'whisper-1',
        config: _config(client),
      );

      await expectLater(
        model.doStream(
          const TranscriptionModelStreamOptions(
            audio: Stream<TranscriptionAudio>.empty(),
            inputAudioFormat: TranscriptionInputAudioFormat(
              type: 'audio/pcm',
            ),
          ),
        ),
        throwsA(
          isA<UnsupportedFunctionalityError>().having(
            (e) => e.functionality,
            'functionality',
            'streaming transcription with whisper-1',
          ),
        ),
      );
    });

    test('streaming call warns about REST-only provider options', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final connector = _FakeOpenAiWebSocketConnector();
      final model = OpenAiTranscriptionModel(
        'gpt-realtime-whisper',
        config: _config(client, webSocketConnector: connector.call),
      );

      final result = await model.doStream(
        const TranscriptionModelStreamOptions(
          audio: Stream<TranscriptionAudio>.empty(),
          inputAudioFormat: TranscriptionInputAudioFormat(
            type: 'audio/pcm',
          ),
          providerOptions: {
            'openai': {
              'language': 'en',
              'include': ['logprobs'],
              'prompt': 'domain words',
              'temperature': 0.2,
              'timestampGranularities': ['word'],
            },
          },
        ),
      );

      expect(
        await result.stream.first,
        const TranscriptionStreamStart([
          UnsupportedWarning(
            'providerOptions.openai.include',
            details: 'OpenAI streaming transcription does not support include.',
          ),
          UnsupportedWarning(
            'providerOptions.openai.prompt',
            details: 'OpenAI streaming transcription does not support prompt.',
          ),
          UnsupportedWarning(
            'providerOptions.openai.temperature',
            details:
                'OpenAI streaming transcription does not support temperature.',
          ),
          UnsupportedWarning(
            'providerOptions.openai.timestampGranularities',
            details: 'OpenAI streaming transcription does not support '
                'timestampGranularities.',
          ),
        ]),
      );
      expect(result.request!.body, {
        'type': 'session.update',
        'session': {
          'type': 'transcription',
          'audio': {
            'input': {
              'format': {'type': 'audio/pcm'},
              'transcription': {
                'model': 'gpt-realtime-whisper',
                'language': 'en',
              },
              'turn_detection': null,
            },
          },
        },
      });
    });

    test('canceling the transcription stream closes WebSocket and audio',
        () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final connector = _FakeOpenAiWebSocketConnector();
      final model = OpenAiTranscriptionModel(
        'gpt-realtime-whisper',
        config: _config(client, webSocketConnector: connector.call),
      );
      var audioCancelled = false;
      final audio = StreamController<TranscriptionAudio>(
        onCancel: () {
          audioCancelled = true;
        },
      );

      final result = await model.doStream(
        TranscriptionModelStreamOptions(
          audio: audio.stream,
          inputAudioFormat: const TranscriptionInputAudioFormat(
            type: 'audio/pcm',
          ),
        ),
      );

      final subscription = result.stream.listen((_) {});
      await connector.connection.waitForClientMessages(1);
      await subscription.cancel();

      expect(connector.connection.closed, isTrue);
      expect(audioCancelled, isTrue);
    });

    test('cancellation signal emits terminal error and cleans up', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final connector = _FakeOpenAiWebSocketConnector();
      final model = OpenAiTranscriptionModel(
        'gpt-realtime-whisper',
        config: _config(client, webSocketConnector: connector.call),
      );
      final cancellation = CancellationController();
      var audioCancelled = false;
      final audio = StreamController<TranscriptionAudio>(
        onCancel: () {
          audioCancelled = true;
        },
      );

      final result = await model.doStream(
        TranscriptionModelStreamOptions(
          audio: audio.stream,
          inputAudioFormat: const TranscriptionInputAudioFormat(
            type: 'audio/pcm',
          ),
          cancellation: cancellation.signal,
        ),
      );

      final partsFuture = result.stream.toList();
      await connector.connection.waitForClientMessages(1);
      cancellation.cancel();

      final parts = await partsFuture;
      expect(parts, hasLength(2));
      expect(parts.first, const TranscriptionStreamStart([]));
      expect(
        parts.last,
        isA<TranscriptionStreamError>().having(
          (part) => part.error.toString(),
          'error',
          'Bad state: OpenAI realtime transcription cancelled',
        ),
      );
      expect(connector.connection.closed, isTrue);
      expect(audioCancelled, isTrue);
    });
  });
}

final class _FakeOpenAiWebSocketConnector {
  late Uri url;
  late List<String> protocols;
  late Map<String, String> headers;
  late _FakeOpenAiWebSocketConnection connection;

  OpenAiWebSocketConnection call(
    Uri url, {
    Iterable<String>? protocols,
    Map<String, String>? headers,
  }) {
    this.url = url;
    this.protocols = [...?protocols];
    this.headers = {...?headers};
    connection = _FakeOpenAiWebSocketConnection();
    return connection;
  }
}

final class _FakeOpenAiWebSocketConnection
    implements OpenAiWebSocketConnection {
  final _incoming = StreamController<Object?>();
  final _messageController = StreamController<void>.broadcast();
  final clientMessages = <Object?>[];
  var closed = false;
  int? closeCode;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<Object?> get stream => _incoming.stream;

  @override
  void add(Object? data) {
    clientMessages.add(data);
    _messageController.add(null);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    this.closeCode = closeCode;
    await _incoming.close();
  }

  void serverAdd(Object? data) {
    _incoming.add(data);
  }

  Future<void> serverClose() => _incoming.close();

  Future<void> waitForClientMessages(int count) async {
    while (clientMessages.length < count) {
      await _messageController.stream.first;
    }
  }
}
