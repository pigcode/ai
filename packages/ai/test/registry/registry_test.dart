import 'dart:async';
import 'dart:typed_data';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

void main() {
  group('customProvider', () {
    test('returns configured models and resource APIs', () {
      final languageModel = _FakeLanguageModel('language-1');
      final embeddingModel = _FakeEmbeddingModel('embedding-1');
      final imageModel = _FakeImageModel('image-1');
      final transcriptionModel = _FakeTranscriptionModel('transcription-1');
      final speechModel = _FakeSpeechModel('speech-1');
      final videoModel = _FakeVideoModel('video-1');
      final rerankingModel = _FakeRerankingModel('reranking-1');
      final files = _FakeFiles();
      final skills = _FakeSkills();

      final provider = customProvider(
        languageModels: {'language-1': languageModel},
        embeddingModels: {'embedding-1': embeddingModel},
        imageModels: {'image-1': imageModel},
        transcriptionModels: {'transcription-1': transcriptionModel},
        speechModels: {'speech-1': speechModel},
        videoModels: {'video-1': videoModel},
        rerankingModels: {'reranking-1': rerankingModel},
        files: files,
        skills: skills,
      );

      expect(provider.specificationVersion, contracts.providerSpecVersion);
      expect(provider.languageModel('language-1'), same(languageModel));
      expect(provider.embeddingModel('embedding-1'), same(embeddingModel));
      expect(provider.imageModel('image-1'), same(imageModel));
      expect(
        provider.transcriptionModel('transcription-1'),
        same(transcriptionModel),
      );
      expect(provider.speechModel('speech-1'), same(speechModel));
      expect(provider.videoModel('video-1'), same(videoModel));
      expect(provider.rerankingModel('reranking-1'), same(rerankingModel));
      expect(provider.files(), same(files));
      expect(provider.skills(), same(skills));
    });

    test('delegates missing models and resource APIs to fallback provider', () {
      final fallbackLanguageModel = _FakeLanguageModel('fallback-language');
      final fallbackEmbeddingModel = _FakeEmbeddingModel('fallback-embedding');
      final fallbackImageModel = _FakeImageModel('fallback-image');
      final fallbackTranscriptionModel =
          _FakeTranscriptionModel('fallback-transcription');
      final fallbackSpeechModel = _FakeSpeechModel('fallback-speech');
      final fallbackVideoModel = _FakeVideoModel('fallback-video');
      final fallbackRerankingModel = _FakeRerankingModel('fallback-reranking');
      final fallbackFiles = _FakeFiles();
      final fallbackSkills = _FakeSkills();
      final fallback = _MapProvider(
        languageModels: {'fallback-language': fallbackLanguageModel},
        embeddingModels: {'fallback-embedding': fallbackEmbeddingModel},
        imageModels: {'fallback-image': fallbackImageModel},
        transcriptionModels: {
          'fallback-transcription': fallbackTranscriptionModel,
        },
        speechModels: {'fallback-speech': fallbackSpeechModel},
        videoModels: {'fallback-video': fallbackVideoModel},
        rerankingModels: {'fallback-reranking': fallbackRerankingModel},
        files: fallbackFiles,
        skills: fallbackSkills,
      );
      final provider = customProvider(fallbackProvider: fallback);

      expect(provider.languageModel('fallback-language'),
          same(fallbackLanguageModel));
      expect(provider.embeddingModel('fallback-embedding'),
          same(fallbackEmbeddingModel));
      expect(provider.imageModel('fallback-image'), same(fallbackImageModel));
      expect(
        provider.transcriptionModel('fallback-transcription'),
        same(fallbackTranscriptionModel),
      );
      expect(
          provider.speechModel('fallback-speech'), same(fallbackSpeechModel));
      expect(provider.videoModel('fallback-video'), same(fallbackVideoModel));
      expect(
        provider.rerankingModel('fallback-reranking'),
        same(fallbackRerankingModel),
      );
      expect(provider.files(), same(fallbackFiles));
      expect(provider.skills(), same(fallbackSkills));
    });

    test('throws typed errors for missing models and unsupported resources',
        () {
      final provider = customProvider();

      expect(
        () => provider.languageModel('missing'),
        throwsA(isA<NoSuchModelError>().having(
          (error) => error.modelType,
          'modelType',
          contracts.ModelType.languageModel,
        )),
      );
      expect(
        () => provider.embeddingModel('missing'),
        throwsA(isA<NoSuchModelError>().having(
          (error) => error.modelType,
          'modelType',
          contracts.ModelType.embeddingModel,
        )),
      );
      expect(
        () => provider.imageModel('missing'),
        throwsA(isA<NoSuchModelError>().having(
          (error) => error.modelType,
          'modelType',
          contracts.ModelType.imageModel,
        )),
      );
      expect(
        () => provider.transcriptionModel('missing'),
        throwsA(isA<NoSuchModelError>().having(
          (error) => error.modelType,
          'modelType',
          contracts.ModelType.transcriptionModel,
        )),
      );
      expect(
        () => provider.speechModel('missing'),
        throwsA(isA<NoSuchModelError>().having(
          (error) => error.modelType,
          'modelType',
          contracts.ModelType.speechModel,
        )),
      );
      expect(
        () => provider.videoModel('missing'),
        throwsA(isA<NoSuchModelError>().having(
          (error) => error.modelType,
          'modelType',
          contracts.ModelType.videoModel,
        )),
      );
      expect(
        () => provider.rerankingModel('missing'),
        throwsA(isA<NoSuchModelError>().having(
          (error) => error.modelType,
          'modelType',
          contracts.ModelType.rerankingModel,
        )),
      );
      expect(
        provider.files,
        throwsA(isA<UnsupportedFunctionalityError>().having(
          (error) => error.functionality,
          'functionality',
          'files',
        )),
      );
      expect(
        provider.skills,
        throwsA(isA<UnsupportedFunctionalityError>().having(
          (error) => error.functionality,
          'functionality',
          'skills',
        )),
      );
    });
  });

  group('createProviderRegistry', () {
    test('resolves every model type from provider:model ids', () {
      final languageModel = _FakeLanguageModel('language');
      final embeddingModel = _FakeEmbeddingModel('embedding');
      final imageModel = _FakeImageModel('image');
      final transcriptionModel = _FakeTranscriptionModel('transcription');
      final speechModel = _FakeSpeechModel('speech');
      final videoModel = _FakeVideoModel('video');
      final rerankingModel = _FakeRerankingModel('reranking');
      final provider = _MapProvider(
        languageModels: {'language:model': languageModel},
        embeddingModels: {'embedding:model': embeddingModel},
        imageModels: {'image:model': imageModel},
        transcriptionModels: {'transcription:model': transcriptionModel},
        speechModels: {'speech:model': speechModel},
        videoModels: {'video:model': videoModel},
        rerankingModels: {'reranking:model': rerankingModel},
      );
      final registry = createProviderRegistry({'test': provider});

      expect(registry.specificationVersion, contracts.providerSpecVersion);
      expect(
          registry.languageModel('test:language:model'), same(languageModel));
      expect(registry.embeddingModel('test:embedding:model'),
          same(embeddingModel));
      expect(registry.imageModel('test:image:model'), same(imageModel));
      expect(
        registry.transcriptionModel('test:transcription:model'),
        same(transcriptionModel),
      );
      expect(registry.speechModel('test:speech:model'), same(speechModel));
      expect(registry.videoModel('test:video:model'), same(videoModel));
      expect(
        registry.rerankingModel('test:reranking:model'),
        same(rerankingModel),
      );
    });

    test('supports custom separators and provider-scoped resources', () {
      final languageModel = _FakeLanguageModel('language');
      final files = _FakeFiles();
      final skills = _FakeSkills();
      final registry = createProviderRegistry(
        {
          'openai': _MapProvider(
            languageModels: {'gpt-4o': languageModel},
            files: files,
            skills: skills,
          ),
        },
        separator: ' > ',
      );

      expect(registry.languageModel('openai > gpt-4o'), same(languageModel));
      expect(registry.files('openai'), same(files));
      expect(registry.skills('openai'), same(skills));
    });

    test('rejects empty separators', () {
      expect(
        () => createProviderRegistry(const {}, separator: ''),
        throwsA(isA<ArgumentError>().having(
          (error) => error.name,
          'name',
          'separator',
        )),
      );
    });

    test('throws NoSuchProviderError for unknown providers', () {
      final registry = createProviderRegistry({
        'openai': _MapProvider(languageModels: const {}),
        'anthropic': _MapProvider(languageModels: const {}),
      });

      expect(
        () => registry.languageModel('google:gemini'),
        throwsA(isA<NoSuchProviderError>()
            .having((error) => error.providerId, 'providerId', 'google')
            .having(
          (error) => error.availableProviders,
          'availableProviders',
          ['openai', 'anthropic'],
        ).having(
          (error) => error.modelType,
          'modelType',
          contracts.ModelType.languageModel,
        )),
      );
    });

    test('throws NoSuchModelError for malformed registry ids', () {
      final registry = createProviderRegistry({});

      expect(
        () => registry.imageModel('image-only'),
        throwsA(isA<NoSuchModelError>()
            .having((error) => error.modelId, 'modelId', 'image-only')
            .having(
              (error) => error.modelType,
              'modelType',
              contracts.ModelType.imageModel,
            )
            .having(
              (error) => error.message,
              'message',
              contains('providerId:modelId'),
            )),
      );
    });
  });
}

