// Compatibility fixture (unit): P1-CROSS-01
// Compatibility fixture (unit): P1-CROSS-02
import 'dart:typed_data';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:test/test.dart';

/// 仅经 barrel 类型定义的 telemetry 集成,验证 `Telemetry` mixin 经 barrel 可用。
final class _BarrelTelemetry with Telemetry {}

/// 仅经 barrel 类型实现的 echo embedding 模型:每个值映射为
/// `[值长度]` 的单元素向量,供 barrel 自足性断言使用。
final class _EchoEmbeddingModel implements EmbeddingModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.embedding';
  @override
  String get modelId => 'echo-embedding';
  @override
  int? get maxEmbeddingsPerCall => null;
  @override
  bool get supportsParallelCalls => true;

  @override
  Future<EmbeddingModelResult> doEmbed(
    EmbeddingModelCallOptions options,
  ) async {
    return EmbeddingModelResult(
      embeddings: [
        for (final value in options.values) [value.length.toDouble()],
      ],
      usage: const EmbeddingUsage(tokens: 3),
      warnings: const [],
      response: const EmbeddingResponseInfo(headers: {'x-echo': 'y'}),
    );
  }
}

/// 仅经 barrel 类型实现的 echo transcription 模型。
final class _EchoTranscriptionModel implements StreamableTranscriptionModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.transcription';

  @override
  String get modelId => 'echo-transcription';

  @override
  Future<TranscriptionModelResult> doGenerate(
    TranscriptionModelCallOptions options,
  ) async {
    return const TranscriptionModelResult(
      text: 'transcript-ok',
      segments: [
        TranscriptionSegment(
          text: 'transcript-ok',
          startSecond: 0,
          endSecond: 1,
        ),
      ],
      language: 'en',
      durationInSeconds: 1,
      warnings: [],
      response: ResponseInfo(modelId: 'echo-transcription'),
    );
  }

  @override
  Future<TranscriptionModelStreamResult> doStream(
    TranscriptionModelStreamOptions options,
  ) async {
    return TranscriptionModelStreamResult(
      stream: Stream<TranscriptionModelStreamPart>.fromIterable(
        const [
          TranscriptionStreamStart([]),
          TranscriptionDelta(delta: 'stream-'),
          TranscriptionFinal(text: 'stream-ok', startSecond: 0, endSecond: 1),
          TranscriptionFinish(
            text: 'stream-ok',
            segments: [
              TranscriptionSegment(
                text: 'stream-ok',
                startSecond: 0,
                endSecond: 1,
              ),
            ],
            language: 'en',
            durationInSeconds: 1,
          ),
        ],
      ),
      response: const ResponseInfo(modelId: 'echo-transcription-stream'),
    );
  }
}

/// 仅经 barrel 类型实现的 echo speech 模型。
final class _EchoSpeechModel implements SpeechModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.speech';

  @override
  String get modelId => 'echo-speech';

  @override
  Future<SpeechModelResult> doGenerate(
    SpeechModelCallOptions options,
  ) async {
    return SpeechModelResult(
      audio: Uint8List.fromList([1, 2, 3]),
      warnings: const [],
      response: const ResponseInfo(
        modelId: 'echo-speech',
        headers: {'content-type': 'audio/mp3'},
      ),
    );
  }
}

/// 仅经 barrel 类型实现的 echo reranking 模型。
final class _EchoRerankingModel implements RerankingModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.reranking';

  @override
  String get modelId => 'echo-reranking';

  @override
  Future<RerankingModelResult> doRerank(
    RerankingModelCallOptions options,
  ) async {
    return const RerankingModelResult(
      ranking: [
        RerankingModelRanking(index: 1, relevanceScore: 0.8),
        RerankingModelRanking(index: 0, relevanceScore: 0.2),
      ],
      warnings: [],
      response: ResponseInfo(modelId: 'echo-reranking'),
    );
  }
}

