// 目的:仅经由公共 barrel 触达每个公共区域的一个代表性符号,
// 证明 barrel 完整且未泄漏/漏导出任何内部类型。
import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('barrel exposes the full public surface', () {
    test('json area', () {
      const JsonObject obj = <String, Object?>{'k': 'v'};
      const schema = JsonSchema(<String, Object?>{'type': 'object'});
      // ignore: unnecessary_nullable_for_final_variable_declarations
      const JsonValue value = 1;
      const JsonArray array = <Object?>[1, 2];
      expect(schema.value, obj.keys.isEmpty ? isEmpty : isNotEmpty);
      expect(value, 1);
      expect(array, hasLength(2));
    });

    test('shared area (metadata / warning / file data)', () {
      const ProviderMetadata meta = <String, JsonObject>{
        'openai': <String, Object?>{'k': 'v'},
      };
      const ProviderOptions options = <String, JsonObject>{};
      const ProviderReference reference = <String, String>{'openai': 'file-1'};
      const Headers headers = <String, String>{'x': 'y'};
      const Warning warning = UnsupportedWarning('feature');
      final FileData file = FileDataBytes(Uint8List.fromList(<int>[1, 2, 3]));
      expect(meta, isNotEmpty);
      expect(options, isEmpty);
      expect(reference['openai'], 'file-1');
      expect(headers['x'], 'y');
      expect(warning, isA<UnsupportedWarning>());
      expect(file, isA<FileDataBytes>());
      expect(const DeprecatedWarning('s', 'm'), isA<Warning>());
      expect(const FileDataText('hi'), isA<FileData>());
    });

    test('message area', () {
      const LanguageModelMessage message = SystemMessage('you are a bot');
      const LanguageModelPrompt prompt = <LanguageModelMessage>[message];
      expect(message, isA<SystemMessage>());
      expect(prompt, hasLength(1));
      expect(
          const UserMessage(<UserContentPart>[]), isA<LanguageModelMessage>());
    });

    test('content part area', () {
      const UserContentPart part = TextPart('hello');
      const AssistantContentPart reasoning = ReasoningPart('thinking');
      const AssistantContentPart request =
          ToolApprovalRequestPart(approvalId: 'a1', toolCallId: 'c1');
      const ToolContentPart approval =
          ToolApprovalResponsePart(approvalId: 'a1', approved: true);
      expect(part, isA<TextPart>());
      expect(reasoning, isA<ReasoningPart>());
      expect(request, isA<ToolApprovalRequestPart>());
      expect(approval, isA<ToolApprovalResponsePart>());
    });

    test('tool area', () {
      const LanguageModelTool tool = FunctionTool(
        name: 'get_weather',
        inputSchema: JsonSchema(<String, Object?>{'type': 'object'}),
      );
      const ToolChoice choice = ToolChoiceAuto();
      const ToolResultOutput output = ToolResultText('done');
      const ToolResultContentItem item = ToolResultTextItem('chunk');
      expect(tool, isA<FunctionTool>());
      expect(choice, isA<ToolChoiceAuto>());
      expect(output, isA<ToolResultText>());
      expect(item, isA<ToolResultTextItem>());
      expect(const ToolChoiceTool('get_weather'), isA<ToolChoice>());
    });

    test('content (doGenerate output) area', () {
      const LanguageModelContent content = TextContent('hi');
      const ToolCall call =
          ToolCall(toolCallId: 'c1', toolName: 't', input: '{}');
      const source = SourceContent.url(id: 's1', url: 'https://example.com');
      expect(content, isA<TextContent>());
      expect(call.input, '{}');
      expect(source.sourceType, SourceType.url);
    });

    test('stream part area', () {
      const LanguageModelStreamPart start = StreamStart(<Warning>[]);
      const LanguageModelStreamPart delta = TextDelta('t1', 'hello');
      const LanguageModelStreamPart error = ErrorPart('boom');
      // 复用的内容项(7 个)也是 stream part(同时实现两个 sealed 上界)。
      const LanguageModelStreamPart shared =
          ToolCall(toolCallId: 'c', toolName: 't', input: '{}');
      expect(start, isA<StreamStart>());
      expect(delta, isA<TextDelta>());
      expect(error, isA<ErrorPart>());
      expect(shared, isA<LanguageModelStreamPart>());
    });

    test('usage area', () {
      const usage = LanguageModelUsage(
        inputTokens: InputTokens(total: 10),
        outputTokens: OutputTokens(total: 5),
      );
      expect(usage.inputTokens.total, 10);
      expect(usage.outputTokens.total, 5);
    });

    test('finish reason area', () {
      const reason = LanguageModelFinishReason(FinishReasonType.stop);
      expect(reason.unified, FinishReasonType.stop);
      expect(FinishReasonType.values, contains(FinishReasonType.toolCalls));
    });

    test('reasoning + response format areas', () {
      expect(ReasoningEffort.providerDefault.wireValue, 'provider-default');
      const ResponseFormat format = ResponseFormatText();
      expect(format, isA<ResponseFormatText>());
      expect(const ResponseFormatJson(), isA<ResponseFormat>());
    });

    test('call options area', () {
      const options = LanguageModelCallOptions(
        prompt: <LanguageModelMessage>[SystemMessage('sys')],
        temperature: 0.5,
      );
      final copied = options.copyWith(topP: 0.9);
      expect(copied.temperature, 0.5);
      expect(copied.topP, 0.9);
    });

    test('language model + results area', () {
      const result = LanguageModelGenerateResult(
        content: <LanguageModelContent>[TextContent('hi')],
        finishReason: LanguageModelFinishReason(FinishReasonType.stop),
        usage: LanguageModelUsage(
          inputTokens: InputTokens(),
          outputTokens: OutputTokens(),
        ),
        warnings: <Warning>[],
      );
      expect(result.content, hasLength(1));
      // LanguageModel 是抽象接口:引用其静态类型即证明其被导出。
      const LanguageModel? model = null;
      expect(model, isNull);
      final stream = LanguageModelStreamResult(
        stream: const Stream<LanguageModelStreamPart>.empty(),
      );
      expect(stream.stream, isNotNull);
    });

    test('provider area', () {
      const Provider? provider = null;
      expect(provider, isNull);
    });

    test('middleware area', () {
      const middleware = LanguageModelMiddleware();
      expect(middleware, isA<LanguageModelMiddleware>());
      final imageMiddleware = ImageModelMiddleware(
        wrapGenerate: ({
          required ImageModelDoGenerate doGenerate,
          required ImageModelCallOptions params,
          required ImageModel model,
        }) =>
            doGenerate(),
      );
      expect(imageMiddleware, isA<ImageModelMiddleware>());
      expect(imageMiddleware.wrapGenerate, isNotNull);
    });

    test('cancellation area', () {
      final controller = CancellationController();
      final CancellationSignal signal = controller.signal;
      expect(signal.isCancelled, isFalse);
      controller.cancel();
      expect(signal.isCancelled, isTrue);
    });

    test('errors area', () {
      const AiError error = ApiCallError(
        message: 'server error',
        url: 'https://example.com',
        requestBody: null,
        statusCode: 503,
      );
      expect(error, isA<ApiCallError>());
      expect((error as ApiCallError).isRetryable, isTrue);
      expect(ModelType.languageModel, isA<ModelType>());
      expect(
        NoSuchProviderReferenceError(
          provider: 'google',
          reference: {'openai': 'file-1'},
        ),
        isA<AiError>(),
      );
      expect(
        NoSuchProviderError(
          modelId: 'google',
          modelType: ModelType.languageModel,
          providerId: 'google',
          availableProviders: ['openai'],
        ),
        isA<NoSuchModelError>(),
      );
      expect(const NoOutputGeneratedError(), isA<AiError>());
      expect(const NoObjectGeneratedError(), isA<AiError>());
      expect(const NoTranscriptGeneratedError(), isA<AiError>());
      expect(const NoSpeechGeneratedError(), isA<AiError>());
      expect(const NoImageGeneratedError(), isA<AiError>());
      expect(const NoVideoGeneratedError(), isA<AiError>());
    });

    test('embedding area', () {
      const options = EmbeddingModelCallOptions(values: ['hello']);
      const result = EmbeddingModelResult(
        embeddings: <Embedding>[
          [0.1, 0.2],
        ],
        warnings: <Warning>[],
      );
      expect(options.values, ['hello']);
      expect(result.embeddings, hasLength(1));
      // EmbeddingModel 是抽象接口:引用其静态类型即证明其被导出。
      const EmbeddingModel? model = null;
      expect(model, isNull);
      const usage = EmbeddingUsage(tokens: 3);
      const response = EmbeddingResponseInfo(headers: {'x': 'y'});
      expect(usage.tokens, 3);
      expect(response.headers, {'x': 'y'});
      final middleware = EmbeddingModelMiddleware(
        wrapEmbed: ({
          required EmbeddingModelDoEmbed doEmbed,
          required EmbeddingModelCallOptions params,
          required EmbeddingModel model,
        }) =>
            doEmbed(),
      );
      expect(middleware.wrapEmbed, isNotNull);
      final tooMany = TooManyEmbeddingValuesForCallError(
        provider: 'p',
        modelId: 'm',
        maxEmbeddingsPerCall: 1,
        valuesCount: 2,
      );
      expect(tooMany, isA<AiError>());
    });

    test('reranking area', () {
      const documents = RerankingDocumentsText(['a', 'b']);
      const objectDocuments = RerankingDocumentsObject([
        <String, Object?>{'id': '1'},
      ]);
      const options = RerankingModelCallOptions(
        documents: documents,
        query: 'a',
      );
      const ranking = RerankingModelRanking(
        index: 0,
        relevanceScore: 0.9,
      );
      const result = RerankingModelResult(
        ranking: [ranking],
        warnings: <Warning>[],
      );

      expect(documents, isA<RerankingDocuments>());
      expect(objectDocuments, isA<RerankingDocuments>());
      expect(options.query, 'a');
      expect(result.ranking.single.relevanceScore, 0.9);
      const RerankingModel? model = null;
      expect(model, isNull);
    });

    test('transcription area', () {
      final options = TranscriptionModelCallOptions(
        audio: TranscriptionAudioBytes(Uint8List.fromList([1, 2, 3])),
        mediaType: 'audio/wav',
      );
      const result = TranscriptionModelResult(
        text: 'hello',
        segments: [
          TranscriptionSegment(
            text: 'hello',
            startSecond: 0,
            endSecond: 1,
          ),
        ],
        warnings: <Warning>[],
      );

      expect(options.audio, isA<TranscriptionAudioBytes>());
      expect(const TranscriptionAudioBase64('AQID'), isA<TranscriptionAudio>());
      expect(result.segments.single.text, 'hello');
      const TranscriptionModel? model = null;
      expect(model, isNull);
      final streamResult = TranscriptionModelStreamResult(
        stream: const Stream<TranscriptionModelStreamPart>.empty(),
        response: const ResponseInfo(modelId: 'stream-model'),
      );
      expect(
        const TranscriptionInputAudioFormat(type: 'audio/pcm', rate: 24000),
        isA<TranscriptionInputAudioFormat>(),
      );
      expect(
        const TranscriptionStreamStart(<Warning>[]),
        isA<TranscriptionModelStreamPart>(),
      );
      expect(streamResult.response?.modelId, 'stream-model');
      const StreamableTranscriptionModel? streamableModel = null;
      expect(streamableModel, isNull);
    });

    test('speech area', () {
      final audio = Uint8List.fromList([1, 2, 3]);
      const options = SpeechModelCallOptions(
        text: 'hello',
        voice: 'nova',
        outputFormat: 'mp3',
      );
      final result = SpeechModelResult(
        audio: audio,
        format: 'mp3',
        warnings: const <Warning>[],
      );
      expect(options.text, 'hello');
      expect(options.voice, 'nova');
      expect(result.audio, audio);
      expect(result.format, 'mp3');
      const SpeechModel? model = null;
      expect(model, isNull);
    });

    test('image area', () {
      final image = Uint8List.fromList([1, 2, 3]);
      const options = ImageModelCallOptions(
        prompt: 'A tiny ceramic teapot',
        n: 1,
        size: '1024x1024',
      );
      final result = ImageModelResult(
        images: [image],
        warnings: const <Warning>[],
      );
      expect(options.prompt, 'A tiny ceramic teapot');
      expect(options.n, 1);
      expect(result.images.single, image);
      const ImageModel? model = null;
      expect(model, isNull);
      const usage = ImageModelUsage(inputTokens: 1, outputTokens: 2);
      expect(usage.totalTokens, isNull);
    });

    test('video area', () {
      final videoBytes = Uint8List.fromList([1, 2, 3]);
      final imageBytes = Uint8List.fromList([4, 5, 6]);
      final frame = VideoFrameImage(
        image: VideoModelFileBytes(imageBytes, mediaType: 'image/png'),
        frameType: VideoFrameType.firstFrame,
      );
      final options = VideoModelCallOptions(
        prompt: 'A calm ocean loop',
        n: 1,
        aspectRatio: '16:9',
        resolution: '1280x720',
        frameImages: [frame],
      );
      final result = VideoModelResult(
        videos: [
          VideoModelVideoDataBytes(videoBytes, mediaType: 'video/mp4'),
        ],
        warnings: const <Warning>[],
      );

      expect(options.prompt, 'A calm ocean loop');
      expect(options.frameImages?.single.frameType, VideoFrameType.firstFrame);
      expect(const VideoModelFileBase64('AQID', mediaType: 'image/png'),
          isA<VideoModelFile>());
      expect(VideoModelFileUrl(Uri.parse('https://example.com/image.png')),
          isA<VideoModelFile>());
      expect(result.videos.single, isA<VideoModelVideoDataBytes>());
      expect(const VideoModelVideoDataBase64('AAAA', mediaType: 'video/mp4'),
          isA<VideoModelVideoData>());
      expect(
        VideoModelVideoDataUrl(Uri.parse('https://example.com/video.mp4')),
        isA<VideoModelVideoData>(),
      );
      const VideoModel? model = null;
      expect(model, isNull);
    });

    test('files area', () {
      final data = FileDataBytes(Uint8List.fromList([1, 2, 3]));
      final options = FilesUploadOptions(
        data: data,
        mediaType: 'application/pdf',
        filename: 'doc.pdf',
        providerOptions: const {
          'openai': {'purpose': 'assistants'},
        },
      );
      const result = FilesUploadResult(
        providerReference: {'openai': 'file-1'},
        mediaType: 'application/pdf',
        filename: 'doc.pdf',
        providerMetadata: {
          'openai': {'purpose': 'assistants'},
        },
        warnings: <Warning>[],
      );

      expect(options.data, data);
      expect(options.mediaType, 'application/pdf');
      expect(result.providerReference['openai'], 'file-1');
      const Files? files = null;
      expect(files, isNull);
    });

    test('skills area', () {
      const file = SkillFile(
        path: 'SKILL.md',
        data: FileDataText('# Demo'),
      );
      const options = SkillsUploadOptions(
        files: [file],
        displayTitle: 'Demo skill',
      );
      const result = SkillsUploadResult(
        providerReference: {'openai': 'skill-1'},
        displayTitle: 'Demo skill',
        name: 'demo',
        description: 'A demo skill',
        latestVersion: 'v1',
        providerMetadata: {
          'openai': {'createdAt': 1},
        },
        warnings: <Warning>[],
      );

      expect(options.files.single.path, 'SKILL.md');
      expect(result.providerReference['openai'], 'skill-1');
      const Skills? skills = null;
      expect(skills, isNull);
    });
  });
}