final class _FakeLanguageModel implements LanguageModel {
  const _FakeLanguageModel(this.modelId);

  @override
  String get specificationVersion => contracts.languageModelSpecVersion;

  @override
  String get provider => 'fake-language';

  @override
  final String modelId;

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls => const {};

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) async =>
      const LanguageModelGenerateResult(
        content: [TextContent('ok')],
        finishReason: LanguageModelFinishReason(FinishReasonType.stop),
        usage: LanguageModelUsage(
          inputTokens: InputTokens(),
          outputTokens: OutputTokens(),
        ),
        warnings: [],
      );

  @override
  Future<LanguageModelStreamResult> doStream(
    LanguageModelCallOptions options,
  ) async =>
      LanguageModelStreamResult(
        stream: const Stream<LanguageModelStreamPart>.empty(),
      );
}

final class _FakeEmbeddingModel implements EmbeddingModel {
  const _FakeEmbeddingModel(this.modelId);

  @override
  String get specificationVersion => contracts.embeddingModelSpecVersion;

  @override
  String get provider => 'fake-embedding';

  @override
  final String modelId;

  @override
  FutureOr<int?> get maxEmbeddingsPerCall => null;

  @override
  FutureOr<bool> get supportsParallelCalls => true;

  @override
  Future<EmbeddingModelResult> doEmbed(
    EmbeddingModelCallOptions options,
  ) async =>
      const EmbeddingModelResult(
        embeddings: [
          [1],
        ],
        warnings: [],
      );
}

