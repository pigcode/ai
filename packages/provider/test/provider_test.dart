import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

import 'support/echo_model.dart';

/// 最小的 fake [EmbeddingModel]:仅承载 provider/modelId 身份,契约测试
/// 不需要真正执行 [doEmbed]。
final class _FakeEmbeddingModel implements EmbeddingModel {
  _FakeEmbeddingModel({required this.provider, required this.modelId});

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  final String modelId;

  @override
  FutureOr<int?> get maxEmbeddingsPerCall => null;

  @override
  FutureOr<bool> get supportsParallelCalls => true;

  @override
  Future<EmbeddingModelResult> doEmbed(EmbeddingModelCallOptions options) {
    throw UnimplementedError('contract tests never call doEmbed');
  }
}

/// 最小的 fake [TranscriptionModel]:仅承载 provider/modelId 身份,契约测试
/// 不需要真正执行 [doGenerate]。
final class _FakeTranscriptionModel implements TranscriptionModel {
  _FakeTranscriptionModel({required this.provider, required this.modelId});

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  final String modelId;

  @override
  Future<TranscriptionModelResult> doGenerate(
    TranscriptionModelCallOptions options,
  ) {
    throw UnimplementedError('contract tests never call doGenerate');
  }
}

/// 最小的 fake [SpeechModel]:仅承载 provider/modelId 身份,契约测试
/// 不需要真正执行 [doGenerate]。
final class _FakeSpeechModel implements SpeechModel {
  _FakeSpeechModel({required this.provider, required this.modelId});

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  final String modelId;

  @override
  Future<SpeechModelResult> doGenerate(SpeechModelCallOptions options) {
    throw UnimplementedError('contract tests never call doGenerate');
  }
}

/// 最小的 fake [ImageModel]:仅承载 provider/modelId 身份,契约测试
/// 不需要真正执行 [doGenerate]。
final class _FakeImageModel implements ImageModel {
  _FakeImageModel({required this.provider, required this.modelId});

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  final String modelId;

  @override
  FutureOr<int?> get maxImagesPerCall => 1;

  @override
  Future<ImageModelResult> doGenerate(ImageModelCallOptions options) {
    throw UnimplementedError('contract tests never call doGenerate');
  }
}

/// 最小的 fake [VideoModel]:仅承载 provider/modelId 身份,契约测试
/// 不需要真正执行 [doGenerate]。
final class _FakeVideoModel implements VideoModel {
  _FakeVideoModel({required this.provider, required this.modelId});

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  final String modelId;

  @override
  FutureOr<int?> get maxVideosPerCall => 1;

  @override
  Future<VideoModelResult> doGenerate(VideoModelCallOptions options) {
    throw UnimplementedError('contract tests never call doGenerate');
  }
}

/// 最小的 fake [RerankingModel]:仅承载 provider/modelId 身份,契约测试
/// 不需要真正执行 [doRerank]。
final class _FakeRerankingModel implements RerankingModel {
  _FakeRerankingModel({required this.provider, required this.modelId});

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  final String modelId;

  @override
  Future<RerankingModelResult> doRerank(
    RerankingModelCallOptions options,
  ) {
    throw UnimplementedError('contract tests never call doRerank');
  }
}

final class _FakeFiles implements Files {
  _FakeFiles({required this.provider});

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  Future<FilesUploadResult> uploadFile(FilesUploadOptions options) {
    throw UnimplementedError('contract tests never call uploadFile');
  }
}

final class _FakeSkills implements Skills {
  _FakeSkills({required this.provider});

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  Future<SkillsUploadResult> uploadSkill(SkillsUploadOptions options) {
    throw UnimplementedError('contract tests never call uploadSkill');
  }
}

/// 最小的 fake [Provider]:注册表命中返回 echo/embedding 模型,未命中抛
/// [NoSuchModelError]。用于验证 [Provider] 契约的分支
/// (languageModel/embeddingModel/imageModel/transcriptionModel/speechModel)。
final class FakeProvider implements Provider {
  FakeProvider(
    this._models, [
    this._embeddingModels = const {},
    this._imageModels = const {},
    this._transcriptionModels = const {},
    this._speechModels = const {},
    this._videoModels = const {},
    this._files,
    this._skills,
    this._rerankingModels = const {},
  ]);

  @override
  String get specificationVersion => 'v4';

  final Map<String, LanguageModel> _models;
  final Map<String, EmbeddingModel> _embeddingModels;
  final Map<String, ImageModel> _imageModels;
  final Map<String, TranscriptionModel> _transcriptionModels;
  final Map<String, SpeechModel> _speechModels;
  final Map<String, VideoModel> _videoModels;
  final Map<String, RerankingModel> _rerankingModels;
  final Files? _files;
  final Skills? _skills;

