import 'dart:async';
import 'dart:typed_data';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

import '../support/scripted_model.dart';
import '../support/scripted_service_provider.dart';

const _usage = contracts.LanguageModelUsage(
  inputTokens: contracts.InputTokens(total: 1),
  outputTokens: contracts.OutputTokens(total: 1),
);

void main() {
  // Compatibility fixture (scripted-peer): P1-CORE-12
  // Compatibility fixture (scripted-peer): P1-CORE-13
  // Compatibility fixture (scripted-peer): P1-CORE-14
  // Compatibility fixture (scripted-peer): P1-CORE-15
  // Compatibility fixture (scripted-peer): P1-CORE-16
  test('middleware ordering, settings merge and metadata remain public',
      () async {
    final order = <String>[];
    final model = ScriptedModel(
      turns: const <ScriptedTurn>[
        ScriptedTurn(
          content: <contracts.LanguageModelContent>[
            contracts.TextContent('middleware-ok'),
          ],
          finishReason: contracts.LanguageModelFinishReason(
            contracts.FinishReasonType.stop,
          ),
          usage: _usage,
          providerMetadata: <String, contracts.JsonObject>{
            'scripted': <String, Object?>{'trace': 'preserved'},
          },
        ),
      ],
    );
    final inner = wrapLanguageModel(
      model,
      contracts.LanguageModelMiddleware(
        transformParams: ({
          required bool stream,
          required contracts.LanguageModelCallOptions params,
          required contracts.LanguageModel model,
        }) async {
          order.add('inner-transform');
          return params;
        },
        wrapGenerate: ({
          required contracts.LanguageModelDoGenerate doGenerate,
          required contracts.LanguageModelDoStream doStream,
          required contracts.LanguageModelCallOptions params,
          required contracts.LanguageModel model,
        }) async {
          order.add('inner-before');
          final result = await doGenerate();
          order.add('inner-after');
          return result;
        },
      ),
    );
    final withDefaults = wrapLanguageModel(
      inner,
      defaultSettingsMiddleware(
        settings: const DefaultLanguageModelSettings(
          temperature: 0.2,
          headers: <String, String>{
            'x-default': 'yes',
            'x-shared': 'default',
          },
          providerOptions: <String, contracts.JsonObject>{
            'scripted': <String, Object?>{
              'nested': <String, Object?>{
                'default': true,
                'shared': 'default',
              },
            },
          },
        ),
      ),
    );
    final outer = wrapLanguageModel(
      withDefaults,
      contracts.LanguageModelMiddleware(
        transformParams: ({
          required bool stream,
          required contracts.LanguageModelCallOptions params,
          required contracts.LanguageModel model,
        }) async {
          order.add('outer-transform');
          return params;
        },
        wrapGenerate: ({
          required contracts.LanguageModelDoGenerate doGenerate,
          required contracts.LanguageModelDoStream doStream,
          required contracts.LanguageModelCallOptions params,
          required contracts.LanguageModel model,
        }) async {
          order.add('outer-before');
          final result = await doGenerate();
          order.add('outer-after');
          return result;
        },
      ),
    );

    final result = await generateText(
      model: outer,
      prompt: 'middleware',
      headers: const <String, String>{
        'x-shared': 'call',
        'x-call': 'yes',
      },
      providerOptions: const <String, contracts.JsonObject>{
        'scripted': <String, Object?>{
          'nested': <String, Object?>{
            'shared': 'call',
            'call': true,
          },
        },
      },
    );

    expect(order, <String>[
      'outer-transform',
      'outer-before',
      'inner-transform',
      'inner-before',
      'inner-after',
      'outer-after',
    ]);
    expect(model.receivedCallOptions.single.temperature, 0.2);
    expect(model.receivedCallOptions.single.headers, <String, String>{
      'x-default': 'yes',
      'x-shared': 'call',
      'x-call': 'yes',
    });
    expect(
      model.receivedCallOptions.single.providerOptions,
      const <String, contracts.JsonObject>{
        'scripted': <String, Object?>{
          'nested': <String, Object?>{
            'default': true,
            'shared': 'call',
            'call': true,
          },
        },
      },
    );
    expect(
      result.finalStep.providerMetadata,
      const <String, contracts.JsonObject>{
        'scripted': <String, Object?>{'trace': 'preserved'},
      },
    );
  });

  test('telemetry is opt-in, redacted and terminal events are exclusive',
      () async {
    final success = _RecordingTelemetry();
    final model = ScriptedModel(
      turns: const <ScriptedTurn>[
        ScriptedTurn(
          content: <contracts.LanguageModelContent>[
            contracts.ToolCall(
              toolCallId: 'call-1',
              toolName: 'echo',
              input: '{"secret":"input"}',
            ),
          ],
          finishReason: contracts.LanguageModelFinishReason(
            contracts.FinishReasonType.toolCalls,
          ),
          usage: _usage,
        ),
        ScriptedTurn(
          content: <contracts.LanguageModelContent>[
            contracts.TextContent('secret output'),
          ],
          finishReason: contracts.LanguageModelFinishReason(
            contracts.FinishReasonType.stop,
          ),
          usage: _usage,
        ),
      ],
    );
    await generateText(
      model: model,
      prompt: 'secret prompt',
      tools: <String, Tool>{
        'echo': Tool(
          inputSchema: const contracts.JsonSchema(<String, Object?>{
            'type': 'object',
          }),
          execute: (input, options) => 'secret tool output',
        ),
      },
      stopWhen: isStepCount(2),
      telemetry: TelemetrySettings(
        recordInputs: false,
        recordOutputs: false,
        integrations: <Telemetry>[success],
      ),
    );

    expect(success.events, <String>[
      'start',
      'step-start',
      'model-start',
      'model-end',
      'tool-start',
      'tool-end',
      'step-end',
      'step-start',
      'model-start',
      'model-end',
      'step-end',
      'end',
    ]);
    expect(success.modelStarts, everyElement(isEmpty));
    expect(success.modelEnds, everyElement(isEmpty));
    expect(success.end!.steps, hasLength(2));
    expect(
        success.end!.steps,
        everyElement(
          isA<StepResult>().having((step) => step.content, 'content', isEmpty),
        ));

    final failed = _RecordingTelemetry();
    await streamText(
      model: ErrorStreamModel(),
      prompt: 'error',
      telemetry: TelemetrySettings(integrations: <Telemetry>[failed]),
    ).consumeStream();
    expect(failed.events.where((event) => event == 'error'), hasLength(1));
    expect(failed.events, isNot(contains('end')));
    expect(failed.events, isNot(contains('abort')));

    final aborted = _RecordingTelemetry();
    final cancellation = contracts.CancellationController()
      ..cancel('scripted abort');
    await streamText(
      model: ScriptedModel(
        turns: const <ScriptedTurn>[
          ScriptedTurn(
            content: <contracts.LanguageModelContent>[
              contracts.TextContent('unused'),
            ],
            finishReason: contracts.LanguageModelFinishReason(
              contracts.FinishReasonType.stop,
            ),
            usage: _usage,
          ),
        ],
      ),
      prompt: 'abort',
      cancellation: cancellation.signal,
      telemetry: TelemetrySettings(integrations: <Telemetry>[aborted]),
    ).consumeStream();
    expect(aborted.events.where((event) => event == 'abort'), hasLength(1));
    expect(aborted.abort!.reason, 'scripted abort');
    expect(aborted.events, isNot(contains('end')));
    expect(aborted.events, isNot(contains('error')));
  });

  test('service helpers aggregate usage, warnings, metadata and errors',
      () async {
    final peer = ScriptedServiceProvider();
    final singleEmbedding = await embed(
      model: peer.embedding,
      value: 'one',
    );
    final embeddings = await embedMany(
      model: peer.embedding,
      values: const <String>['two', 'three'],
    );
    final ranking = await rerank<String>(
      model: peer.reranking,
      documents: const <String>['first', 'second'],
      query: 'query',
    );
    final images = await generateImage(
      model: peer.image,
      prompt: 'image',
      n: 2,
    );
    final videos = await generateVideo(
      model: peer.video,
      prompt: 'video',
      n: 2,
    );
    final speech = await generateSpeech(
      model: peer.speech,
      text: 'speak',
    );
    final transcript = await transcribe(
      model: peer.transcription,
      audio: DataBytes(Uint8List.fromList(<int>[1, 2, 3])),
      mediaType: 'audio/wav',
    );

    expect(singleEmbedding.embedding, <double>[3, 1]);
    expect(embeddings.embeddings, <List<double>>[
      <double>[3, 2],
      <double>[5, 3],
    ]);
    expect(embeddings.usage.tokens, 2);
    expect(embeddings.warnings, hasLength(2));
    expect(ranking.rerankedDocuments, <String>['second', 'first']);
    expect(images.images, hasLength(2));
    expect(images.warnings, hasLength(2));
    expect(
      images.usage,
      const contracts.ImageModelUsage(
        inputTokens: 3,
        outputTokens: 6,
        totalTokens: 9,
      ),
    );
    expect(videos.videos, hasLength(2));
    expect(videos.warnings, hasLength(2));
    expect(speech.audio, Uint8List.fromList(<int>[1, 2, 3]));
    expect(speech.warnings, hasLength(1));
    expect(transcript.text, 'scripted transcript');
    expect(transcript.warnings, hasLength(1));

    await expectLater(
      generateImage(model: _EmptyImageModel(), prompt: 'empty'),
      throwsA(isA<contracts.NoImageGeneratedError>()),
    );
  });

  test('UI and text stream conversion preserves data and terminal semantics',
      () async {
    final parsed = UiMessageChunk.fromJson(const <String, Object?>{
      'type': 'data-future-widget',
      'id': 'widget-1',
      'data': <String, Object?>{'state': 'ready'},
    });
    final dataCalls = <DataUiMessageChunk>[];
    final messages = await readUiMessageStream(
      stream: Stream<UiMessageChunk>.fromIterable(<UiMessageChunk>[
        DataUiMessageChunk(
          type: 'data-future-widget',
          data: 'transient',
          transient: true,
        ),
        parsed,
        AbortUiMessageChunk(reason: 'user'),
        FinishUiMessageChunk(),
      ]),
      onData: dataCalls.add,
    ).toList();

    expect(parsed, isA<DataUiMessageChunk>());
    expect(dataCalls, hasLength(2));
    expect(messages.last.parts, const <UiMessagePart>[
      DataUiPart(
        type: 'data-future-widget',
        id: 'widget-1',
        data: <String, Object?>{'state': 'ready'},
      ),
    ]);
    expect(
      toUiMessageChunk(const ErrorPart('internal')),
      ErrorUiMessageChunk('An error occurred.'),
    );
    expect(
      toUiMessageChunk(const AbortPart(reason: 'user')),
      AbortUiMessageChunk(reason: 'user'),
    );
    expect(
      toUiMessageChunk(const FinishPart(
        finishReason: contracts.LanguageModelFinishReason(
          contracts.FinishReasonType.stop,
        ),
        totalUsage: _usage,
      )),
      FinishUiMessageChunk(
        finishReason: contracts.LanguageModelFinishReason(
          contracts.FinishReasonType.stop,
        ),
      ),
    );
    expect(
      await toTextStream(Stream<TextStreamPart>.fromIterable(
        const <TextStreamPart>[
          TextDeltaPart('text-1', 'hello'),
          AbortPart(reason: 'ignored by plain text'),
          ErrorPart('ignored by plain text'),
        ],
      )).toList(),
      <String>['hello'],
    );
  });

  test('file, skill and registry helpers preserve options and typed errors',
      () async {
    final peer = ScriptedServiceProvider();
    final registry = createProviderRegistry(
      <String, contracts.Provider>{'peer': peer},
    );
    final file = await uploadFile(
      api: registry.files('peer'),
      data: const contracts.FileDataText('fixture'),
      filename: 'fixture.txt',
      providerOptions: const <String, contracts.JsonObject>{
        'scripted': <String, Object?>{'purpose': 'compatibility'},
      },
    );
    final skill = await uploadSkill(
      api: registry.skills('peer'),
      files: const <contracts.SkillFile>[
        contracts.SkillFile(
          path: 'SKILL.md',
          data: contracts.FileDataText('# Fixture'),
        ),
      ],
      displayTitle: 'Fixture Skill',
      providerOptions: const <String, contracts.JsonObject>{
        'scripted': <String, Object?>{'version': 1},
      },
    );

    expect(file.providerReference, const <String, String>{
      'scripted': 'file-1',
    });
    expect(peer.fileApi.calls.single.mediaType, 'text/plain');
    expect(
      peer.fileApi.calls.single.providerOptions,
      const <String, contracts.JsonObject>{
        'scripted': <String, Object?>{'purpose': 'compatibility'},
      },
    );
    expect(skill.latestVersion, 'v1');
    expect(
      peer.skillApi.calls.single.providerOptions,
      const <String, contracts.JsonObject>{
        'scripted': <String, Object?>{'version': 1},
      },
    );
    expect(
      () => registry.embeddingModel('missing:model'),
      throwsA(
        isA<contracts.NoSuchProviderError>().having(
          (error) => error.providerId,
          'providerId',
          'missing',
        ),
      ),
    );
  });
}