final class _FakeImageModel implements ImageModel {
  const _FakeImageModel(this.modelId);

  @override
  String get specificationVersion => contracts.imageModelSpecVersion;

  @override
  String get provider => 'fake-image';

  @override
  final String modelId;

  @override
  FutureOr<int?> get maxImagesPerCall => null;

  @override
  Future<ImageModelResult> doGenerate(
    ImageModelCallOptions options,
  ) async =>
      ImageModelResult(
        images: [
          Uint8List.fromList([1])
        ],
        warnings: const [],
      );
}

final class _FakeVideoModel implements VideoModel {
  const _FakeVideoModel(this.modelId);

  @override
  String get specificationVersion => contracts.videoModelSpecVersion;

  @override
  String get provider => 'fake-video';

  @override
  final String modelId;

  @override
  FutureOr<int?> get maxVideosPerCall => null;

  @override
  Future<VideoModelResult> doGenerate(
    VideoModelCallOptions options,
  ) async =>
      VideoModelResult(
        videos: [
          VideoModelVideoDataBytes(Uint8List.fromList([1]))
        ],
        warnings: const [],
      );
}

final class _FakeTranscriptionModel implements TranscriptionModel {
  const _FakeTranscriptionModel(this.modelId);

  @override
  String get specificationVersion => contracts.transcriptionModelSpecVersion;

  @override
  String get provider => 'fake-transcription';

  @override
  final String modelId;

