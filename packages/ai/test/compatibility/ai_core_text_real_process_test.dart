import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:test/test.dart';

const _peerVersion = 'phase1-ai-core-peer-v1';
const _deadline = Duration(seconds: 5);
const _usage = lm.LanguageModelUsage(
  inputTokens: lm.InputTokens(total: 1),
  outputTokens: lm.OutputTokens(total: 1),
);

void main() {
  // Compatibility fixture (real-process): P1-CORE-01
  // Compatibility fixture (real-process): P1-CORE-02
  // Compatibility fixture (real-process): P1-CORE-03
  // Compatibility fixture (real-process): P1-CORE-04
  // Compatibility fixture (real-process): P1-CORE-05
  // Compatibility fixture (real-process): P1-CORE-06
  // Compatibility fixture (real-process): P1-CORE-07
  // Compatibility fixture (real-process): P1-CORE-08
  // Compatibility fixture (real-process): P1-CORE-09
  // Compatibility fixture (real-process): P1-CORE-10
  // Compatibility fixture (real-process): P1-CORE-11
  test('public text APIs exchange every core fixture with the fixed peer',
      () async {
    final peer = await _PeerProcess.start();
    final httpClient = HttpClient();
    final model = _PeerBackedModel(
      peer: peer,
      httpClient: httpClient,
      generateTurns: <Map<String, Object?>>[
        <String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'text',
              'text': '{"answer":"stdio"}',
            },
          ],
          'finishReason': 'stop',
          'warnings': <Object?>['temperature'],
          'inputCount': 2,
          'outputCount': 1,
          'responseId': 'stdio-response',
        },
        <String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'tool-call',
              'toolCallId': 'repair-id',
              'toolName': 'missing',
              'input': '{"value":3}',
            },
          ],
          'finishReason': 'tool-calls',
        },
        <String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'tool-call',
              'toolCallId': 'denied-id',
              'toolName': 'delete',
              'input': '{}',
            },
          ],
          'finishReason': 'tool-calls',
        },
        <String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'text',
              'text': '{"result":"blue"}',
            },
          ],
          'finishReason': 'stop',
        },
        <String, Object?>{
          'throw': 'peer generate failure',
        },
      ],
      streamScripts: <List<Object?>>[
        _toolStream(value: 1),
        _toolStream(value: 2),
        <Object?>[
          <String, Object?>{'type': 'stream-start'},
          <String, Object?>{'type': 'text-start', 'id': 'text-final'},
          <String, Object?>{
            'type': 'text-delta',
            'id': 'text-final',
            'delta': '{"answer":"sse"}',
          },
          <String, Object?>{'type': 'text-end', 'id': 'text-final'},
          <String, Object?>{'type': 'finish', 'finishReason': 'stop'},
        ],
        <Object?>[
          <String, Object?>{'type': 'stream-start'},
          <String, Object?>{'type': 'error', 'error': 'peer stream failure'},
        ],
        _delayedTextStream(delayMs: 150),
        _delayedTextStream(delayMs: 150),
      ],
    );

    try {
      final generated = await generateText(
        model: model,
        messages: const <ModelMessage>[
          UserModelMessage(
            <UserContentPart>[TextPart('generate')],
            providerOptions: <String, lm.JsonObject>{
              'openai': <String, Object?>{'message': true},
            },
          ),
        ],
        instructions: 'fixed peer instruction',
        providerOptions: const <String, lm.JsonObject>{
          'openai': <String, Object?>{'request': true},
        },
        output: Output.object(
          schema: const lm.JsonSchema(<String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'answer': <String, Object?>{'type': 'string'},
            },
            'required': <Object?>['answer'],
            'additionalProperties': false,
          }),
        ),
      );
      expect(generated.output, <String, Object?>{'answer': 'stdio'});
      expect(generated.warnings, <lm.Warning>[
        const lm.UnsupportedWarning('temperature'),
      ]);
      expect(generated.usage.inputTokens.total, 2);
      expect(generated.response?.id, 'stdio-response');
      expect(model.receivedOptions.first.prompt.first, isA<lm.SystemMessage>());
      expect(
        (model.receivedOptions.first.prompt.last as lm.UserMessage)
            .providerOptions,
        const <String, lm.JsonObject>{
          'openai': <String, Object?>{'message': true},
        },
      );

      ToolCallRepairFailure? repairFailure;
      final repaired = await generateText(
        model: model,
        prompt: 'repair',
        tools: <String, Tool>{
          'echo': Tool(
            inputSchema: _valueSchema,
            execute: (input, options) =>
                (input as Map<String, Object?>)['value'],
          ),
        },
        repairToolCall: (options) {
          repairFailure = options.error;
          return lm.ToolCall(
            toolCallId: options.toolCall.toolCallId,
            toolName: 'echo',
            input: options.toolCall.input,
          );
        },
      );
      expect(repairFailure, isA<NoSuchToolError>());
      expect(repaired.toolResults.single.result, 3);

      var deleteExecuted = false;
      final denied = await generateText(
        model: model,
        prompt: 'deny',
        tools: <String, Tool>{
          'delete': Tool(
            inputSchema: const lm.JsonSchema(<String, Object?>{
              'type': 'object',
            }),
            execute: (input, options) {
              deleteExecuted = true;
              return 'deleted';
            },
          ),
        },
        toolApproval: const <String, Object?>{
          'delete': ToolApprovalStatus.denied(reason: 'fixed policy'),
        },
      );
      expect(deleteExecuted, isFalse);
      expect(
        denied.finalStep.toolResultOutputs.single,
        const lm.ToolResultExecutionDenied(reason: 'fixed policy'),
      );

      final choice = await generateText(
        model: model,
        prompt: 'choice',
        output: Output.choice(options: const <String>['red', 'blue']),
      );
      expect(choice.output, 'blue');
      await expectLater(
        generateText(model: model, prompt: 'provider error'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'peer generate failure',
          ),
        ),
      );

      final callbackEvents = <String>[];
      final streamed = streamText(
        model: model,
        prompt: 'stream tools',
        tools: <String, Tool>{
          'echo': Tool(
            inputSchema: _valueSchema,
            onInputStart: (options) {
              callbackEvents.add('start:${options.toolCallId}');
            },
            onInputAvailable: (options) {
              callbackEvents.add(
                'available:'
                '${(options.input as Map<String, Object?>)['value']}',
              );
            },
            execute: (input, options) =>
                (input as Map<String, Object?>)['value'],
          ),
        },
        stopWhen: isStepCount(3),
        output: Output.object(
          schema: const lm.JsonSchema(<String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'answer': <String, Object?>{'type': 'string'},
            },
            'required': <Object?>['answer'],
            'additionalProperties': false,
          }),
        ),
      );
      final streamedParts = await streamed.stream.toList();
      expect(await streamed.output, <String, Object?>{'answer': 'sse'});
      expect(await streamed.toolCalls, hasLength(2));
      expect(await streamed.toolResults, hasLength(2));
      expect(
        callbackEvents,
        <String>[
          'start:reused-id',
          'available:1',
          'start:reused-id',
          'available:2',
        ],
      );
      expect(streamedParts.first, isA<StartPart>());
      expect(streamedParts.last, isA<FinishPart>());
      expect(streamedParts.whereType<StartStepPart>(), hasLength(3));
      expect(streamedParts.whereType<FinishStepPart>(), hasLength(3));
      expect(streamedParts.whereType<ToolCallStreamPart>(), hasLength(2));

      final finalStreamPrompt = model.receivedOptions.last.prompt;
      expect(
        finalStreamPrompt
            .whereType<lm.AssistantMessage>()
            .expand((message) => message.content)
            .whereType<lm.ToolCallPart>()
            .map((call) => call.toolCallId),
        <String>['reused-id', 'reused-id'],
      );

      final failed = streamText(model: model, prompt: 'stream error');
      final failedParts = await failed.stream.toList();
      expect(failedParts.last, const ErrorPart('peer stream failure'));
      expect(failedParts.whereType<FinishPart>(), isEmpty);

      final cancellation = lm.CancellationController();
      final aborted = streamText(
        model: model,
        prompt: 'abort',
        cancellation: cancellation.signal,
      );
      await aborted.stream.firstWhere((part) => part is StartStepPart);
      cancellation.cancel('fixed peer abort');
      final abortedParts = await aborted.stream.toList();
      expect(abortedParts.last, const AbortPart(reason: 'fixed peer abort'));
      expect(abortedParts.whereType<ErrorPart>(), isEmpty);

      final timedOut = streamText(
        model: model,
        prompt: 'timeout',
        timeout: const TimeoutConfiguration(
          firstChunk: Duration(milliseconds: 30),
        ),
      );
      final timeoutParts = await timedOut.stream.toList();
      expect(
        timeoutParts.last,
        isA<ErrorPart>().having(
          (part) => part.error,
          'error',
          isA<TimeoutException>(),
        ),
      );

      expect(model.generateCallCount, 5);
      expect(model.streamCallCount, 6);
      await peer.shutdown();
      expect(await peer.process.exitCode.timeout(_deadline), 0);
      expect((await peer.stderrOutput).trim(), isEmpty);
    } finally {
      httpClient.close(force: true);
      await peer.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}

