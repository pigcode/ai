import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

import '../support/scripted_embedding_model.dart';
import '../support/scripted_model.dart';

void main() {
  group('wrapProvider', () {
    test('wraps language, embedding, and image model factories with middleware',
        () async {
      final languageModel = ScriptedModel(
        provider: 'scripted',
        modelId: 'lm-1',
        turns: [
          ScriptedTurn(
            content: const [contracts.TextContent('ok')],
            finishReason: const contracts.LanguageModelFinishReason(
              contracts.FinishReasonType.stop,
            ),
            usage: const contracts.LanguageModelUsage(
              inputTokens: contracts.InputTokens(),
              outputTokens: contracts.OutputTokens(),
            ),
          ),
        ],
      );
      final embeddingModel = ScriptedEmbeddingModel(
        provider: 'scripted-embedding',
        modelId: 'embed-1',
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
            [2.0],
          ]),
        ],
      );
      final imageModel = _FakeImageModel();
      final baseProvider = _ScriptedProvider(
        languageModels: {'lm-1': languageModel},
        embeddingModels: {'embed-1': embeddingModel},
        imageModels: {'image-1': imageModel},
      );

      final wrapped = wrapProvider(
        provider: baseProvider,
        languageModelMiddleware: contracts.LanguageModelMiddleware(
          transformParams: ({
            required bool stream,
            required contracts.LanguageModelCallOptions params,
            required contracts.LanguageModel model,
          }) async =>
              params.copyWith(temperature: 0.42),
        ),
        embeddingModelMiddleware: contracts.EmbeddingModelMiddleware(
          transformParams: ({
            required contracts.EmbeddingModelCallOptions params,
            required contracts.EmbeddingModel model,
          }) async =>
              contracts.EmbeddingModelCallOptions(
            values: [...params.values, 'extra'],
            headers: params.headers,
            providerOptions: params.providerOptions,
            cancellation: params.cancellation,
          ),
        ),
        imageModelMiddleware: contracts.ImageModelMiddleware(
          transformParams: ({
            required contracts.ImageModelCallOptions params,
            required contracts.ImageModel model,
          }) async =>
              contracts.ImageModelCallOptions(
            prompt: '${params.prompt} in blue',
            n: 2,
            size: params.size,
            aspectRatio: params.aspectRatio,
            seed: params.seed,
            headers: params.headers,
            providerOptions: params.providerOptions,
            cancellation: params.cancellation,
          ),
        ),
      );

      await wrapped.languageModel('lm-1').doGenerate(
            const contracts.LanguageModelCallOptions(
              prompt: [
                contracts.UserMessage([contracts.TextPart('hi')]),
              ],
            ),
          );
      await wrapped.embeddingModel('embed-1').doEmbed(
            const contracts.EmbeddingModelCallOptions(values: ['base']),
          );
      await wrapped.imageModel('image-1').doGenerate(
            const contracts.ImageModelCallOptions(prompt: 'draw icon'),
          );

      expect(languageModel.receivedCallOptions.single.temperature, 0.42);
      expect(embeddingModel.receivedCallOptions.single.values, [
        'base',
        'extra',
      ]);
      expect(imageModel.receivedCallOptions.single.prompt, 'draw icon in blue');
      expect(imageModel.receivedCallOptions.single.n, 2);
    });

    test('without middleware delegates model factories unchanged', () {
      final languageModel = ScriptedModel(turns: const []);
      final embeddingModel = ScriptedEmbeddingModel(batches: const []);
      final imageModel = _FakeImageModel();
      final transcriptionModel = _FakeTranscriptionModel();
      final speechModel = _FakeSpeechModel();
      final videoModel = _FakeVideoModel();
      final rerankingModel = _FakeRerankingModel();
      final files = _FakeFiles();
      final skills = _FakeSkills();
      final baseProvider = _ScriptedProvider(
        languageModels: {'lm': languageModel},
        embeddingModels: {'embed': embeddingModel},
        imageModels: {'image': imageModel},
        transcriptionModels: {'transcribe': transcriptionModel},
        speechModels: {'speech': speechModel},
        videoModels: {'video': videoModel},
        rerankingModels: {'rerank': rerankingModel},
        files: files,
        skills: skills,
      );

      final wrapped = wrapProvider(provider: baseProvider);

      expect(wrapped.specificationVersion, contracts.providerSpecVersion);
      expect(wrapped.languageModel('lm'), same(languageModel));
      expect(wrapped.embeddingModel('embed'), same(embeddingModel));
      expect(wrapped.imageModel('image'), same(imageModel));
      expect(
        wrapped.transcriptionModel('transcribe'),
        same(transcriptionModel),
      );
      expect(wrapped.speechModel('speech'), same(speechModel));
      expect(wrapped.videoModel('video'), same(videoModel));
      expect(wrapped.rerankingModel('rerank'), same(rerankingModel));
      expect(wrapped.files(), same(files));
      expect(wrapped.skills(), same(skills));
    });
  });
}

final class _FakeImageModel implements contracts.ImageModel {
  final List<contracts.ImageModelCallOptions> receivedCallOptions = [];

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'scripted-image';

  @override
  String get modelId => 'image-1';