/// 仅经 barrel 类型实现的 echo image 模型。
final class _EchoImageModel implements ImageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.image';

  @override
  String get modelId => 'echo-image';

  @override
  int? get maxImagesPerCall => null;

  @override
  Future<ImageModelResult> doGenerate(
    ImageModelCallOptions options,
  ) async {
    return ImageModelResult(
      images: [
        Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
      ],
      warnings: const [],
      response: const ResponseInfo(modelId: 'echo-image'),
    );
  }
}

/// 仅经 barrel 类型实现的 echo video 模型。
final class _EchoVideoModel implements VideoModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.video';

  @override
  String get modelId => 'echo-video';

  @override
  int? get maxVideosPerCall => null;

  @override
  Future<VideoModelResult> doGenerate(
    VideoModelCallOptions options,
  ) async {
    return VideoModelResult(
      videos: [
        VideoModelVideoDataBytes(
          Uint8List.fromList([
            0,
            0,
            0,
            0,
            0x66,
            0x74,
            0x79,
            0x70,
          ]),
        ),
      ],
      warnings: const [],
      response: const ResponseInfo(modelId: 'echo-video'),
    );
  }
}

final class _EchoFiles implements Files {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.files';

  @override
  Future<FilesUploadResult> uploadFile(FilesUploadOptions options) async {
    return FilesUploadResult(
      providerReference: const {'test': 'file-1'},
      mediaType: options.mediaType,
      filename: options.filename,
      warnings: const [],
    );
  }
}

final class _EchoSkills implements Skills {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.skills';

  @override
  Future<SkillsUploadResult> uploadSkill(SkillsUploadOptions options) async {
    return SkillsUploadResult(
      providerReference: const {'test': 'skill-1'},
      displayTitle: options.displayTitle,
      name: 'echo-skill',
      warnings: const [],
    );
  }
}

final class _EchoLanguageModel implements LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test';
  @override
  String get modelId => 'echo';
  @override
  Map<String, List<RegExp>> get supportedUrls => const {};

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) async {
    return LanguageModelGenerateResult(
      content: const [TextContent('barrel-ok')],
      finishReason: const LanguageModelFinishReason(FinishReasonType.stop),
      usage: const LanguageModelUsage(
        inputTokens: InputTokens(total: 1),
        outputTokens: OutputTokens(total: 1),
      ),
      warnings: const [],
    );
  }

  @override
  Future<LanguageModelStreamResult> doStream(
    LanguageModelCallOptions options,
  ) async {
    return LanguageModelStreamResult(
      stream: Stream.fromIterable(const <LanguageModelStreamPart>[
        StreamStart([]),
        TextStart('1'),
        TextDelta('1', 'barrel-ok'),
        TextEnd('1'),
      ]),
    );
  }
}

final class _EchoProvider implements Provider {
  const _EchoProvider();

  @override
  String get specificationVersion => 'v4';

  @override
  LanguageModel languageModel(String modelId) => _EchoLanguageModel();

  @override
  EmbeddingModel embeddingModel(String modelId) => _EchoEmbeddingModel();

  @override
  ImageModel imageModel(String modelId) => _EchoImageModel();

  @override
  VideoModel videoModel(String modelId) => _EchoVideoModel();

  @override
  TranscriptionModel transcriptionModel(String modelId) =>
      _EchoTranscriptionModel();

  @override
  SpeechModel speechModel(String modelId) => _EchoSpeechModel();

  @override
  RerankingModel rerankingModel(String modelId) => _EchoRerankingModel();

  @override
  Files files() => _EchoFiles();

  @override
  Skills skills() => _EchoSkills();
}