const _valueSchema = lm.JsonSchema(<String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'value': <String, Object?>{'type': 'number'},
  },
  'required': <Object?>['value'],
});

List<Object?> _toolStream({required int value}) {
  return <Object?>[
    <String, Object?>{'type': 'stream-start'},
    <String, Object?>{
      'type': 'tool-input-start',
      'id': 'reused-id',
      'toolName': 'echo',
    },
    <String, Object?>{
      'type': 'tool-input-delta',
      'id': 'reused-id',
      'delta': '{"value":$value}',
    },
    <String, Object?>{'type': 'tool-input-end', 'id': 'reused-id'},
    <String, Object?>{
      'type': 'tool-call',
      'toolCallId': 'reused-id',
      'toolName': 'echo',
      'input': '{"value":$value}',
    },
    <String, Object?>{'type': 'finish', 'finishReason': 'tool-calls'},
  ];
}

List<Object?> _delayedTextStream({required int delayMs}) {
  return <Object?>[
    <String, Object?>{'type': 'stream-start'},
    <String, Object?>{
      'delayMs': delayMs,
      'data': <String, Object?>{'type': 'text-start', 'id': 'delayed'},
    },
    <String, Object?>{
      'type': 'text-delta',
      'id': 'delayed',
      'delta': 'late',
    },
    <String, Object?>{'type': 'text-end', 'id': 'delayed'},
    <String, Object?>{'type': 'finish', 'finishReason': 'stop'},
  ];
}