  @override
  LanguageModel languageModel(String modelId) {
    final model = _models[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: ModelType.languageModel,
      );
    }
    return model;
  }

  @override
  EmbeddingModel embeddingModel(String modelId) {
    final model = _embeddingModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: ModelType.embeddingModel,
      );
    }
    return model;
  }

  @override
  ImageModel imageModel(String modelId) {
    final model = _imageModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: ModelType.imageModel,
      );
    }
    return model;
  }

  @override
  TranscriptionModel transcriptionModel(String modelId) {
    final model = _transcriptionModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: ModelType.transcriptionModel,
      );
    }
    return model;
  }

  @override
  SpeechModel speechModel(String modelId) {
    final model = _speechModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: ModelType.speechModel,
      );
    }
    return model;
  }

  @override
  VideoModel videoModel(String modelId) {
    final model = _videoModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: ModelType.videoModel,
      );
    }
    return model;
  }

  @override
  RerankingModel rerankingModel(String modelId) {
    final model = _rerankingModels[modelId];
    if (model == null) {
      throw NoSuchModelError(
        modelId: modelId,
        modelType: ModelType.rerankingModel,
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

void main() {
  group('Provider', () {
    test('exposes the v4 specification version', () {
      final Provider provider = FakeProvider(const {});

      expect(provider.specificationVersion, 'v4');
    });

    test('languageModel returns the registered model for a known id', () {
      final echo = EchoModel(provider: 'fake', modelId: 'echo-1');
      final provider = FakeProvider({'echo-1': echo});

      final model = provider.languageModel('echo-1');

      expect(model, same(echo));
      expect(model.modelId, 'echo-1');
      expect(model.provider, 'fake');
    });

    test('languageModel throws NoSuchModelError for an unknown id', () {
      final provider = FakeProvider(const {});

      expect(
        () => provider.languageModel('missing'),
        throwsA(
          isA<NoSuchModelError>()
              .having((e) => e.modelId, 'modelId', 'missing')
              .having(
                (e) => e.modelType,
                'modelType',
                ModelType.languageModel,
              ),
        ),
      );
    });

    test('NoSuchModelError is an AiError', () {
      final provider = FakeProvider(const {});

      expect(
        () => provider.languageModel('missing'),
        throwsA(isA<AiError>()),
      );
    });
  });

  group('Provider.embeddingModel', () {
    test('returns the registered embedding model for a known id', () {
      final fake = _FakeEmbeddingModel(provider: 'fake', modelId: 'emb-1');
      // 显式声明为 [Provider],确保调用走接口抽象成员而非 FakeProvider
      // 自身的方法——接口若缺该成员,此处直接编译失败。
      final Provider provider = FakeProvider(const {}, {'emb-1': fake});

      final model = provider.embeddingModel('emb-1');

      expect(model, same(fake));
      expect(model.modelId, 'emb-1');
      expect(model.provider, 'fake');
    });

    test('throws NoSuchModelError for an unknown id', () {
      final Provider provider = FakeProvider(const {});

      expect(
        () => provider.embeddingModel('missing'),
        throwsA(
          isA<NoSuchModelError>()
              .having((e) => e.modelId, 'modelId', 'missing')
              .having(
                (e) => e.modelType,
                'modelType',
                ModelType.embeddingModel,
              ),
        ),
      );
    });

    test('NoSuchModelError is an AiError', () {
      final Provider provider = FakeProvider(const {});

      expect(
        () => provider.embeddingModel('missing'),
        throwsA(isA<AiError>()),
      );
    });
  });

  group('Provider.imageModel', () {
    test('returns the registered image model for a known id', () {
      final fake = _FakeImageModel(
        provider: 'fake.image',
        modelId: 'image-1',
      );
      final Provider provider = FakeProvider(
        const {},
        const {},
        {'image-1': fake},
      );

      final model = provider.imageModel('image-1');

      expect(model, same(fake));
      expect(model.modelId, 'image-1');
      expect(model.provider, 'fake.image');
    });

    test('throws NoSuchModelError for an unknown id', () {
      final Provider provider = FakeProvider(const {});

      expect(
        () => provider.imageModel('missing'),
        throwsA(
          isA<NoSuchModelError>()
              .having((e) => e.modelId, 'modelId', 'missing')
              .having(
                (e) => e.modelType,
                'modelType',
                ModelType.imageModel,
              ),
        ),
      );
    });
  });

  group('Provider.transcriptionModel', () {
    test('returns the registered transcription model for a known id', () {
      final fake = _FakeTranscriptionModel(
        provider: 'fake.transcription',
        modelId: 'transcribe-1',
      );
      final Provider provider = FakeProvider(
        const {},
        const {},
        const {},
        {'transcribe-1': fake},
      );

      final model = provider.transcriptionModel('transcribe-1');

      expect(model, same(fake));
      expect(model.modelId, 'transcribe-1');
      expect(model.provider, 'fake.transcription');
    });

    test('throws NoSuchModelError for an unknown id', () {
      final Provider provider = FakeProvider(const {});

      expect(
        () => provider.transcriptionModel('missing'),
        throwsA(
          isA<NoSuchModelError>()
              .having((e) => e.modelId, 'modelId', 'missing')
              .having(
                (e) => e.modelType,
                'modelType',
                ModelType.transcriptionModel,
              ),
        ),
      );
    });
  });

  group('Provider.speechModel', () {
    test('returns the registered speech model for a known id', () {
      final fake = _FakeSpeechModel(
        provider: 'fake.speech',
        modelId: 'speech-1',
      );
      final Provider provider = FakeProvider(
        const {},
        const {},
        const {},
        const {},
        {'speech-1': fake},
      );

      final model = provider.speechModel('speech-1');

      expect(model, same(fake));
      expect(model.modelId, 'speech-1');
      expect(model.provider, 'fake.speech');
    });

    test('throws NoSuchModelError for an unknown id', () {
      final Provider provider = FakeProvider(const {});

      expect(
        () => provider.speechModel('missing'),
        throwsA(
          isA<NoSuchModelError>()
              .having((e) => e.modelId, 'modelId', 'missing')
              .having(
                (e) => e.modelType,
                'modelType',
                ModelType.speechModel,
              ),
        ),
      );
    });
  });

  group('Provider.videoModel', () {
    test('returns the registered video model for a known id', () {
      final fake = _FakeVideoModel(
        provider: 'fake.video',
        modelId: 'video-1',
      );
      final Provider provider = FakeProvider(
        const {},
        const {},
        const {},
        const {},
        const {},
        {'video-1': fake},
      );

      final model = provider.videoModel('video-1');

      expect(model, same(fake));
      expect(model.modelId, 'video-1');
      expect(model.provider, 'fake.video');
    });

    test('throws NoSuchModelError for an unknown id', () {
      final Provider provider = FakeProvider(const {});

      expect(
        () => provider.videoModel('missing'),
        throwsA(
          isA<NoSuchModelError>()
              .having((e) => e.modelId, 'modelId', 'missing')
              .having(
                (e) => e.modelType,
                'modelType',
                ModelType.videoModel,
              ),
        ),
      );
    });
  });

  group('Provider.rerankingModel', () {
    test('returns the registered reranking model for a known id', () {
      final fake = _FakeRerankingModel(provider: 'fake', modelId: 'rerank-1');
      final Provider provider = FakeProvider(
        const {},
        const {},
        const {},
        const {},
        const {},
        const {},
        null,
        null,
        {'rerank-1': fake},
      );

      final model = provider.rerankingModel('rerank-1');

      expect(model, same(fake));
      expect(model.modelId, 'rerank-1');
      expect(model.provider, 'fake');
    });

    test('throws NoSuchModelError for an unknown id', () {
      final Provider provider = FakeProvider(const {});

      expect(
        () => provider.rerankingModel('missing'),
        throwsA(
          isA<NoSuchModelError>()
              .having((e) => e.modelId, 'modelId', 'missing')
              .having(
                (e) => e.modelType,
                'modelType',
                ModelType.rerankingModel,
              ),
        ),
      );
    });
  });

  group('Provider.files', () {
    test('returns the provider files interface', () {
      final fake = _FakeFiles(provider: 'fake.files');
      final Provider provider = FakeProvider(
        const {},
        const {},
        const {},
        const {},
        const {},
        const {},
        fake,
      );

      final files = provider.files();

      expect(files, same(fake));
      expect(files.provider, 'fake.files');
      expect(files.specificationVersion, 'v4');
    });

    test('throws UnsupportedFunctionalityError when files are unsupported', () {
      final Provider provider = FakeProvider(const {});

      expect(
        provider.files,
        throwsA(
          isA<UnsupportedFunctionalityError>().having(
            (e) => e.functionality,
            'functionality',
            'files',
          ),
        ),
      );
    });
  });

  group('Provider.skills', () {
    test('returns the provider skills interface', () {
      final fake = _FakeSkills(provider: 'fake.skills');
      final Provider provider = FakeProvider(
        const {},
        const {},
        const {},
        const {},
        const {},
        const {},
        null,
        fake,
      );

      final skills = provider.skills();

      expect(skills, same(fake));
      expect(skills.provider, 'fake.skills');
      expect(skills.specificationVersion, 'v4');
    });

    test('throws UnsupportedFunctionalityError when skills are unsupported',
        () {
      final Provider provider = FakeProvider(const {});

      expect(
        provider.skills,
        throwsA(
          isA<UnsupportedFunctionalityError>().having(
            (e) => e.functionality,
            'functionality',
            'skills',
          ),
        ),
      );
    });
  });
}
