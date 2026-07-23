import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

const _peerVersion = 'phase1-anthropic-peer-v1';
const _deadline = Duration(seconds: 5);

void main() {
  // Compatibility fixture (real-process): P1-ANTHROPIC-01
  // Compatibility fixture (real-process): P1-ANTHROPIC-02
  // Compatibility fixture (real-process): P1-ANTHROPIC-03
  // Compatibility fixture (real-process): P1-ANTHROPIC-04
  // Compatibility fixture (real-process): P1-ANTHROPIC-05
  // Compatibility fixture (real-process): P1-ANTHROPIC-06
  // Compatibility fixture (real-process): P1-ANTHROPIC-07
  // Compatibility fixture (real-process): P1-ANTHROPIC-08
  test(
    'fixed child peer covers Anthropic HTTP, SSE and resource boundaries',
    () async {
      final peer = await _PeerProcess.start();
      final client = http.Client();
      final inspectionClient = HttpClient();
      try {
        final provider = createAnthropic(
          apiKey: 'real-key',
          baseUrl: 'http://${peer.host}:${peer.port}/v1/',
          headers: const <String, String>{'x-provider-header': 'real'},
          name: 'real.messages',
          client: client,
        );
        expect(
            provider.messages('claude-sonnet-4-5').provider, 'real.messages');
        expect(
          () => createAnthropic(apiKey: 'real-key', baseUrl: ''),
          throwsA(isA<InvalidArgumentError>()),
        );

        final model = provider.messages('claude-sonnet-4-5');
        final generated = await model.doGenerate(
          LanguageModelCallOptions(
            prompt: const <LanguageModelMessage>[
              UserMessage(<UserContentPart>[
                TextPart(
                  'Find the source.',
                  providerOptions: <String, JsonObject>{
                    'anthropic': <String, Object?>{
                      'cacheControl': <String, Object?>{'type': 'ephemeral'},
                    },
                  },
                ),
              ]),
            ],
            tools: <LanguageModelTool>[
              anthropicTools.webSearch_20260209(maxUses: 1),
              anthropicTools.webFetch_20260209(
                maxUses: 1,
                citations: const AnthropicWebFetchCitations(enabled: true),
              ),
            ],
            toolChoice: const ToolChoiceAuto(),
            providerOptions: const <String, JsonObject>{
              'real': <String, Object?>{
                'thinking': <String, Object?>{
                  'type': 'enabled',
                  'budgetTokens': 1024,
                },
              },
            },
          ),
        );
        expect(generated.finishReason.unified, FinishReasonType.stop);
        expect(generated.usage.inputTokens.total, 5);
        expect(generated.content.whereType<ToolCall>(), hasLength(2));
        expect(generated.content.whereType<ToolResult>(), hasLength(2));
        expect(generated.content.whereType<SourceContent>(), hasLength(3));
        final text = generated.content.whereType<TextContent>().single;
        expect(text.providerMetadata?['anthropic']?['citations'], hasLength(1));
        expect(
          generated.providerMetadata?['real']?['container'],
          <String, Object?>{
            'expiresAt': '2026-07-24T00:00:00Z',
            'id': 'container-real',
            'skills': null,
          },
        );

        await model.doGenerate(
          LanguageModelCallOptions(
            prompt: <LanguageModelMessage>[
              AssistantMessage(<AssistantContentPart>[
                TextPart(
                  text.text,
                  providerOptions: text.providerMetadata,
                ),
              ]),
              const UserMessage(<UserContentPart>[TextPart('Continue')]),
            ],
          ),
        );

        final future = await provider.messages('future-model').doGenerate(
              const LanguageModelCallOptions(
                prompt: <LanguageModelMessage>[
                  UserMessage(<UserContentPart>[TextPart('Return JSON')]),
                ],
                responseFormat: ResponseFormatJson(
                  schema: JsonSchema(<String, Object?>{'type': 'object'}),
                ),
                providerOptions: <String, JsonObject>{
                  'real': <String, Object?>{
                    'structuredOutputMode': 'jsonTool',
                    'disableParallelToolUse': false,
                  },
                },
              ),
            );
        expect(future.content, const <LanguageModelContent>[
          TextContent('{"ok":true}'),
        ]);
        expect(
          future.warnings.whereType<CompatibilityWarning>().single.feature,
          'maxOutputTokens',
        );
        expect(
          future.warnings.whereType<UnsupportedWarning>().single.feature,
          'providerOptions.anthropic.disableParallelToolUse',
        );

        final streamed = await model.doStream(
          const LanguageModelCallOptions(
            prompt: <LanguageModelMessage>[
              UserMessage(<UserContentPart>[TextPart('Stream')]),
            ],
            tools: <LanguageModelTool>[
              FunctionTool(
                name: 'get_weather',
                inputSchema: JsonSchema(<String, Object?>{'type': 'object'}),
              ),
            ],
          ),
        );
        final parts = await streamed.stream.toList().timeout(_deadline);
        expect(
          parts.whereType<TextDelta>().map((part) => part.delta).join(),
          'real streamed answer',
        );
        expect(
          parts.whereType<TextEnd>().single.providerMetadata?['anthropic']
              ?['citations'],
          hasLength(1),
        );
        expect(
          parts.whereType<ToolCall>().single.toolName,
          'get_weather',
        );
        expect(
          parts.whereType<FinishPart>().single.finishReason.unified,
          FinishReasonType.toolCalls,
        );

        await expectLater(
          model.doStream(
            const LanguageModelCallOptions(
              prompt: <LanguageModelMessage>[
                UserMessage(<UserContentPart>[TextPart('Stream error')]),
              ],
              headers: <String, String>{'x-fixture': 'stream-error'},
            ),
          ),
          throwsA(
            isA<ApiCallError>()
                .having((error) => error.message, 'message', 'real overloaded')
                .having((error) => error.statusCode, 'statusCode', 529)
                .having((error) => error.isRetryable, 'isRetryable', isTrue),
          ),
        );
        await expectLater(
          model.doGenerate(
            const LanguageModelCallOptions(
              prompt: <LanguageModelMessage>[
                UserMessage(<UserContentPart>[TextPart('HTTP error')]),
              ],
              headers: <String, String>{'x-fixture': 'http-error'},
            ),
          ),
          throwsA(
            isA<ApiCallError>()
                .having((error) => error.message, 'message', 'real rate limit')
                .having((error) => error.statusCode, 'statusCode', 429),
          ),
        );

        final file = await provider.files().uploadFile(
              const FilesUploadOptions(
                data: FileDataText('real'),
                mediaType: 'text/plain',
                filename: 'real.txt',
              ),
            );
        final skill = await provider.skills().uploadSkill(
              const SkillsUploadOptions(
                displayTitle: 'Real skill',
                files: <SkillFile>[
                  SkillFile(
                    path: 'SKILL.md',
                    data: FileDataText('# Real'),
                  ),
                ],
              ),
            );
        expect(file.providerReference, <String, String>{
          'anthropic': 'file-real',
        });
        expect(skill.providerReference, <String, String>{
          'anthropic': 'skill-real',
        });

        final observations = await _readJson(
          inspectionClient,
          Uri.parse('http://${peer.host}:${peer.port}/observations'),
        );
        for (final key in <String>[
          'apiKeySeen',
          'versionSeen',
          'providerHeaderSeen',
          'cacheControlSeen',
          'thinkingSeen',
          'providerToolsSeen',
          'citationReplaySeen',
          'serialJsonToolSeen',
          'unknownFallbackSeen',
          'filesMultipartSeen',
          'skillsMultipartSeen',
        ]) {
          expect(observations[key], isTrue, reason: key);
        }
        expect(observations['streamRequestCount'], 1);
        expect(
          observations['paths'],
          <Object?>[
            '/observations',
            '/v1/files',
            '/v1/messages',
            '/v1/skills',
          ],
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
      repositoryRoot.uri.resolve('tool/fixtures/anthropic_peer.dart'),
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
