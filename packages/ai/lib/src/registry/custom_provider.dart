import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

/// 用一组显式模型/API 实例创建一个 [provider.Provider]。
///
/// 未配置的模型入口会委托给 [fallbackProvider]；若没有 fallback，则抛出
/// [provider.NoSuchModelError]。`files`/`skills` 同理，缺省且无 fallback 时
/// 抛出 [provider.UnsupportedFunctionalityError]。
provider.Provider customProvider({
  Map<String, provider.LanguageModel> languageModels = const {},
  Map<String, provider.EmbeddingModel> embeddingModels = const {},
  Map<String, provider.ImageModel> imageModels = const {},
  Map<String, provider.TranscriptionModel> transcriptionModels = const {},
  Map<String, provider.SpeechModel> speechModels = const {},
  Map<String, provider.VideoModel> videoModels = const {},
  Map<String, provider.RerankingModel> rerankingModels = const {},
  provider.Files? files,
  provider.Skills? skills,
  provider.Provider? fallbackProvider,
}) {
  return _CustomProvider(
    languageModels: languageModels,
    embeddingModels: embeddingModels,
    imageModels: imageModels,
    transcriptionModels: transcriptionModels,
    speechModels: speechModels,
    videoModels: videoModels,
    rerankingModels: rerankingModels,
    files: files,
    skills: skills,
    fallbackProvider: fallbackProvider,
  );
}

final class _CustomProvider implements provider.Provider {
  const _CustomProvider({
    required this.languageModels,
    required this.embeddingModels,
    required this.imageModels,
    required this.transcriptionModels,
    required this.speechModels,
    required this.videoModels,
    required this.rerankingModels,
    required provider.Files? files,
    required provider.Skills? skills,
    required provider.Provider? fallbackProvider,
  })  : _files = files,
        _skills = skills,
        _fallbackProvider = fallbackProvider;

  final Map<String, provider.LanguageModel> languageModels;
  final Map<String, provider.EmbeddingModel> embeddingModels;
  final Map<String, provider.ImageModel> imageModels;
  final Map<String, provider.TranscriptionModel> transcriptionModels;
  final Map<String, provider.SpeechModel> speechModels;
  final Map<String, provider.VideoModel> videoModels;
  final Map<String, provider.RerankingModel> rerankingModels;
  final provider.Files? _files;
  final provider.Skills? _skills;
  final provider.Provider? _fallbackProvider;

  @override
  String get specificationVersion => provider.providerSpecVersion;

  @override
  provider.LanguageModel languageModel(String modelId) {
    final model = languageModels[modelId];
    if (model != null) {
      return model;
    }
    final fallback = _fallbackProvider;
    if (fallback != null) {
      return fallback.languageModel(modelId);
    }
    throw provider.NoSuchModelError(
      modelId: modelId,
      modelType: provider.ModelType.languageModel,
    );
  }

  @override
  provider.EmbeddingModel embeddingModel(String modelId) {
    final model = embeddingModels[modelId];
    if (model != null) {
      return model;
    }
    final fallback = _fallbackProvider;
    if (fallback != null) {
      return fallback.embeddingModel(modelId);
    }
    throw provider.NoSuchModelError(
      modelId: modelId,
      modelType: provider.ModelType.embeddingModel,
    );
  }

  @override
  provider.ImageModel imageModel(String modelId) {
    final model = imageModels[modelId];
    if (model != null) {
      return model;
    }
    final fallback = _fallbackProvider;
    if (fallback != null) {
      return fallback.imageModel(modelId);
    }
    throw provider.NoSuchModelError(
      modelId: modelId,
      modelType: provider.ModelType.imageModel,
    );
  }

  @override
  provider.TranscriptionModel transcriptionModel(String modelId) {
    final model = transcriptionModels[modelId];
    if (model != null) {
      return model;
    }
    final fallback = _fallbackProvider;
    if (fallback != null) {
      return fallback.transcriptionModel(modelId);
    }
    throw provider.NoSuchModelError(
      modelId: modelId,
      modelType: provider.ModelType.transcriptionModel,
    );
  }

  @override
  provider.SpeechModel speechModel(String modelId) {
    final model = speechModels[modelId];
    if (model != null) {
      return model;
    }
    final fallback = _fallbackProvider;
    if (fallback != null) {
      return fallback.speechModel(modelId);
    }
    throw provider.NoSuchModelError(
      modelId: modelId,
      modelType: provider.ModelType.speechModel,
    );
  }

  @override
  provider.VideoModel videoModel(String modelId) {
    final model = videoModels[modelId];
    if (model != null) {
      return model;
    }
    final fallback = _fallbackProvider;
    if (fallback != null) {
      return fallback.videoModel(modelId);
    }
    throw provider.NoSuchModelError(
      modelId: modelId,
      modelType: provider.ModelType.videoModel,
    );
  }

  @override
  provider.RerankingModel rerankingModel(String modelId) {
    final model = rerankingModels[modelId];
    if (model != null) {
      return model;
    }
    final fallback = _fallbackProvider;
    if (fallback != null) {
      return fallback.rerankingModel(modelId);
    }
    throw provider.NoSuchModelError(
      modelId: modelId,
      modelType: provider.ModelType.rerankingModel,
    );
  }

  @override
  provider.Files files() {
    final files = _files;
    if (files != null) {
      return files;
    }
    final fallback = _fallbackProvider;
    if (fallback != null) {
      return fallback.files();
    }
    throw const provider.UnsupportedFunctionalityError(
      functionality: 'files',
    );
  }

  @override
  provider.Skills skills() {
    final skills = _skills;
    if (skills != null) {
      return skills;
    }
    final fallback = _fallbackProvider;
    if (fallback != null) {
      return fallback.skills();
    }
    throw const provider.UnsupportedFunctionalityError(
      functionality: 'skills',
    );
  }
}