  @override
  int? get maxImagesPerCall => null;

  @override
  Future<contracts.ImageModelResult> doGenerate(
    contracts.ImageModelCallOptions options,
  ) async {
    receivedCallOptions.add(options);
    return const contracts.ImageModelResult(images: [], warnings: []);
  }
}

final class _FakeTranscriptionModel implements contracts.TranscriptionModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'scripted-transcription';

  @override
  String get modelId => 'transcribe-1';

  @override
  Future<contracts.TranscriptionModelResult> doGenerate(
    contracts.TranscriptionModelCallOptions options,
  ) {
    throw UnimplementedError('wrapProvider tests never call doGenerate');
  }
}

final class _FakeSpeechModel implements contracts.SpeechModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'scripted-speech';

  @override
  String get modelId => 'speech-1';

  @override
  Future<contracts.SpeechModelResult> doGenerate(
    contracts.SpeechModelCallOptions options,
  ) {
    throw UnimplementedError('wrapProvider tests never call doGenerate');
  }
}

final class _FakeVideoModel implements contracts.VideoModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'scripted-video';

  @override
  String get modelId => 'video-1';

  @override
  int? get maxVideosPerCall => null;

  @override
  Future<contracts.VideoModelResult> doGenerate(
    contracts.VideoModelCallOptions options,
  ) {
    throw UnimplementedError('wrapProvider tests never call doGenerate');
  }
}

final class _FakeRerankingModel implements contracts.RerankingModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'scripted-reranking';

  @override
  String get modelId => 'rerank-1';

  @override
  Future<contracts.RerankingModelResult> doRerank(
    contracts.RerankingModelCallOptions options,
  ) {
    throw UnimplementedError('wrapProvider tests never call doRerank');
  }
}

final class _FakeFiles implements contracts.Files {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'scripted-files';

  @override
  Future<contracts.FilesUploadResult> uploadFile(
    contracts.FilesUploadOptions options,
  ) {
    throw UnimplementedError('wrapProvider tests never call uploadFile');
  }
}

final class _FakeSkills implements contracts.Skills {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'scripted-skills';

  @override
  Future<contracts.SkillsUploadResult> uploadSkill(
    contracts.SkillsUploadOptions options,
  ) {
    throw UnimplementedError('wrapProvider tests never call uploadSkill');
  }
}

final class _ScriptedProvider implements contracts.Provider {
  const _ScriptedProvider({
    required this.languageModels,
    required this.embeddingModels,
    this.imageModels = const {},
    this.transcriptionModels = const {},
    this.speechModels = const {},
    this.videoModels = const {},
    this.rerankingModels = const {},
    contracts.Files? files,
    contracts.Skills? skills,
  })  : _files = files,
        _skills = skills;

  final Map<String, contracts.LanguageModel> languageModels;
  final Map<String, contracts.EmbeddingModel> embeddingModels;
  final Map<String, contracts.ImageModel> imageModels;
  final Map<String, contracts.TranscriptionModel> transcriptionModels;
  final Map<String, contracts.SpeechModel> speechModels;
  final Map<String, contracts.VideoModel> videoModels;
  final Map<String, contracts.RerankingModel> rerankingModels;
  final contracts.Files? _files;
  final contracts.Skills? _skills;

  @override
  String get specificationVersion => 'v4';

  @override
  contracts.LanguageModel languageModel(String modelId) {
    final model = languageModels[modelId];
    if (model == null) {
      throw contracts.NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.languageModel,
      );
    }
    return model;
  }

  @override
  contracts.EmbeddingModel embeddingModel(String modelId) {
    final model = embeddingModels[modelId];
    if (model == null) {
      throw contracts.NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.embeddingModel,
      );
    }
    return model;
  }

  @override
  contracts.ImageModel imageModel(String modelId) {
    final model = imageModels[modelId];
    if (model == null) {
      throw contracts.NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.imageModel,
      );
    }
    return model;
  }

  @override
  contracts.TranscriptionModel transcriptionModel(String modelId) {
    final model = transcriptionModels[modelId];
    if (model == null) {
      throw contracts.NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.transcriptionModel,
      );
    }
    return model;
  }

  @override
  contracts.SpeechModel speechModel(String modelId) {
    final model = speechModels[modelId];
    if (model == null) {
      throw contracts.NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.speechModel,
      );
    }
    return model;
  }

  @override
  contracts.VideoModel videoModel(String modelId) {
    final model = videoModels[modelId];
    if (model == null) {
      throw contracts.NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.videoModel,
      );
    }
    return model;
  }

  @override
  contracts.RerankingModel rerankingModel(String modelId) {
    final model = rerankingModels[modelId];
    if (model == null) {
      throw contracts.NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.rerankingModel,
      );
    }
    return model;
  }

  @override
  contracts.Files files() {
    final files = _files;
    if (files == null) {
      throw const contracts.UnsupportedFunctionalityError(
        functionality: 'files',
      );
    }
    return files;
  }

  @override
  contracts.Skills skills() {
    final skills = _skills;
    if (skills == null) {
      throw const contracts.UnsupportedFunctionalityError(
        functionality: 'skills',
      );
    }
    return skills;
  }
}