final class _PeerBackedModel implements lm.LanguageModel {
  _PeerBackedModel({
    required this.peer,
    required this.httpClient,
    required List<Map<String, Object?>> generateTurns,
    required List<List<Object?>> streamScripts,
  })  : _generateTurns = List<Map<String, Object?>>.of(generateTurns),
        _streamScripts = List<List<Object?>>.of(streamScripts);

  final _PeerProcess peer;
  final HttpClient httpClient;
  final List<Map<String, Object?>> _generateTurns;
  final List<List<Object?>> _streamScripts;
  final List<lm.LanguageModelCallOptions> receivedOptions =
      <lm.LanguageModelCallOptions>[];
  var generateCallCount = 0;
  var streamCallCount = 0;

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'fixed-process-peer';

  @override
  String get modelId => 'fixed-process-model';

  @override
  Map<String, List<RegExp>> get supportedUrls => const <String, List<RegExp>>{};

  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) async {
    receivedOptions.add(options);
    final index = generateCallCount++;
    final response = await peer.request(<String, Object?>{
      'id': 'generate-$index',
      'op': 'echo',
      'value': _generateTurns[index],
    });
    final turn = response['value']! as Map<String, Object?>;
    if (turn['throw'] case final String message) {
      throw StateError(message);
    }
    final responseId = turn['responseId'];
    return lm.LanguageModelGenerateResult(
      content: (turn['content']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(_content)
          .toList(growable: false),
      finishReason: _finishReason(turn['finishReason']! as String),
      usage: lm.LanguageModelUsage(
        inputTokens: lm.InputTokens(
          total: turn['inputCount'] as int? ?? 1,
        ),
        outputTokens: lm.OutputTokens(
          total: turn['outputCount'] as int? ?? 1,
        ),
      ),
      warnings: <lm.Warning>[
        for (final warning
            in turn['warnings'] as List<Object?>? ?? const <Object?>[])
          lm.UnsupportedWarning(warning! as String),
      ],
      response: responseId is String
          ? lm.ResponseInfo(id: responseId, modelId: modelId)
          : null,
    );
  }

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async {
    receivedOptions.add(options);
    final index = streamCallCount++;
    final request = await httpClient.postUrl(
      Uri.parse('http://${peer.host}:${peer.port}/sse'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, Object?>{
      'events': _streamScripts[index],
    }));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('peer SSE returned ${response.statusCode}');
    }
    return lm.LanguageModelStreamResult(
      stream: _decodeSse(response),
      request: lm.RequestInfo(body: <String, Object?>{'script': index}),
      response: lm.ResponseInfo(
        id: 'sse-$index',
        modelId: modelId,
        headers: const <String, String>{'x-peer': 'fixed-process'},
      ),
    );
  }

  Stream<lm.LanguageModelStreamPart> _decodeSse(
    HttpClientResponse response,
  ) async* {
    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) {
        continue;
      }
      final event =
          jsonDecode(line.substring('data: '.length)) as Map<String, Object?>;
      yield _streamPart(event);
    }
  }

  lm.LanguageModelContent _content(Map<String, Object?> content) {
    return switch (content['type']) {
      'text' => lm.TextContent(content['text']! as String),
      'tool-call' => lm.ToolCall(
          toolCallId: content['toolCallId']! as String,
          toolName: content['toolName']! as String,
          input: content['input']! as String,
        ),
      _ => throw StateError('unknown peer content ${content['type']}'),
    };
  }

  lm.LanguageModelStreamPart _streamPart(Map<String, Object?> event) {
    return switch (event['type']) {
      'stream-start' => const lm.StreamStart(<lm.Warning>[]),
      'text-start' => lm.TextStart(event['id']! as String),
      'text-delta' => lm.TextDelta(
          event['id']! as String,
          event['delta']! as String,
        ),
      'text-end' => lm.TextEnd(event['id']! as String),
      'tool-input-start' => lm.ToolInputStart(
          id: event['id']! as String,
          toolName: event['toolName']! as String,
        ),
      'tool-input-delta' => lm.ToolInputDelta(
          event['id']! as String,
          event['delta']! as String,
        ),
      'tool-input-end' => lm.ToolInputEnd(event['id']! as String),
      'tool-call' => lm.ToolCall(
          toolCallId: event['toolCallId']! as String,
          toolName: event['toolName']! as String,
          input: event['input']! as String,
        ),
      'finish' => lm.FinishPart(
          usage: _usage,
          finishReason: _finishReason(event['finishReason']! as String),
        ),
      'error' => lm.ErrorPart(event['error']),
      _ => throw StateError('unknown peer stream part ${event['type']}'),
    };
  }

  lm.LanguageModelFinishReason _finishReason(String value) {
    return lm.LanguageModelFinishReason(switch (value) {
      'stop' => lm.FinishReasonType.stop,
      'tool-calls' => lm.FinishReasonType.toolCalls,
      _ => lm.FinishReasonType.other,
    });
  }
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
      await process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
    }
  }
}
