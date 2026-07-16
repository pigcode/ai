import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

/// 多 provider 注册表：通过 `providerId:modelId` 形式解析模型。
abstract interface class ProviderRegistry {
  /// registry 规范版本。
  String get specificationVersion;

  /// 按组合 id 解析语言模型。
  provider.LanguageModel languageModel(String id);

  /// 按组合 id 解析 embedding 模型。
  provider.EmbeddingModel embeddingModel(String id);

  /// 按组合 id 解析 image 模型。
  provider.ImageModel imageModel(String id);

  /// 按组合 id 解析 transcription 模型。
  provider.TranscriptionModel transcriptionModel(String id);

  /// 按组合 id 解析 speech 模型。
  provider.SpeechModel speechModel(String id);

  /// 按组合 id 解析 video 模型。
  provider.VideoModel videoModel(String id);

  /// 按组合 id 解析 reranking 模型。
  provider.RerankingModel rerankingModel(String id);

  /// 按 provider id 解析文件上传接口。
  provider.Files files(String providerId);

  /// 按 provider id 解析 skill 上传接口。
  provider.Skills skills(String providerId);
}

/// 创建一个 provider registry。
///
/// 模型 id 默认使用 `providerId:modelId` 格式；[separator] 可改为其它分隔符。
/// 只按第一个分隔符切分，因此 provider 内部的 modelId 可以继续包含分隔符。
/// [separator] 不能为空。
ProviderRegistry createProviderRegistry(
  Map<String, provider.Provider> providers, {
  String separator = ':',
}) {
  if (separator.isEmpty) {
    throw ArgumentError.value(separator, 'separator', 'must not be empty');
  }
  return _DefaultProviderRegistry(providers, separator: separator);
}

final class _DefaultProviderRegistry implements ProviderRegistry {
  const _DefaultProviderRegistry(
    this._providers, {
    required String separator,
  }) : _separator = separator;

  final Map<String, provider.Provider> _providers;
  final String _separator;

  @override
  String get specificationVersion => provider.providerSpecVersion;

  @override
  provider.LanguageModel languageModel(String id) {
    final parts = _splitId(id, provider.ModelType.languageModel);
    return _getProvider(parts.providerId, provider.ModelType.languageModel)
        .languageModel(parts.modelId);
  }

  @override
  provider.EmbeddingModel embeddingModel(String id) {
    final parts = _splitId(id, provider.ModelType.embeddingModel);
    return _getProvider(parts.providerId, provider.ModelType.embeddingModel)
        .embeddingModel(parts.modelId);
  }

  @override
  provider.ImageModel imageModel(String id) {
    final parts = _splitId(id, provider.ModelType.imageModel);
    return _getProvider(parts.providerId, provider.ModelType.imageModel)
        .imageModel(parts.modelId);
  }

  @override
  provider.TranscriptionModel transcriptionModel(String id) {
    final parts = _splitId(id, provider.ModelType.transcriptionModel);
    return _getProvider(parts.providerId, provider.ModelType.transcriptionModel)
        .transcriptionModel(parts.modelId);
  }

  @override
  provider.SpeechModel speechModel(String id) {
    final parts = _splitId(id, provider.ModelType.speechModel);
    return _getProvider(parts.providerId, provider.ModelType.speechModel)
        .speechModel(parts.modelId);
  }

  @override
  provider.VideoModel videoModel(String id) {
    final parts = _splitId(id, provider.ModelType.videoModel);
    return _getProvider(parts.providerId, provider.ModelType.videoModel)
        .videoModel(parts.modelId);
  }

  @override
  provider.RerankingModel rerankingModel(String id) {
    final parts = _splitId(id, provider.ModelType.rerankingModel);
    return _getProvider(parts.providerId, provider.ModelType.rerankingModel)
        .rerankingModel(parts.modelId);
  }

  @override
  provider.Files files(String providerId) {
    return _getProvider(providerId, provider.ModelType.languageModel).files();
  }

  @override
  provider.Skills skills(String providerId) {
    return _getProvider(providerId, provider.ModelType.languageModel).skills();
  }

  _RegistryIdParts _splitId(String id, provider.ModelType modelType) {
    final index = id.indexOf(_separator);
    if (index == -1) {
      throw provider.NoSuchModelError(
        modelId: id,
        modelType: modelType,
        message: 'Invalid ${modelType.name} id for registry: $id '
            '(must be in the format "providerId${_separator}modelId")',
      );
    }
    return _RegistryIdParts(
      providerId: id.substring(0, index),
      modelId: id.substring(index + _separator.length),
    );
  }

  provider.Provider _getProvider(
    String providerId,
    provider.ModelType modelType,
  ) {
    final providerValue = _providers[providerId];
    if (providerValue != null) {
      return providerValue;
    }
    throw provider.NoSuchProviderError(
      modelId: providerId,
      modelType: modelType,
      providerId: providerId,
      availableProviders: _providers.keys.toList(growable: false),
    );
  }
}

final class _RegistryIdParts {
  const _RegistryIdParts({
    required this.providerId,
    required this.modelId,
  });

  final String providerId;
  final String modelId;
}