final class _RecordingTelemetry with Telemetry {
  final List<String> events = <String>[];
  final List<List<ModelMessage>> modelStarts = <List<ModelMessage>>[];
  final List<List<contracts.LanguageModelContent>> modelEnds =
      <List<contracts.LanguageModelContent>>[];
  GenerateTextEndEvent? end;
  GenerateTextAbortEvent? abort;

  @override
  void onStart(GenerateTextStartEvent e, TelemetryMetadata m) {
    events.add('start');
  }

  @override
  void onStepStart(GenerateTextStepStartEvent e, TelemetryMetadata m) {
    events.add('step-start');
  }

  @override
  void onLanguageModelCallStart(
    LanguageModelCallStartEvent e,
    TelemetryMetadata m,
  ) {
    events.add('model-start');
    modelStarts.add(e.messages);
  }

  @override
  void onLanguageModelCallEnd(
    LanguageModelCallEndEvent e,
    TelemetryMetadata m,
  ) {
    events.add('model-end');
    modelEnds.add(e.content);
  }

  @override
  void onToolExecutionStart(
    ToolExecutionStartEvent e,
    TelemetryMetadata m,
  ) {
    events.add('tool-start');
  }

  @override
  void onToolExecutionEnd(
    ToolExecutionEndEvent e,
    TelemetryMetadata m,
  ) {
    events.add('tool-end');
  }

  @override
  void onStepEnd(StepResult step, TelemetryMetadata m) {
    events.add('step-end');
  }

  @override
  void onEnd(GenerateTextEndEvent e, TelemetryMetadata m) {
    events.add('end');
    end = e;
  }

  @override
  void onAbort(GenerateTextAbortEvent e, TelemetryMetadata m) {
    events.add('abort');
    abort = e;
  }

  @override
  void onError(Object? error, TelemetryMetadata m) {
    events.add('error');
  }
}

final class _EmptyImageModel implements contracts.ImageModel {
  @override
  String get specificationVersion => contracts.imageModelSpecVersion;

  @override
  String get provider => 'scripted.services.empty-image';

  @override
  String get modelId => 'empty-image';

  @override
  int? get maxImagesPerCall => 1;

  @override
  Future<contracts.ImageModelResult> doGenerate(
    contracts.ImageModelCallOptions options,
  ) async =>
      const contracts.ImageModelResult(
        images: <Uint8List>[],
        warnings: <contracts.Warning>[],
      );
}