  @override
  Future<TranscriptionModelResult> doGenerate(
    TranscriptionModelCallOptions options,
  ) async =>
      const TranscriptionModelResult(text: 'ok', segments: [], warnings: []);
}

final class _FakeSpeechModel implements SpeechModel {
  const _FakeSpeechModel(this.modelId);

  @override
  String get specificationVersion => contracts.speechModelSpecVersion;

  @override
  String get provider => 'fake-speech';

  @override
  final String modelId;

  @override
  Future<SpeechModelResult> doGenerate(
    SpeechModelCallOptions options,
  ) async =>
      SpeechModelResult(audio: Uint8List.fromList([1]), warnings: const []);
}

final class _FakeRerankingModel implements RerankingModel {
  const _FakeRerankingModel(this.modelId);

  @override
  String get specificationVersion => contracts.rerankingModelSpecVersion;

  @override
  String get provider => 'fake-reranking';

  @override
  final String modelId;

  @override
  Future<RerankingModelResult> doRerank(
    RerankingModelCallOptions options,
  ) async =>
      const RerankingModelResult(
        ranking: [RerankingModelRanking(index: 0, relevanceScore: 1)],
        warnings: [],
      );
}

final class _FakeFiles implements Files {
  @override
  String get specificationVersion => contracts.filesSpecVersion;

  @override
  String get provider => 'fake-files';

  @override
  Future<FilesUploadResult> uploadFile(FilesUploadOptions options) async =>
      const FilesUploadResult(
        providerReference: {'fake': 'file-1'},
        warnings: [],
      );
}

final class _FakeSkills implements Skills {
  @override
  String get specificationVersion => contracts.skillsSpecVersion;

  @override
  String get provider => 'fake-skills';

  @override
  Future<SkillsUploadResult> uploadSkill(SkillsUploadOptions options) async =>
      const SkillsUploadResult(
        providerReference: {'fake': 'skill-1'},
        warnings: [],
      );
}

final class _MapProvider implements Provider {
  const _MapProvider({
    this.languageModels = const {},
    this.embeddingModels = const {},
    this.imageModels = const {},
    this.transcriptionModels = const {},
    this.speechModels = const {},
    this.videoModels = const {},
    this.rerankingModels = const {},
    Files? files,
    Skills? skills,
  })  : _files = files,
        _skills = skills;

  final Map<String, LanguageModel> languageModels;
  final Map<String, EmbeddingModel> embeddingModels;
  final Map<String, ImageModel> imageModels;
  final Map<String, TranscriptionModel> transcriptionModels;
  final Map<String, SpeechModel> speechModels;
  final Map<String, VideoModel> videoModels;
  final Map<String, RerankingModel> rerankingModels;
  final Files? _files;
  final Skills? _skills;

  @override
  String get specificationVersion => contracts.providerSpecVersion;

  @override
  LanguageModel languageModel(String modelId) {
    final model = languageModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.languageModel,
      );
    }
    return model;
  }

  @override
  EmbeddingModel embeddingModel(String modelId) {
    final model = embeddingModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.embeddingModel,
      );
    }
    return model;
  }

  @override
  ImageModel imageModel(String modelId) {
    final model = imageModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.imageModel,
      );
    }
    return model;
  }

  @override
  TranscriptionModel transcriptionModel(String modelId) {
    final model = transcriptionModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.transcriptionModel,
      );
    }
    return model;
  }

  @override
  SpeechModel speechModel(String modelId) {
    final model = speechModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.speechModel,
      );
    }
    return model;
  }

  @override
  VideoModel videoModel(String modelId) {
    final model = videoModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.videoModel,
      );
    }
    return model;
  }

  @override
  RerankingModel rerankingModel(String modelId) {
    final model = rerankingModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.rerankingModel,
      );
    }
    return model;
  }

  @override
  Files files() {
    final files = _files;
    if (files == null) {
      throw const UnsupportedFunctionalityError(functionality: 'files');
    }
    return files;
  }

  @override
  Skills skills() {
    final skills = _skills;
    if (skills == null) {
      throw const UnsupportedFunctionalityError(functionality: 'skills');
    }
    return skills;
  }
}
