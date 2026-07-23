import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

const _peerVersion = 'phase1-openai-peer-v1';
const _deadline = Duration(seconds: 5);

void main() {
  // Compatibility fixture (real-process): P1-OPENAI-01
  // Compatibility fixture (real-process): P1-OPENAI-02
  // Compatibility fixture (real-process): P1-OPENAI-03
  // Compatibility fixture (real-process): P1-OPENAI-04
  // Compatibility fixture (real-process): P1-OPENAI-05
  // Compatibility fixture (real-process): P1-OPENAI-06
  // Compatibility fixture (real-process): P1-OPENAI-07
  // Compatibility fixture (real-process): P1-OPENAI-08
  test(
    'fixed child peer covers OpenAI HTTP, SSE and WebSocket boundaries',
    () async {
      final peer = await _PeerProcess.start();
      final client = http.Client();
      final inspectionClient = HttpClient();
      try {
        final provider = createOpenAi(
          apiKey: 'fixture-key',
          baseUrl: 'http://${peer.host}:${peer.port}/v1/',
          organization: 'org-real',
          project: 'project-real',
          client: client,
        );

        expect(provider.languageModel('gpt-5.4').provider, 'openai.responses');
        expect(provider.chat('gpt-5.4').provider, 'openai.chat');

        final chat = await provider.chat('gpt-5.4').doGenerate(
              const LanguageModelCallOptions(
                prompt: <LanguageModelMessage>[
                  UserMessage(<UserContentPart>[TextPart('chat')]),
                ],
                tools: <LanguageModelTool>[
                  FunctionTool(
                    name: 'get_weather',
                    inputSchema: JsonSchema(<String, Object?>{
                      'type': 'object',
                    }),
                  ),
                ],
                responseFormat: ResponseFormatJson(
                  name: 'answer',
                  schema: JsonSchema(<String, Object?>{'type': 'object'}),
                ),
              ),
            );
        expect(chat.content, const <LanguageModelContent>[
          TextContent('real-chat-ok'),
        ]);

        final chatStream = await provider.chat('gpt-5.4').doStream(
              const LanguageModelCallOptions(
                prompt: <LanguageModelMessage>[
                  UserMessage(<UserContentPart>[TextPart('chat stream')]),
                ],
              ),
            );
        final chatParts = await chatStream.stream.toList().timeout(_deadline);
        expect(
          chatParts.whereType<ToolCall>().single,
          const ToolCall(
            toolCallId: 'call_real',
            toolName: 'get_weather',
            input: '{"city":"Shanghai"}',
          ),
        );
        expect(
          chatParts.whereType<FinishPart>().single.usage.inputTokens.total,
          8,
        );

        final responses = provider.responses('gpt-5.4');
        final response = await responses.doGenerate(
          LanguageModelCallOptions(
            prompt: const <LanguageModelMessage>[
              UserMessage(<UserContentPart>[TextPart('computer')]),
            ],
            tools: <LanguageModelTool>[
              openAiTools.webSearch(),
              openAiTools.fileSearch(
                vectorStoreIds: const <String>['vs_real'],
              ),
              openAiTools.codeInterpreter(),
              openAiTools.computer(),
            ],
          ),
        );
        final computer = response.content.whereType<ToolCall>().single;
        expect(computer.toolCallId, 'computer_call_real');
        expect(computer.toolName, 'computer');
        expect(
          computer.providerMetadata?['openai']?['itemId'],
          'computer_item_real',
        );
        expect(
          (jsonDecode(computer.input) as JsonObject)['actions'],
          <Object?>[
            <String, Object?>{
              'type': 'click',
              'button': 'left',
              'x': 12,
              'y': 34,
            },
            <String, Object?>{'type': 'screenshot'},
          ],
        );

        final responseStream = await responses.doStream(
          const LanguageModelCallOptions(
            prompt: <LanguageModelMessage>[
              UserMessage(<UserContentPart>[TextPart('responses stream')]),
            ],
          ),
        );
        final responseParts =
            await responseStream.stream.toList().timeout(_deadline);
        expect(
          responseParts.whereType<TextDelta>().map((part) => part.delta).join(),
          'real-responses-ok',
        );
        expect(responseParts.last, isA<FinishPart>());

        await expectLater(
          responses.doGenerate(
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

        final embedding =
            await provider.embeddingModel('text-embedding-3-small').doEmbed(
                  const EmbeddingModelCallOptions(values: <String>['fixture']),
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
                  SkillFile(
                    path: 'SKILL.md',
                    data: FileDataText('# Fixture'),
                  ),
                ],
              ),
            );
        expect(embedding.embeddings.single, <double>[0.1, 0.2]);
        expect(image.images.single, Uint8List.fromList(<int>[1, 2, 3]));
        expect(speech.audio, Uint8List.fromList(<int>[4, 5, 6]));
        expect(transcription.text, 'real transcript');
        expect(file.providerReference, <String, String>{'openai': 'file_real'});
        expect(
          skill.providerReference,
          <String, String>{'openai': 'skill_real'},
        );

        final realtime = provider.transcriptionModel(
          'gpt-realtime-whisper',
        ) as StreamableTranscriptionModel;
        final realtimeResult = await realtime.doStream(
          TranscriptionModelStreamOptions(
            audio: Stream<TranscriptionAudio>.fromIterable(
              <TranscriptionAudio>[
                TranscriptionAudioBytes(
                  Uint8List.fromList(<int>[7, 8, 9]),
                ),
              ],
            ),
            inputAudioFormat: const TranscriptionInputAudioFormat(
              type: 'audio/pcm',
              rate: 24000,
            ),
            providerOptions: const <String, JsonObject>{
              'openai': <String, Object?>{'language': 'en'},
            },
          ),
        );
        final realtimeParts =
            await realtimeResult.stream.toList().timeout(_deadline);
        expect(
          realtimeParts.whereType<TranscriptionDelta>().single.delta,
          'real ',
        );
        expect(
          realtimeParts.whereType<TranscriptionFinish>().single.text,
          'real transcript',
        );

        final observations = await _readJson(
          inspectionClient,
          Uri.parse('http://${peer.host}:${peer.port}/observations'),
        );
        expect(observations['authorizationHeaderSeen'], isTrue);
        expect(observations['websocketAuthorizationSeen'], isTrue);
        expect(
          observations['websocketProtocols'],
          <Object?>['realtime'],
        );
        expect(observations['websocketFrameTypes'], <Object?>[
          'session.update',
          'input_audio_buffer.append',
          'input_audio_buffer.commit',
        ]);
        expect(
          observations['paths'],
          containsAll(<String>[
            '/v1/chat/completions',
            '/v1/responses',
            '/v1/embeddings',
            '/v1/images/generations',
            '/v1/audio/speech',
            '/v1/audio/transcriptions',
            '/v1/files',
            '/v1/skills',
            '/v1/realtime',
          ]),
        );
      } finally {
        client.close();
        inspectionClient.close(force: true);
        await peer.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
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
      repositoryRoot.uri.resolve('tool/fixtures/openai_peer.dart'),
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
      <Object?>[
        'loopback-http',
        'loopback-sse',
        'loopback-websocket',
      ],
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
    final stderrText = await stderrOutput;
    expect(stderrText, isEmpty);
  }
}