void main() {
  test('barrel re-exports typed provider metadata', () {
    const ProviderMetadata metadata = <String, JsonObject>{
      'portable': <String, Object?>{'traceId': 'ai'},
    };
    const Headers headers = <String, String>{'x-trace-id': 'ai'};
    expect(metadata['portable']?['traceId'], 'ai');
    expect(headers['x-trace-id'], 'ai');
  });

  test('barrel exposes telemetry surface', () {
    final integration = _BarrelTelemetry();
    expect(integration, isA<Telemetry>());

    const meta = TelemetryMetadata(functionId: 'f');
    expect(meta.recordInputs, isTrue);
    expect(meta.recordOutputs, isTrue);

    const settings = TelemetrySettings(functionId: 'f', recordInputs: false);
    expect(settings.functionId, 'f');

    registerTelemetry([integration]);
    expect(globalTelemetryIntegrations(), contains(integration));
    clearTelemetryIntegrations();
    expect(globalTelemetryIntegrations(), isEmpty);

    const toolStart = ToolExecutionStartEvent(
      callId: 'c',
      toolCallId: 't',
      toolName: 'x',
      input: null,
      toolContext: null,
    );
    expect(toolStart.toolName, 'x');
    const success = ToolExecutionEndSuccess(
      callId: 'c',
      toolCallId: 't',
      toolName: 'x',
      output: null,
      toolExecutionMs: 1,
    );
    expect(success, isA<ToolExecutionEndEvent>());

    // 事件类型经 barrel 可见(编译期):
    LanguageModelCallStartEvent? lmStart;
    LanguageModelCallEndEvent? lmEnd;
    ToolExecutionEndError? toolErr;
    expect([lmStart, lmEnd, toolErr], everyElement(isNull));
  });

  test('barrel exposes message/tool/core/stream/entry-point/middleware surface',
      () async {
    // 消息层:content part + Prompt。
    const part = TextPart('hi');
    const prompt = Prompt(prompt: 'hello');
    expect(part.text, 'hi');
    expect(prompt.prompt, 'hello');

    // 工具系统。
    final echoTool = tool(
      Tool(
        inputSchema: const JsonSchema(<String, Object?>{'type': 'object'}),
        execute: (input, options) async => 'ok',
      ),
    );
    expect(echoTool, isA<Tool>());

    // 循环引擎:stopWhen 工厂。
    final stop = isStepCount(1);
    expect(await stop(const <StepResult>[]), isFalse);
    final ActiveTools activeTools = ['echo'];
    final ToolOrder toolOrder = ['echo'];
    const RuntimeContext runtimeContext = {'requestId': 'barrel'};
    const ToolsContext toolsContext = {
      'echo': {'tenant': 'demo'},
    };
    final prepareStepResult = PrepareStepResult(
      activeTools: activeTools,
      toolOrder: toolOrder,
      messages: <ModelMessage>[UserModelMessage.text('override')],
    );
    PrepareStepResult prepareStep(PrepareStepOptions options) {
      final List<ModelMessage> messages = options.messages;
      final List<ModelMessage> initialMessages = options.initialMessages;
      final List<ModelMessage> responseMessages = options.responseMessages;
      expect(messages, isNotEmpty);
      expect(initialMessages, isNotEmpty);
      expect(responseMessages, isEmpty);
      expect(options.runtimeContext, runtimeContext);
      expect(options.toolsContext, toolsContext);
      return prepareStepResult;
    }

    expect(prepareStepResult.activeTools, ['echo']);
    expect(prepareStepResult.toolOrder, ['echo']);
    expect(prepareStep, isA<PrepareStepFunction>());
    const approvalStatus = ToolApprovalStatus.userApproval;
    expect(approvalStatus.type, ToolApprovalStatusType.userApproval);
    ToolCall? repairToolCall(ToolCallRepairOptions options) => null;
    expect(repairToolCall, isA<ToolCallRepairFunction>());
    expect(
      NoSuchToolError(toolName: 'missing', availableTools: ['echo']),
      isA<ToolCallRepairFailure>(),
    );

    // 中间件:wrapLanguageModel / wrapEmbeddingModel / wrapProvider。
    final LanguageModel base = _EchoLanguageModel();
    final wrapped = wrapLanguageModel(
      base,
      const LanguageModelMiddleware(),
    );
    expect(wrapped, isA<LanguageModel>());
    final wrappedEmbedding = wrapEmbeddingModel(
      _EchoEmbeddingModel(),
      const EmbeddingModelMiddleware(),
    );
    expect(wrappedEmbedding, isA<EmbeddingModel>());
    final wrappedImage = wrapImageModel(
      _EchoImageModel(),
      const ImageModelMiddleware(),
    );
    expect(wrappedImage, isA<ImageModel>());
    final imageMiddleware = ImageModelMiddleware(
      wrapGenerate: ({
        required ImageModelDoGenerate doGenerate,
        required ImageModelCallOptions params,
        required ImageModel model,
      }) =>
          doGenerate(),
    );
    expect(imageMiddleware.wrapGenerate, isNotNull);
    final wrappedProvider = wrapProvider(provider: const _EchoProvider());
    expect(wrappedProvider.languageModel('echo'), isA<LanguageModel>());
    expect(wrappedProvider.embeddingModel('echo'), isA<EmbeddingModel>());
    expect(wrappedProvider.imageModel('echo'), isA<ImageModel>());
    expect(wrappedProvider.videoModel('echo'), isA<VideoModel>());
    expect(
      wrappedProvider.transcriptionModel('echo'),
      isA<TranscriptionModel>(),
    );
    expect(wrappedProvider.speechModel('echo'), isA<SpeechModel>());
    expect(wrappedProvider.rerankingModel('echo'), isA<RerankingModel>());
    expect(wrappedProvider.files(), isA<Files>());
    expect(wrappedProvider.skills(), isA<Skills>());
    final custom = customProvider(
      languageModels: {'echo': _EchoLanguageModel()},
      videoModels: {'video': _EchoVideoModel()},
    );
    expect(custom.languageModel('echo'), isA<LanguageModel>());
    expect(custom.videoModel('video'), isA<VideoModel>());
    final registry = createProviderRegistry({'echo': custom});
    expect(registry, isA<ProviderRegistry>());
    expect(registry.languageModel('echo:echo'), isA<LanguageModel>());
    expect(registry.videoModel('echo:video'), isA<VideoModel>());
    expect(
      defaultSettingsMiddleware(
        settings: const DefaultLanguageModelSettings(temperature: 0.1),
      ),
      isA<LanguageModelMiddleware>(),
    );
    expect(
      defaultEmbeddingSettingsMiddleware(
        settings: const DefaultEmbeddingModelSettings(headers: {'x': 'y'}),
      ),
      isA<EmbeddingModelMiddleware>(),
    );
    expect(
      addToolInputExamplesMiddleware(),
      isA<LanguageModelMiddleware>(),
    );
    expect(
      extractJsonMiddleware(),
      isA<LanguageModelMiddleware>(),
    );
    expect(
      extractReasoningMiddleware(tagName: 'think'),
      isA<LanguageModelMiddleware>(),
    );
    expect(
      simulateStreamingMiddleware(),
      isA<LanguageModelMiddleware>(),
    );

    // generateText 入口 + StepResult。
    final generated = await generateText(
      model: wrapped,
      prompt: 'hello',
      activeTools: activeTools,
      toolOrder: toolOrder,
      prepareStep: prepareStep,
      runtimeContext: runtimeContext,
      toolsContext: toolsContext,
    );
    expect(generated.text, 'barrel-ok');
    expect(generated.steps.single, isA<StepResult>());
    expect(generated.finalStep.runtimeContext, runtimeContext);
    expect(generated.finalStep.toolsContext, toolsContext);
    final agent = ToolLoopAgent(model: wrapped);
    expect(agent, isA<Agent<dynamic, dynamic, dynamic>>());
    expect(agent.version, 'agent-v1');
    expect((await agent.generate(prompt: 'hello')).text, 'barrel-ok');

    // 生命周期回调事件类型。
    final startEvent = GenerateTextStartEvent(
      model: wrapped,
      messages: <ModelMessage>[UserModelMessage.text('hello')],
    );
    final stepStartEvent = GenerateTextStepStartEvent(
      stepNumber: 0,
      model: wrapped,
      messages: startEvent.messages,
      steps: const <StepResult>[],
    );
    final endEvent = GenerateTextEndEvent(steps: generated.steps);
    void onStart(GenerateTextStartEvent event) {
      expect(event.messages, startEvent.messages);
    }

    void onStepStart(GenerateTextStepStartEvent event) {
      expect(event.stepNumber, stepStartEvent.stepNumber);
    }

    void onEnd(GenerateTextEndEvent event) {
      expect(event.text, endEvent.text);
    }

    final GenerateTextOnStartCallback startCallback = onStart;
    final GenerateTextOnStepStartCallback stepStartCallback = onStepStart;
    final GenerateTextOnEndCallback endCallback = onEnd;
    startCallback(startEvent);
    stepStartCallback(stepStartEvent);
    endCallback(endEvent);
    expect(endEvent.content, hasLength(1));

    final derivedStep = StepResult(
      content: const [
        ReasoningContent('think'),
        ReasoningFileContent(
          data: FileDataBase64('eyJrIjoidiJ9'),
          mediaType: 'application/json',
        ),
        FileContent(data: FileDataBase64('AAA='), mediaType: 'image/png'),
        SourceContent.url(
          id: 'source-1',
          url: 'https://example.com/a',
          title: 'Example',
        ),
      ],
      finishReason: const LanguageModelFinishReason(FinishReasonType.stop),
      usage: const LanguageModelUsage(
        inputTokens: InputTokens(total: 1),
        outputTokens: OutputTokens(total: 1),
      ),
      response: null,
      executedToolResults: const [],
      performance: StepResultPerformance.empty(),
    );
    final List<LanguageModelContent> reasoning = derivedStep.reasoning;
    final List<FileContent> files = derivedStep.files;
    final List<SourceContent> sources = derivedStep.sources;
    expect(reasoning, hasLength(2));
    expect(derivedStep.reasoningText, 'think');
    expect(files.single.mediaType, 'image/png');
    expect(sources.single.sourceType, SourceType.url);

    // uploadFile / uploadSkill 入口 + contract resource types。
    final uploadedFile = await uploadFile(
      api: const _EchoProvider(),
      data: const FileDataText('hello'),
      filename: 'note.txt',
    );
    expect(uploadedFile, isA<UploadFileResult>());
    expect(uploadedFile.providerReference, {'test': 'file-1'});
    expect(uploadedFile.mediaType, 'text/plain');
    final uploadedSkill = await uploadSkill(
      api: const _EchoProvider(),
      files: const [
        SkillFile(path: 'SKILL.md', data: FileDataText('# Demo')),
      ],
      displayTitle: 'Demo skill',
    );
    expect(uploadedSkill, isA<UploadSkillResult>());
    expect(uploadedSkill.providerReference, {'test': 'skill-1'});
    expect(uploadedSkill.displayTitle, 'Demo skill');

    // streamText 入口 + TextStreamPart。
    final streamed = streamText(model: wrapped, prompt: 'hello');
    final parts = await streamed.stream.toList();
    expect(parts, isNotEmpty);
    expect(parts.first, isA<TextStreamPart>());
    expect(
      ToolApprovalRequestStreamPart(
        const ToolApprovalRequest(approvalId: 'a1', toolCallId: 'c1'),
      ),
      isA<TextStreamPart>(),
    );
    expect(const ReasoningStartPart('r1'), isA<TextStreamPart>());
    expect(const ReasoningDeltaPart('r1', 'think'), isA<TextStreamPart>());
    expect(const ReasoningEndPart('r1'), isA<TextStreamPart>());
    expect(await streamed.text, 'barrel-ok');

    // UI message public API surface.
    final uiMessage = UiMessage(
      id: 'ui-1',
      role: UiMessageRole.assistant,
      parts: const [TextUiPart('hello')],
    );
    expect(uiMessage.parts.single, isA<TextUiPart>());
    expect(
      UiMessageChunk.fromJson(
        TextDeltaUiMessageChunk('txt_1', 'hi').toJson(),
      ),
      TextDeltaUiMessageChunk('txt_1', 'hi'),
    );
    expect(
      toUiMessageChunk(const TextDeltaPart('txt_1', 'hi')),
      TextDeltaUiMessageChunk('txt_1', 'hi'),
    );
    expect(
      await toUiMessageStream(
        Stream<TextStreamPart>.fromIterable(const [
          TextDeltaPart('txt_1', 'hi'),
        ]),
      ).toList(),
      [TextDeltaUiMessageChunk('txt_1', 'hi')],
    );
    expect(
      await toTextStream(
        Stream<TextStreamPart>.fromIterable(const [
          TextStartPart('txt_1'),
          TextDeltaPart('txt_1', 'hi'),
          TextEndPart('txt_1'),
        ]),
      ).toList(),
      ['hi'],
    );
    expect(
      await toUiMessageSseStream(
        Stream<UiMessageChunk>.fromIterable([
          TextDeltaUiMessageChunk('txt_1', 'hi'),
        ]),
        sendDone: false,
      ).toList(),
      ['data: {"type":"text-delta","id":"txt_1","delta":"hi"}\n\n'],
    );
    expect(
      convertToModelMessages([
        UiMessage(
          id: 'u1',
          role: UiMessageRole.user,
          parts: const [TextUiPart('hello')],
        ),
      ]).single,
      UserModelMessage.text('hello'),
    );
    expect(
      await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          TextStartUiMessageChunk('txt_1'),
          TextDeltaUiMessageChunk('txt_1', 'hi'),
        ]),
      ).last,
      UiMessage(
        id: '',
        role: UiMessageRole.assistant,
        parts: const [TextUiPart('hi', state: UiPartState.streaming)],
      ),
    );

    // smoothStream 入口 + 内置/自定义 chunk detector 类型。
    String? detector(String buffer) {
      return buffer.length >= 2 ? buffer.substring(0, 2) : null;
    }

    final smoothed = await Stream<TextStreamPart>.fromIterable(const [
      TextDeltaPart('1', 'hello world'),
    ])
        .transform(smoothStream(
          delay: null,
          chunking: SmoothStreamChunking.custom(detector),
        ))
        .toList();
    expect(smoothed, const [
      TextDeltaPart('1', 'he'),
      TextDeltaPart('1', 'll'),
      TextDeltaPart('1', 'o '),
      TextDeltaPart('1', 'wo'),
      TextDeltaPart('1', 'rl'),
      TextDeltaPart('1', 'd'),
    ]);
  });

  test('barrel re-exports contract types used by pigcode_ai public API',
      () async {
    // RequestInfo / ResponseInfo:StartStepPart.request / FinishStepPart.response。
    const requestInfo = RequestInfo(body: {'k': 'v'});
    const responseInfo = ResponseInfo(id: 'r1');
    final startStep = StartStepPart(request: requestInfo, warnings: []);
    expect(startStep.request, requestInfo);
    expect(responseInfo.id, 'r1');

    // Warning 及其全部变体:StartStepPart.warnings。
    final warnings = <Warning>[
      const UnsupportedWarning('feature-a'),
      const CompatibilityWarning('feature-b'),
      const DeprecatedWarning('setting-c', 'deprecated'),
      const OtherWarning('other'),
    ];
    final startStepWithWarnings =
        StartStepPart(request: null, warnings: warnings);
    expect(startStepWithWarnings.warnings, warnings);

    // ToolResultContentOutput 及其 items 判别联合(含 FileItem):FileData 的
    // 具体变体现已从 barrel 导出,故 FileItem 可经 barrel 真正实例化(自足性)。
    const contentOutput = ToolResultContentOutput(<ToolResultContentItem>[
      ToolResultTextItem('hi'),
      ToolResultCustomItem(),
      ToolResultFileItem(
        data: FileDataBase64('YQ=='),
        mediaType: 'text/plain',
      ),
    ]);
    expect(contentOutput.items, hasLength(3));
    expect(contentOutput.items, everyElement(isA<ToolResultContentItem>()));
    // FileData 的各具体变体均可从 barrel 具名/构造。
    expect(FileDataBytes, isNotNull);
    expect(const FileDataBase64('YQ==').base64, 'YQ==');
    expect(FileDataUrl(Uri.parse('https://e.com/a')).url.host, 'e.com');
    expect(
      const FileDataReference(<String, String>{'k': 'v'}).reference['k'],
      'v',
    );
    expect(const FileDataText('x').text, 'x');

    // Output API 与结构化输出错误。
    final output = Output.object(
      schema: const JsonSchema({'type': 'object'}),
    );
    expect(output, isA<Output<JsonObject, JsonObject, Never>>());
    const ResponseFormat responseFormat = ResponseFormatText();
    expect(responseFormat, isA<ResponseFormatText>());
    expect(const ResponseFormatJson(), isA<ResponseFormat>());
    expect(const NoOutputGeneratedError(), isA<AiError>());
    expect(const NoObjectGeneratedError(), isA<AiError>());
    expect(const NoImageGeneratedError(), isA<AiError>());
    expect(const NoVideoGeneratedError(), isA<AiError>());
    expect(const NoTranscriptGeneratedError(), isA<AiError>());
    expect(
      NoSuchProviderReferenceError(
        provider: 'openai',
        reference: const {'anthropic': 'file-1'},
      ),
      isA<AiError>(),
    );
    expect(
      NoSuchProviderError(
        modelId: 'missing',
        modelType: ModelType.languageModel,
        providerId: 'missing',
        availableProviders: ['echo'],
      ),
      isA<NoSuchModelError>(),
    );

    // ProviderReference:DataProviderRef.reference。
    const providerReference = <String, String>{'openai': 'file-1'};
    const dataRef = DataProviderRef(providerReference);
    expect(dataRef.reference, providerReference);
    expect(const DataText('inline').text, 'inline');

    // FunctionTool:buildLanguageModelTools 的返回元素类型。
    final functionTools = buildLanguageModelTools(<String, Tool>{
      'echo': Tool(
        inputSchema: const JsonSchema(<String, Object?>{'type': 'object'}),
      ),
    });
    expect(functionTools.single, isA<FunctionTool>());
  });

  test('barrel exposes embedding surface and re-exports its contract types',
      () async {
    // cosineSimilarity 入口。
    expect(cosineSimilarity([1, 0], [1, 0]), closeTo(1.0, 1e-9));

    // Embedding typedef 经 barrel 可具名。
    final Embedding vector = [0.5, 0.5];
    expect(vector, hasLength(2));

    // EmbeddingModel/EmbeddingModelCallOptions/EmbeddingModelResult/
    // EmbeddingUsage/EmbeddingResponseInfo:经 barrel 实现契约并往返。
    final EmbeddingModel model = _EchoEmbeddingModel();

    // embed 入口 + EmbedResult。
    final embedded = await embed(model: model, value: 'hi');
    expect(embedded, isA<EmbedResult>());
    expect(embedded.embedding, [2.0]);
    expect(embedded.usage, const EmbeddingUsage(tokens: 3));
    expect(
      embedded.response,
      const EmbeddingResponseInfo(headers: {'x-echo': 'y'}),
    );

    // embedMany 入口 + EmbedManyResult(快路径,保序)。
    final many = await embedMany(model: model, values: ['a', 'bb']);
    expect(many, isA<EmbedManyResult>());
    expect(many.embeddings, [
      [1.0],
      [2.0],
    ]);

    // TooManyEmbeddingValuesForCallError 经 barrel 可构造。
    final error = TooManyEmbeddingValuesForCallError(
      provider: 'test.embedding',
      modelId: 'echo-embedding',
      maxEmbeddingsPerCall: 1,
      valuesCount: 2,
    );
    expect(error, isA<AiError>());
    expect(error.valuesCount, 2);
  });

  test('barrel exposes reranking surface and contract types', () async {
    final RerankingModel model = _EchoRerankingModel();
    const documents = ['alpha', 'beta'];
    final result = await rerank(
      model: model,
      documents: documents,
      query: 'b',
    );

    expect(result, isA<RerankResult<String>>());
    expect(result.ranking.first, isA<RerankRanking<String>>());
    expect(result.rerankedDocuments, ['beta', 'alpha']);
    expect(
      const RerankingDocumentsText(documents),
      isA<RerankingDocuments>(),
    );
    expect(
      const RerankingDocumentsObject([
        <String, Object?>{'id': '1'},
      ]),
      isA<RerankingDocuments>(),
    );
    const options = RerankingModelCallOptions(
      documents: RerankingDocumentsText(documents),
      query: 'b',
    );
    expect(options, isA<RerankingModelCallOptions>());
    expect(
      const RerankingModelRanking(index: 0, relevanceScore: 1),
      isA<RerankingModelRanking>(),
    );
    expect(
      const RerankingModelResult(ranking: [], warnings: []),
      isA<RerankingModelResult>(),
    );
  });

  test('barrel exposes transcription surface and contract types', () async {
    final TranscriptionModel model = _EchoTranscriptionModel();
    final result = await transcribe(
      model: model,
      audio: DataBase64('AQID'),
      mediaType: 'audio/wav',
    );

    expect(result, isA<TranscriptionResult>());
    expect(result.text, 'transcript-ok');
    expect(result.segments.single, isA<TranscriptionSegment>());
    expect(result.responses.single.modelId, 'echo-transcription');

    const bytes = TranscriptionAudioBase64('AQID');
    expect(bytes, isA<TranscriptionAudio>());

    final streamed = streamTranscribe(
      model: model,
      audio: const Stream<DataContent>.empty(),
      inputAudioFormat: const TranscriptionInputAudioFormat(type: 'audio/pcm'),
    );
    expect(await streamed.stream.toList(), [
      const TranscriptDeltaPart(delta: 'stream-'),
      const TranscriptFinalPart(
          text: 'stream-ok', startSecond: 0, endSecond: 1),
    ]);
    expect(await streamed.text, 'stream-ok');
    expect(await streamed.responses, [
      const ResponseInfo(modelId: 'echo-transcription-stream'),
    ]);
    expect(const StreamTranscriptionInclude(rawChunks: true).rawChunks, isTrue);
  });

  test('barrel exposes image surface and contract types', () async {
    final ImageModel model = _EchoImageModel();
    final result = await generateImage(model: model, prompt: 'hello image');

    expect(result, isA<GenerateImageResult>());
    expect(result.image, isA<GeneratedImage>());
    expect(result.image.mediaType, 'image/png');
    expect(result.responses.single.modelId, 'echo-image');

    const options = ImageModelCallOptions(prompt: 'hello image');
    expect(options, isA<ImageModelCallOptions>());
  });

  test('barrel exposes video surface and contract types', () async {
    final VideoModel model = _EchoVideoModel();
    final result = await generateVideo(model: model, prompt: 'hello video');

    expect(result, isA<GenerateVideoResult>());
    expect(result.video, isA<GeneratedVideo>());
    expect(result.video.mediaType, 'video/mp4');
    expect(result.responses.single.modelId, 'echo-video');

    const options = VideoModelCallOptions(prompt: 'hello video');
    expect(options, isA<VideoModelCallOptions>());
    expect(
      const VideoModelVideoDataBase64('AAAA', mediaType: 'video/mp4'),
      isA<VideoModelVideoData>(),
    );
    expect(
      VideoModelVideoDataUrl(Uri.parse('https://example.com/out.mp4')),
      isA<VideoModelVideoData>(),
    );
    expect(
      const VideoFrameImage(
        image: VideoModelFileBase64('AAAA', mediaType: 'image/png'),
        frameType: VideoFrameType.firstFrame,
      ),
      isA<VideoFrameImage>(),
    );
  });

  test('barrel exposes speech surface and contract types', () async {
    final SpeechModel model = _EchoSpeechModel();
    final result = await generateSpeech(
      model: model,
      text: 'hello',
      outputFormat: 'mp3',
    );

    expect(result, isA<SpeechResult>());
    expect(result.audio, [1, 2, 3]);
    expect(result.mediaType, 'audio/mp3');
    expect(result.responses.single.modelId, 'echo-speech');

    const options = SpeechModelCallOptions(text: 'hello');
    expect(options, isA<SpeechModelCallOptions>());
  });
}
