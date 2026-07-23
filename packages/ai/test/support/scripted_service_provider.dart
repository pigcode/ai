import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;

/// Public-contract service peer used by the AI Core compatibility lanes.
final class ScriptedServiceProvider implements contracts.Provider {
  ScriptedServiceProvider()
      : embedding = ScriptedServiceEmbeddingModel(),
        image = ScriptedServiceImageModel(),
        video = ScriptedServiceVideoModel(),
        speech = ScriptedServiceSpeechModel(),
        transcription = ScriptedServiceTranscriptionModel(),
        reranking = ScriptedServiceRerankingModel(),
        fileApi = ScriptedServiceFiles(),
        skillApi = ScriptedServiceSkills();

  final ScriptedServiceEmbeddingModel embedding;
  final ScriptedServiceImageModel image;
  final ScriptedServiceVideoModel video;
  final ScriptedServiceSpeechModel speech;
  final ScriptedServiceTranscriptionModel transcription;
  final ScriptedServiceRerankingModel reranking;
  final ScriptedServiceFiles fileApi;
  final ScriptedServiceSkills skillApi;

  @override
  String get specificationVersion => contracts.providerSpecVersion;

  @override
  contracts.LanguageModel languageModel(String modelId) =>
      throw contracts.NoSuchModelError(
        modelId: modelId,
        modelType: contracts.ModelType.languageModel,
      );

  @override
  contracts.EmbeddingModel embeddingModel(String modelId) => embedding;

  @override
  contracts.ImageModel imageModel(String modelId) => image;

  @override
  contracts.VideoModel videoModel(String modelId) => video;

  @override
  contracts.TranscriptionModel transcriptionModel(String modelId) =>
      transcription;

  @override
  contracts.SpeechModel speechModel(String modelId) => speech;

  @override
  contracts.RerankingModel rerankingModel(String modelId) => reranking;

  @override
  contracts.Files files() => fileApi;

  @override
  contracts.Skills skills() => skillApi;
}

final class ScriptedServiceEmbeddingModel implements contracts.EmbeddingModel {
  int callCount = 0;
  final List<contracts.EmbeddingModelCallOptions> calls =
      <contracts.EmbeddingModelCallOptions>[];

  @override
  String get specificationVersion => contracts.embeddingModelSpecVersion;

  @override
  String get provider => 'scripted.services.embedding';

  @override
  String get modelId => 'embedding';

  @override
  int? get maxEmbeddingsPerCall => 1;

  @override
  bool get supportsParallelCalls => false;

  @override
  Future<contracts.EmbeddingModelResult> doEmbed(
    contracts.EmbeddingModelCallOptions options,
  ) async {
    calls.add(options);
    callCount++;
    return contracts.EmbeddingModelResult(
      embeddings: <contracts.Embedding>[
        for (final value in options.values)
          <double>[value.length.toDouble(), callCount.toDouble()],
      ],
      usage: contracts.EmbeddingUsage(tokens: options.values.length),
      warnings: <contracts.Warning>[
        contracts.OtherWarning('embedding-$callCount'),
      ],
      providerMetadata: <String, contracts.JsonObject>{
        'scripted': <String, Object?>{'batch': callCount},
      },
    );
  }
}

final class ScriptedServiceRerankingModel implements contracts.RerankingModel {
  contracts.RerankingModelCallOptions? lastOptions;

  @override
  String get specificationVersion => contracts.rerankingModelSpecVersion;

  @override
  String get provider => 'scripted.services.reranking';

  @override
  String get modelId => 'reranking';

  @override
  Future<contracts.RerankingModelResult> doRerank(
    contracts.RerankingModelCallOptions options,
  ) async {
    lastOptions = options;
    final length = switch (options.documents) {
      contracts.RerankingDocumentsText(:final values) => values.length,
      contracts.RerankingDocumentsObject(:final values) => values.length,
    };
    return contracts.RerankingModelResult(
      ranking: <contracts.RerankingModelRanking>[
        for (var index = length - 1; index >= 0; index--)
          contracts.RerankingModelRanking(
            index: index,
            relevanceScore: (index + 1) / length,
          ),
      ],
      warnings: const <contracts.Warning>[
        contracts.OtherWarning('reranking'),
      ],
      providerMetadata: const <String, contracts.JsonObject>{
        'scripted': <String, Object?>{'kind': 'reranking'},
      },
      response: const contracts.ResponseInfo(modelId: 'reranking'),
    );
  }
}

final class ScriptedServiceImageModel implements contracts.ImageModel {
  int callCount = 0;
  final List<contracts.ImageModelCallOptions> calls =
      <contracts.ImageModelCallOptions>[];

  @override
  String get specificationVersion => contracts.imageModelSpecVersion;

  @override
  String get provider => 'scripted.services.image';

  @override
  String get modelId => 'image';

  @override
  int? get maxImagesPerCall => 1;

