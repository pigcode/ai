import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

const _peerVersion = 'phase1-ai-core-peer-v1';
const _deadline = Duration(seconds: 5);

void main() {
  // Compatibility fixture (real-process): P1-PROVIDER-01
  // Compatibility fixture (real-process): P1-PROVIDER-02
  // Compatibility fixture (real-process): P1-PROVIDER-03
  // Compatibility fixture (real-process): P1-PROVIDER-04
  // Compatibility fixture (real-process): P1-PROVIDER-05
  // Compatibility fixture (real-process): P1-PROVIDER-06
  // Compatibility fixture (real-process): P1-PROVIDER-07
  // Compatibility fixture (real-process): P1-PROVIDER-08
  test('public provider model exchanges all fixtures with the fixed peer',
      () async {
    final peer = await _PeerProcess.start();
    try {
      final model = _ProcessBackedLanguageModel(peer);
      const clientTool = FunctionTool(
        name: 'client_lookup',
        inputSchema: JsonSchema(<String, Object?>{'type': 'object'}),
      );
      const providerTool = ProviderTool(
        id: 'fixture.server_lookup',
        name: 'server_lookup',
        args: <String, Object?>{'region': 'test'},
        supportsDeferredResults: true,
      );
      const options = LanguageModelCallOptions(
        prompt: <LanguageModelMessage>[
          SystemMessage('fixture system'),
          UserMessage(<UserContentPart>[TextPart('hello process')]),
        ],
        tools: <LanguageModelTool>[clientTool, providerTool],
        toolChoice: ToolChoiceAuto(),
        includeRawChunks: true,
      );

      final generated = await model.doGenerate(options);
      expect(generated.content.whereType<TextContent>().single.text,
          'hello process');
      expect(generated.content.whereType<ReasoningContent>(), hasLength(1));
      expect(generated.content.whereType<FileContent>(), hasLength(1));
      expect(generated.content.whereType<SourceContent>(), hasLength(1));
      expect(generated.content.whereType<ToolCall>(), hasLength(1));
      expect(generated.content.whereType<ToolResult>(), hasLength(1));
      expect(generated.content.whereType<CustomContentBlock>(), hasLength(1));
      expect(generated.finishReason.unified, FinishReasonType.other);
      expect(generated.finishReason.raw, 'process_future_reason');
      expect(generated.usage.inputTokens.total, isNull);
      expect(generated.usage.inputTokens.cacheRead, 2);
      expect(generated.usage.outputTokens.total, isNull);
      expect(generated.usage.outputTokens.reasoning, 3);
      expect(generated.warnings.single, isA<CompatibilityWarning>());
      expect(generated.providerMetadata?['fixture']?['transport'], 'stdio');
      expect(generated.request?.body, isA<Map<String, Object?>>());
      expect(generated.response?.headers?['x-fixture'], 'process');

      final normalParts = await (await model.doStream(options)).stream.toList();
      expect(normalParts.whereType<RawPart>(), hasLength(1));
      expect(normalParts.whereType<ToolApprovalRequest>(), hasLength(1));
      expect(normalParts.whereType<FinishPart>(), hasLength(1));
      expect(
        normalParts.where((part) => part is ErrorPart || part is FinishPart),
        hasLength(1),
      );

      final reason = StateError('process abort');
      final cancellation = CancellationController()..cancel(reason);
      final cancelledParts = await (await model.doStream(
        options.copyWith(cancellation: cancellation.signal),
      ))
          .stream
          .toList();
      expect(cancelledParts.whereType<ErrorPart>(), hasLength(1));
      expect(cancelledParts.whereType<FinishPart>(), isEmpty);
      expect(cancelledParts.whereType<ErrorPart>().single.error, same(reason));

      try {
        await model.doGenerate(
          options.copyWith(
            providerOptions: const <String, JsonObject>{
              'fixture': <String, Object?>{'scenario': 'error'},
            },
          ),
        );
        fail('Expected the process adapter to map the peer error.');
      } on ApiCallError catch (error) {
        expect(error.statusCode, 502);
        expect(error.responseHeaders?['x-fixture'], 'process');
        expect(error.responseBody, contains('unknown_operation'));
        expect(error.data, <String, Object?>{'category': 'peer_error'});
        expect(error.isRetryable, isTrue);
      }

      expect(model.specificationVersion, languageModelSpecVersion);
      expect(model.provider, 'fixture');
      expect(model.modelId, 'process-provider-peer');
      await peer.shutdown();
      expect(await peer.process.exitCode.timeout(_deadline), 0);
      expect((await peer.stderrOutput).trim(), isEmpty);
    } finally {
      await peer.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}

final class _ProcessBackedLanguageModel implements LanguageModel {
  _ProcessBackedLanguageModel(this._peer);

  final _PeerProcess _peer;

  @override
  String get specificationVersion => languageModelSpecVersion;

  @override
  String get provider => 'fixture';

  @override
  String get modelId => 'process-provider-peer';

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls =>
      const <String, List<RegExp>>{};

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) async {
    final scenario =
        options.providerOptions?['fixture']?['scenario'] as String?;
    final response = await _peer.request(<String, Object?>{
      'id': 'generate-${_peer.nextRequestId()}',
      'op': scenario == 'error' ? 'triggerError' : 'echo',
      'value': _encodeOptions(options),
    });
    if (response['ok'] != true) {
      throw ApiCallError(
        message: 'Fixed peer rejected the scripted request.',
        url: 'stdio://phase1-ai-core-peer',
        requestBody: _encodeOptions(options),
        statusCode: 502,
        responseHeaders: const <String, String>{'x-fixture': 'process'},
        responseBody: jsonEncode(response),
        data: const <String, Object?>{'category': 'peer_error'},
      );
    }
    final echoed = response['value'] as Map<String, Object?>;
    final promptText = (echoed['prompt'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .where((message) => message['role'] == 'user')
        .expand((message) => (message['text'] as List<Object?>).cast<String>())
        .join();
    return LanguageModelGenerateResult(
      content: <LanguageModelContent>[
        TextContent(promptText),
        const ReasoningContent('process reasoning'),
        const FileContent(
          data: FileDataBase64('ZmlsZQ=='),
          mediaType: 'text/plain',
        ),
        const SourceContent.url(
          id: 'source-1',
          url: 'https://example.test/source',
        ),
        const ToolCall(
          toolCallId: 'call-1',
          toolName: 'client_lookup',
          input: '{"query":"dart"}',
        ),
        const ToolResult(
          toolCallId: 'call-1',
          toolName: 'client_lookup',
          result: <String, Object?>{'answer': 42},
        ),
        const CustomContentBlock(
          'fixture.widget',
          providerMetadata: <String, JsonObject>{
            'fixture': <String, Object?>{'kind': 'widget'},
          },
        ),
      ],
      finishReason: const LanguageModelFinishReason(
        FinishReasonType.other,
        raw: 'process_future_reason',
      ),
      usage: const LanguageModelUsage(
        inputTokens: InputTokens(cacheRead: 2),
        outputTokens: OutputTokens(reasoning: 3),
        raw: <String, Object?>{'cache_read': 2, 'reasoning': 3},
      ),
      warnings: const <Warning>[
        CompatibilityWarning('fixture', details: 'real process peer'),
      ],
      providerMetadata: const <String, JsonObject>{
        'fixture': <String, Object?>{'transport': 'stdio'},
      },
      request: RequestInfo(body: echoed),
      response: const ResponseInfo(
        id: 'process-1',
        modelId: 'process-provider-peer',
        headers: <String, String>{'x-fixture': 'process'},
        body: <String, Object?>{'ok': true},
      ),
    );
  }

  @override
  Future<LanguageModelStreamResult> doStream(
    LanguageModelCallOptions options,
  ) async {
    final response = await _peer.request(<String, Object?>{
      'id': 'stream-${_peer.nextRequestId()}',
      'op': 'echo',
      'value': _encodeOptions(options),
    });
    if (response['ok'] != true) {
      throw StateError('Fixed peer rejected stream setup.');
    }
    final cancellation = options.cancellation;
    if (cancellation?.isCancelled ?? false) {
      return LanguageModelStreamResult(
        stream: Stream<LanguageModelStreamPart>.fromIterable(
          <LanguageModelStreamPart>[
            const StreamStart(<Warning>[]),
            ErrorPart(cancellation!.reason),
          ],
        ),
      );
    }
    return LanguageModelStreamResult(
      stream: Stream<LanguageModelStreamPart>.fromIterable(
        const <LanguageModelStreamPart>[
          StreamStart(<Warning>[]),
          ResponseMetadata(
            id: 'process-1',
            modelId: 'process-provider-peer',
          ),
          RawPart(<String, Object?>{'transport': 'stdio'}),
          ToolApprovalRequest(
            approvalId: 'approval-1',
            toolCallId: 'call-1',
          ),
          FinishPart(
            usage: LanguageModelUsage(
              inputTokens: InputTokens(cacheRead: 2),
              outputTokens: OutputTokens(reasoning: 3),
            ),
            finishReason: LanguageModelFinishReason(
              FinishReasonType.other,
              raw: 'process_future_reason',
            ),
          ),
        ],
      ),
      response: const ResponseInfo(
        id: 'process-1',
        modelId: 'process-provider-peer',
      ),
    );
  }
}

Map<String, Object?> _encodeOptions(LanguageModelCallOptions options) {
  final messages = <Map<String, Object?>>[];
  for (final message in options.prompt) {
    switch (message) {
      case SystemMessage(:final content):
        messages.add(<String, Object?>{
          'role': 'system',
          'text': <String>[content],
        });
      case UserMessage(:final content):
        messages.add(<String, Object?>{
          'role': 'user',
          'text':
              content.whereType<TextPart>().map((part) => part.text).toList(),
        });
      case AssistantMessage():
        messages.add(const <String, Object?>{
          'role': 'assistant',
          'text': <String>[],
        });
      case ToolMessage():
        messages.add(const <String, Object?>{
          'role': 'tool',
          'text': <String>[],
        });
    }
  }
  return <String, Object?>{
    'prompt': messages,
    'tools': <Object?>[
      for (final tool in options.tools ?? const <LanguageModelTool>[])
        switch (tool) {
          FunctionTool(:final name) => <String, Object?>{
              'kind': 'function',
              'name': name,
            },
          ProviderTool(
            :final id,
            :final name,
            :final supportsDeferredResults,
          ) =>
            <String, Object?>{
              'kind': 'provider',
              'id': id,
              'name': name,
              'supportsDeferredResults': supportsDeferredResults,
            },
        },
    ],
    'includeRawChunks': options.includeRawChunks,
    'cancelled': options.cancellation?.isCancelled ?? false,
    'cancellationReason': options.cancellation?.reason?.toString(),
  };
}

final class _PeerProcess {
  _PeerProcess._(
    this.process,
    this._lines,
    this.stderrOutput,
  );

  final Process process;
  final StreamIterator<String> _lines;
  final Future<String> stderrOutput;
  var _requestId = 0;
  var _shutdown = false;

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
    final hasReady = await lines.moveNext().timeout(_deadline);
    expect(hasReady, isTrue);
    final ready = jsonDecode(lines.current) as Map<String, Object?>;
    expect(ready['type'], 'ready');
    expect(ready['version'], _peerVersion);
    expect(ready['sourceBlobHash'], expectedHash);
    expect(ready['host'], InternetAddress.loopbackIPv4.address);
    return _PeerProcess._(process, lines, stderrOutput);
  }

  int nextRequestId() => _requestId++;

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
    final response = await request(<String, Object?>{
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
      await process.exitCode.timeout(const Duration(milliseconds: 10));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
    }
  }
}
