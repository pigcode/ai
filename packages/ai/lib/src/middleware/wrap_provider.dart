import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import 'wrap_embedding_model.dart';
import 'wrap_image_model.dart';
import 'wrap_language_model.dart';

/// 用中间件包装一个 [provider.Provider]。
///
/// 本项目当前 provider 契约包含 language/embedding/image/transcription/speech/
/// video/reranking 以及 files/skills 入口。language/embedding/image 可按需套
/// middleware;其它入口暂无 middleware,因此透明委托。
provider.Provider wrapProvider({
  required provider.Provider provider,
  provider.LanguageModelMiddleware? languageModelMiddleware,
  provider.EmbeddingModelMiddleware? embeddingModelMiddleware,
  provider.ImageModelMiddleware? imageModelMiddleware,
}) {
  return _WrappedProvider(
    provider,
    languageModelMiddleware: languageModelMiddleware,
    embeddingModelMiddleware: embeddingModelMiddleware,
    imageModelMiddleware: imageModelMiddleware,
  );
}

final class _WrappedProvider implements provider.Provider {
  const _WrappedProvider(
    this._provider, {
    required provider.LanguageModelMiddleware? languageModelMiddleware,
    required provider.EmbeddingModelMiddleware? embeddingModelMiddleware,
    required provider.ImageModelMiddleware? imageModelMiddleware,
  })  : _languageModelMiddleware = languageModelMiddleware,
        _embeddingModelMiddleware = embeddingModelMiddleware,
        _imageModelMiddleware = imageModelMiddleware;

  final provider.Provider _provider;
  final provider.LanguageModelMiddleware? _languageModelMiddleware;
  final provider.EmbeddingModelMiddleware? _embeddingModelMiddleware;
  final provider.ImageModelMiddleware? _imageModelMiddleware;

  @override
  String get specificationVersion => provider.providerSpecVersion;

  @override
  provider.LanguageModel languageModel(String modelId) {
    final model = _provider.languageModel(modelId);
    final middleware = _languageModelMiddleware;
    if (middleware == null) {
      return model;
    }
    return wrapLanguageModel(model, middleware);
  }

  @override
  provider.EmbeddingModel embeddingModel(String modelId) {
    final model = _provider.embeddingModel(modelId);
    final middleware = _embeddingModelMiddleware;
    if (middleware == null) {
      return model;
    }
    return wrapEmbeddingModel(model, middleware);
  }

  @override
  provider.ImageModel imageModel(String modelId) {
    final model = _provider.imageModel(modelId);
    final middleware = _imageModelMiddleware;
    if (middleware == null) {
      return model;
    }
    return wrapImageModel(model, middleware);
  }

  @override
  provider.TranscriptionModel transcriptionModel(String modelId) =>
      _provider.transcriptionModel(modelId);

  @override
  provider.SpeechModel speechModel(String modelId) =>
      _provider.speechModel(modelId);

  @override
  provider.VideoModel videoModel(String modelId) =>
      _provider.videoModel(modelId);

  @override
  provider.RerankingModel rerankingModel(String modelId) =>
      _provider.rerankingModel(modelId);

  @override
  provider.Files files() => _provider.files();

  @override
  provider.Skills skills() => _provider.skills();
}