  @override
  Future<contracts.ImageModelResult> doGenerate(
    contracts.ImageModelCallOptions options,
  ) async {
    calls.add(options);
    callCount++;
    return contracts.ImageModelResult(
      images: <Uint8List>[
        for (var index = 0; index < options.n; index++)
          Uint8List.fromList(<int>[callCount, index]),
      ],
      usage: contracts.ImageModelUsage(
        inputTokens: callCount,
        outputTokens: callCount * 2,
        totalTokens: callCount * 3,
      ),
      warnings: <contracts.Warning>[
        contracts.OtherWarning('image-$callCount'),
      ],
      providerMetadata: <String, contracts.JsonObject>{
        'scripted': <String, Object?>{'image$callCount': options.n},
      },
      response: contracts.ResponseInfo(modelId: 'image-$callCount'),
    );
  }
}

final class ScriptedServiceVideoModel implements contracts.VideoModel {
  int callCount = 0;
  final List<contracts.VideoModelCallOptions> calls =
      <contracts.VideoModelCallOptions>[];

  @override
  String get specificationVersion => contracts.videoModelSpecVersion;

  @override
  String get provider => 'scripted.services.video';

  @override
  String get modelId => 'video';

  @override
  int? get maxVideosPerCall => 1;

  @override
  Future<contracts.VideoModelResult> doGenerate(
    contracts.VideoModelCallOptions options,
  ) async {
    calls.add(options);
    callCount++;
    return contracts.VideoModelResult(
      videos: <contracts.VideoModelVideoData>[
        for (var index = 0; index < options.n; index++)
          contracts.VideoModelVideoDataBytes(
            Uint8List.fromList(<int>[callCount, index]),
            mediaType: 'video/mp4',
          ),
      ],
      warnings: <contracts.Warning>[
        contracts.OtherWarning('video-$callCount'),
      ],
      providerMetadata: <String, contracts.JsonObject>{
        'scripted': <String, Object?>{'video$callCount': options.n},
      },
      response: contracts.ResponseInfo(modelId: 'video-$callCount'),
    );
  }
}

final class ScriptedServiceSpeechModel implements contracts.SpeechModel {
  contracts.SpeechModelCallOptions? lastOptions;

  @override
  String get specificationVersion => contracts.speechModelSpecVersion;

  @override
  String get provider => 'scripted.services.speech';

  @override
  String get modelId => 'speech';

  @override
  Future<contracts.SpeechModelResult> doGenerate(
    contracts.SpeechModelCallOptions options,
  ) async {
    lastOptions = options;
    return contracts.SpeechModelResult(
      audio: Uint8List.fromList(<int>[1, 2, 3]),
      warnings: const <contracts.Warning>[
        contracts.OtherWarning('speech'),
      ],
      providerMetadata: const <String, contracts.JsonObject>{
        'scripted': <String, Object?>{'kind': 'speech'},
      },
      response: const contracts.ResponseInfo(
        modelId: 'speech',
        headers: <String, String>{'content-type': 'audio/wav'},
      ),
    );
  }
}

final class ScriptedServiceTranscriptionModel
    implements contracts.TranscriptionModel {
  contracts.TranscriptionModelCallOptions? lastOptions;

  @override
  String get specificationVersion => contracts.transcriptionModelSpecVersion;

  @override
  String get provider => 'scripted.services.transcription';

  @override
  String get modelId => 'transcription';

  @override
  Future<contracts.TranscriptionModelResult> doGenerate(
    contracts.TranscriptionModelCallOptions options,
  ) async {
    lastOptions = options;
    return const contracts.TranscriptionModelResult(
      text: 'scripted transcript',
      segments: <contracts.TranscriptionSegment>[
        contracts.TranscriptionSegment(
          text: 'scripted transcript',
          startSecond: 0,
          endSecond: 1,
        ),
      ],
      language: 'en',
      durationInSeconds: 1,
      warnings: <contracts.Warning>[
        contracts.OtherWarning('transcription'),
      ],
      providerMetadata: <String, contracts.JsonObject>{
        'scripted': <String, Object?>{'kind': 'transcription'},
      },
      response: contracts.ResponseInfo(modelId: 'transcription'),
    );
  }
}

final class ScriptedServiceFiles implements contracts.Files {
  final List<contracts.FilesUploadOptions> calls =
      <contracts.FilesUploadOptions>[];

  @override
  String get specificationVersion => contracts.filesSpecVersion;

  @override
  String get provider => 'scripted.services.files';

  @override
  Future<contracts.FilesUploadResult> uploadFile(
    contracts.FilesUploadOptions options,
  ) async {
    calls.add(options);
    return contracts.FilesUploadResult(
      providerReference: const <String, String>{'scripted': 'file-1'},
      mediaType: options.mediaType,
      filename: options.filename,
      warnings: const <contracts.Warning>[
        contracts.OtherWarning('file'),
      ],
    );
  }
}

final class ScriptedServiceSkills implements contracts.Skills {
  final List<contracts.SkillsUploadOptions> calls =
      <contracts.SkillsUploadOptions>[];

  @override
  String get specificationVersion => contracts.skillsSpecVersion;

  @override
  String get provider => 'scripted.services.skills';

  @override
  Future<contracts.SkillsUploadResult> uploadSkill(
    contracts.SkillsUploadOptions options,
  ) async {
    calls.add(options);
    return contracts.SkillsUploadResult(
      providerReference: const <String, String>{'scripted': 'skill-1'},
      displayTitle: options.displayTitle,
      name: 'scripted-skill',
      latestVersion: 'v1',
      warnings: const <contracts.Warning>[
        contracts.OtherWarning('skill'),
      ],
    );
  }
}
