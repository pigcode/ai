import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

import '../support/scripted_service_provider.dart';

const _peerVersion = 'phase1-ai-core-peer-v1';
const _deadline = Duration(seconds: 5);
const _usage = contracts.LanguageModelUsage(
  inputTokens: contracts.InputTokens(total: 1),
  outputTokens: contracts.OutputTokens(total: 1),
);

void main() {
  // Compatibility fixture (real-process): P1-CORE-12
  // Compatibility fixture (real-process): P1-CORE-13
  // Compatibility fixture (real-process): P1-CORE-14
  // Compatibility fixture (real-process): P1-CORE-15
  // Compatibility fixture (real-process): P1-CORE-16
  test(
    'public middleware, telemetry and service helpers exchange fixed-peer data',
    () async {
      final peer = await _PeerProcess.start();
      final http = HttpClient();
      try {
        final languageModel = _PeerLanguageModel(peer);
        final wrapped = wrapLanguageModel(
          languageModel,
          defaultSettingsMiddleware(
            settings: const DefaultLanguageModelSettings(
              temperature: 0.25,
              headers: <String, String>{'x-peer-lane': 'real-process'},
              providerOptions: <String, contracts.JsonObject>{
                'scripted': <String, Object?>{
                  'nested': <String, Object?>{'default': true},
                },
              },
            ),
          ),
        );
        final telemetry = _TerminalTelemetry();
        final generated = await generateText(
          model: wrapped,
          prompt: 'stdio middleware',
          providerOptions: const <String, contracts.JsonObject>{
            'scripted': <String, Object?>{
              'nested': <String, Object?>{'call': true},
            },
          },
          telemetry: TelemetrySettings(
            recordInputs: false,
            recordOutputs: false,
            integrations: <Telemetry>[telemetry],
          ),
        );

        expect(generated.text, 'stdio-ok');
        expect(languageModel.lastEcho, <String, Object?>{
          'promptCount': 1,
          'temperature': 0.25,
          'headers': <String, Object?>{'x-peer-lane': 'real-process'},
          'providerOptions': <String, Object?>{
            'scripted': <String, Object?>{
              'nested': <String, Object?>{
                'default': true,
                'call': true,
              },
            },
          },
        });
        expect(
          generated.finalStep.providerMetadata,
          const <String, contracts.JsonObject>{
            'fixedPeer': <String, Object?>{'transport': 'stdio'},
          },
        );
        expect(telemetry.events.last, 'end');
        expect(telemetry.startMessages, isEmpty);
        expect(telemetry.endContent, isEmpty);

        final errorTelemetry = _TerminalTelemetry();
        await expectLater(
          generateText(
            model: _PeerLanguageModel(peer, fail: true),
            prompt: 'stdio error',
            telemetry: TelemetrySettings(
              integrations: <Telemetry>[errorTelemetry],
            ),
          ),
          throwsA(isA<StateError>()),
        );
        expect(errorTelemetry.events.where((event) => event == 'error'),
            hasLength(1));
        expect(errorTelemetry.events, isNot(contains('end')));

        final abortTelemetry = _TerminalTelemetry();
        final cancellation = contracts.CancellationController()
          ..cancel('real-process abort');
        await streamText(
          model: languageModel,
          prompt: 'abort',
          cancellation: cancellation.signal,
          telemetry: TelemetrySettings(
            integrations: <Telemetry>[abortTelemetry],
          ),
        ).consumeStream();
        expect(abortTelemetry.events.where((event) => event == 'abort'),
            hasLength(1));
        expect(abortTelemetry.abortReason, 'real-process abort');
        expect(abortTelemetry.events, isNot(contains('error')));
        expect(abortTelemetry.events, isNot(contains('end')));

        final serviceScript = await _postJson(
          http,
          Uri.parse('http://${peer.host}:${peer.port}/echo'),
          const <String, Object?>{
            'values': <Object?>['one', 'three'],
            'documents': <Object?>['first', 'second'],
            'prompt': 'fixed service fixture',
            'providerOptions': <String, Object?>{
              'scripted': <String, Object?>{'lane': 'real-process'},
            },
          },
        );
        expect(serviceScript['ok'], isTrue);
        final serviceBody = serviceScript['body']! as Map<String, Object?>;
        final servicePeer = ScriptedServiceProvider();
        final providerOptions = _providerOptions(
          serviceBody['providerOptions']! as Map<String, Object?>,
        );
        final values = (serviceBody['values']! as List<Object?>).cast<String>();
        final documents =
            (serviceBody['documents']! as List<Object?>).cast<String>();
        final prompt = serviceBody['prompt']! as String;

        final embeddings = await embedMany(
          model: servicePeer.embedding,
          values: values,
          providerOptions: providerOptions,
        );
        final ranking = await rerank<String>(
          model: servicePeer.reranking,
          documents: documents,
          query: 'fixture',
          providerOptions: providerOptions,
        );
        final images = await generateImage(
          model: servicePeer.image,
          prompt: prompt,
          n: 2,
          providerOptions: providerOptions,
        );
        final videos = await generateVideo(
          model: servicePeer.video,
          prompt: prompt,
          n: 2,
          providerOptions: providerOptions,
        );
        final speech = await generateSpeech(
          model: servicePeer.speech,
          text: prompt,
          providerOptions: providerOptions,
        );
        final transcription = await transcribe(
          model: servicePeer.transcription,
          audio: DataBytes(Uint8List.fromList(<int>[1, 2, 3])),
          mediaType: 'audio/wav',
          providerOptions: providerOptions,
        );

        expect(embeddings.embeddings, hasLength(2));
        expect(embeddings.usage.tokens, 2);
        expect(embeddings.warnings, hasLength(2));
        expect(ranking.rerankedDocuments, <String>['second', 'first']);
        expect(images.images, hasLength(2));
        expect(images.warnings, hasLength(2));
        expect(videos.videos, hasLength(2));
        expect(videos.warnings, hasLength(2));
        expect(speech.audio.toList(), <int>[1, 2, 3]);
        expect(transcription.text, 'scripted transcript');
        expect(
          servicePeer.embedding.calls.first.providerOptions,
          providerOptions,
        );
        expect(
          servicePeer.transcription.lastOptions!.providerOptions,
          providerOptions,
        );

        final events = await _readSse(
          http,
          Uri.parse('http://${peer.host}:${peer.port}/sse'),
          const <Object?>[
            <String, Object?>{'type': 'start', 'messageId': 'peer-message'},
            <String, Object?>{
              'type': 'data-future-widget',
              'id': 'widget-1',
              'data': <String, Object?>{'state': 'ready'},
            },
            <String, Object?>{'type': 'abort', 'reason': 'peer abort'},
            <String, Object?>{
              'type': 'error',
              'errorText': 'peer error',
            },
            <String, Object?>{
              'type': 'finish',
              'finishReason': 'stop',
            },
          ],
        );
        final uiChunks = events
            .map((event) => UiMessageChunk.fromJson(event))
            .toList(growable: false);
        final uiErrors = <Object>[];
        final messages = await readUiMessageStream(
          stream: Stream<UiMessageChunk>.fromIterable(uiChunks),
          onError: uiErrors.add,
        ).toList();

        expect(uiChunks[1], isA<DataUiMessageChunk>());
        expect(uiChunks[2], isA<AbortUiMessageChunk>());
        expect(uiChunks[3], isA<ErrorUiMessageChunk>());
        expect(uiChunks[4], isA<FinishUiMessageChunk>());
        expect(uiErrors, <Object>['peer error']);
        expect(messages.last.id, 'peer-message');
        expect(messages.last.parts, const <UiMessagePart>[
          DataUiPart(
            type: 'data-future-widget',
            id: 'widget-1',
            data: <String, Object?>{'state': 'ready'},
          ),
        ]);
        expect(
          await toTextStream(Stream<TextStreamPart>.fromIterable(
            const <TextStreamPart>[
              TextDeltaPart('peer-text', 'peer'),
              AbortPart(reason: 'ignored'),
              ErrorPart('ignored'),
            ],
          )).toList(),
          <String>['peer'],
        );

        final resources = _ResourceProvider(
          servicePeer,
          _PeerFiles(http, peer),
          _PeerSkills(http, peer),
        );
        final registry = createProviderRegistry(
          <String, contracts.Provider>{'peer': resources},
        );
        final uploadedFile = await uploadFile(
          api: registry.files('peer'),
          data: const contracts.FileDataText('fixture body'),
          filename: 'fixture.txt',
          providerOptions: providerOptions,
        );
        final uploadedSkill = await uploadSkill(
          api: registry.skills('peer'),
          files: const <contracts.SkillFile>[
            contracts.SkillFile(
              path: 'SKILL.md',
              data: contracts.FileDataText('# Fixed peer'),
            ),
          ],
          displayTitle: 'Fixed Peer Skill',
          providerOptions: providerOptions,
        );

        expect(uploadedFile.providerReference, const <String, String>{
          'fixedPeer': 'file-1',
        });
        expect(uploadedSkill.providerReference, const <String, String>{
          'fixedPeer': 'skill-1',
        });
        expect(
          () => registry.embeddingModel('missing:model'),
          throwsA(isA<contracts.NoSuchProviderError>()),
        );

        await peer.shutdown();
        expect(await peer.process.exitCode.timeout(_deadline), 0);
        expect((await peer.stderrOutput).trim(), isEmpty);
      } finally {
        http.close(force: true);
        await peer.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

final class _PeerLanguageModel implements contracts.LanguageModel {
  _PeerLanguageModel(this.peer, {this.fail = false});

  final _PeerProcess peer;
  final bool fail;
  Map<String, Object?>? lastEcho;

  @override
  String get specificationVersion => contracts.languageModelSpecVersion;

  @override
  String get provider => 'fixed.peer.language';

  @override
  String get modelId => 'stdio';

  @override
  Map<String, List<RegExp>> get supportedUrls => const <String, List<RegExp>>{};

  @override
  Future<contracts.LanguageModelGenerateResult> doGenerate(
    contracts.LanguageModelCallOptions options,
  ) async {
    final response = await peer.request(<String, Object?>{
      'id': 'language-${peer.nextRequestId()}',
      'op': fail ? 'unknown' : 'echo',
      'value': <String, Object?>{
        'promptCount': options.prompt.length,
        'temperature': options.temperature,
        'headers': options.headers,
        'providerOptions': options.providerOptions,
      },
    });
    if (response['ok'] != true) {
      throw StateError('fixed peer failure: ${response['error']}');
    }
    lastEcho = (response['value']! as Map<String, Object?>);
    return const contracts.LanguageModelGenerateResult(
      content: <contracts.LanguageModelContent>[
        contracts.TextContent('stdio-ok'),
      ],
      finishReason: contracts.LanguageModelFinishReason(
        contracts.FinishReasonType.stop,
      ),
      usage: _usage,
      warnings: <contracts.Warning>[],
      providerMetadata: <String, contracts.JsonObject>{
        'fixedPeer': <String, Object?>{'transport': 'stdio'},
      },
    );
  }

  @override
  Future<contracts.LanguageModelStreamResult> doStream(
    contracts.LanguageModelCallOptions options,
  ) async =>
      const contracts.LanguageModelStreamResult(
        stream: Stream<contracts.LanguageModelStreamPart>.empty(),
      );
}

final class _TerminalTelemetry with Telemetry {
  final List<String> events = <String>[];
  List<ModelMessage>? startMessages;
  List<contracts.LanguageModelContent>? endContent;
  Object? abortReason;

  @override
  void onStart(GenerateTextStartEvent e, TelemetryMetadata m) {
    events.add('start');
  }

  @override
  void onLanguageModelCallStart(
    LanguageModelCallStartEvent e,
    TelemetryMetadata m,
  ) {
    events.add('model-start');
    startMessages = e.messages;
  }

  @override
  void onLanguageModelCallEnd(
    LanguageModelCallEndEvent e,
    TelemetryMetadata m,
  ) {
    events.add('model-end');
    endContent = e.content;
  }

  @override
  void onEnd(GenerateTextEndEvent e, TelemetryMetadata m) {
    events.add('end');
  }

  @override
  void onAbort(GenerateTextAbortEvent e, TelemetryMetadata m) {
    events.add('abort');
    abortReason = e.reason;
  }

  @override
  void onError(Object? error, TelemetryMetadata m) {
    events.add('error');
  }
}

final class _PeerFiles implements contracts.Files {
  _PeerFiles(this.http, this.peer);

  final HttpClient http;
  final _PeerProcess peer;

  @override
  String get specificationVersion => contracts.filesSpecVersion;

  @override
  String get provider => 'fixed.peer.files';

  @override
  Future<contracts.FilesUploadResult> uploadFile(
    contracts.FilesUploadOptions options,
  ) async {
    final response = await _postJson(
      http,
      Uri.parse('http://${peer.host}:${peer.port}/echo'),
      <String, Object?>{
        'kind': 'file',
        'mediaType': options.mediaType,
        'filename': options.filename,
        'providerOptions': options.providerOptions,
      },
    );
    if (response['ok'] != true) {
      throw StateError('fixed peer rejected file upload');
    }
    return contracts.FilesUploadResult(
      providerReference: const <String, String>{'fixedPeer': 'file-1'},
      mediaType: options.mediaType,
      filename: options.filename,
      warnings: const <contracts.Warning>[],
    );
  }
}

final class _PeerSkills implements contracts.Skills {
  _PeerSkills(this.http, this.peer);

  final HttpClient http;
  final _PeerProcess peer;

  @override
  String get specificationVersion => contracts.skillsSpecVersion;

  @override
  String get provider => 'fixed.peer.skills';

  @override
  Future<contracts.SkillsUploadResult> uploadSkill(
    contracts.SkillsUploadOptions options,
  ) async {
    final response = await _postJson(
      http,
      Uri.parse('http://${peer.host}:${peer.port}/echo'),
      <String, Object?>{
        'kind': 'skill',
        'paths': <String>[for (final file in options.files) file.path],
        'displayTitle': options.displayTitle,
        'providerOptions': options.providerOptions,
      },
    );
    if (response['ok'] != true) {
      throw StateError('fixed peer rejected skill upload');
    }
    return contracts.SkillsUploadResult(
      providerReference: const <String, String>{'fixedPeer': 'skill-1'},
      displayTitle: options.displayTitle,
      latestVersion: 'v1',
      warnings: const <contracts.Warning>[],
    );
  }
}

final class _ResourceProvider implements contracts.Provider {
  const _ResourceProvider(this.delegate, this.fileApi, this.skillApi);

  final ScriptedServiceProvider delegate;
  final contracts.Files fileApi;
  final contracts.Skills skillApi;

  @override
  String get specificationVersion => contracts.providerSpecVersion;

  @override
  contracts.LanguageModel languageModel(String modelId) =>
      delegate.languageModel(modelId);

  @override
  contracts.EmbeddingModel embeddingModel(String modelId) =>
      delegate.embeddingModel(modelId);

  @override
  contracts.ImageModel imageModel(String modelId) =>
      delegate.imageModel(modelId);

  @override
  contracts.VideoModel videoModel(String modelId) =>
      delegate.videoModel(modelId);

  @override
  contracts.TranscriptionModel transcriptionModel(String modelId) =>
      delegate.transcriptionModel(modelId);

  @override
  contracts.SpeechModel speechModel(String modelId) =>
      delegate.speechModel(modelId);

  @override
  contracts.RerankingModel rerankingModel(String modelId) =>
      delegate.rerankingModel(modelId);

  @override
  contracts.Files files() => fileApi;

  @override
  contracts.Skills skills() => skillApi;
}

contracts.ProviderOptions _providerOptions(Map<String, Object?> value) {
  return <String, contracts.JsonObject>{
    for (final entry in value.entries)
      entry.key: Map<String, Object?>.from(
        entry.value! as Map<String, Object?>,
      ),
  };
}

Future<Map<String, Object?>> _postJson(
  HttpClient client,
  Uri uri,
  Object? body,
) async {
  final request = await client.postUrl(uri).timeout(_deadline);
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(body));
  final response = await request.close().timeout(_deadline);
  final text = await utf8.decoder.bind(response).join().timeout(_deadline);
  expect(response.statusCode, HttpStatus.ok);
  return jsonDecode(text) as Map<String, Object?>;
}

Future<List<Map<String, Object?>>> _readSse(
  HttpClient client,
  Uri uri,
  List<Object?> events,
) async {
  final request = await client.postUrl(uri).timeout(_deadline);
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(<String, Object?>{'events': events}));
  final response = await request.close().timeout(_deadline);
  expect(response.statusCode, HttpStatus.ok);
  final lines = await utf8.decoder
      .bind(response)
      .transform(const LineSplitter())
      .where((line) => line.startsWith('data: '))
      .toList()
      .timeout(_deadline);
  return <Map<String, Object?>>[
    for (final line in lines)
      jsonDecode(line.substring('data: '.length)) as Map<String, Object?>,
  ];
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
  var _requestId = 0;
  var _shutdown = false;

  int nextRequestId() => _requestId++;

  static Future<_PeerProcess> start() async {
    final repositoryRoot = Directory.current.parent.parent;
    final peerFile = File.fromUri(
      repositoryRoot.uri.resolve('tool/fixtures/ai_core_peer.dart'),
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
    return _PeerProcess._(
      process,
      lines,
      stderrOutput,
      host: ready['host']! as String,
      port: ready['port']! as int,
    );
  }

  Future<Map<String, Object?>> request(Map<String, Object?> request) async {
    process.stdin.writeln(jsonEncode(request));
    await process.stdin.flush();
    expect(await _lines.moveNext().timeout(_deadline), isTrue);
    return jsonDecode(_lines.current) as Map<String, Object?>;
  }

  Future<void> shutdown() async {
    if (_shutdown) {
      return;
    }
    final response = await request(const <String, Object?>{
      'id': 'shutdown',
      'op': 'shutdown',
    });
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
  }
}
