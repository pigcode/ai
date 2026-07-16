import '../embedding_model/embedding_model.dart';
import '../files/files.dart';
import '../image_model/image_model.dart';
import '../language_model/language_model.dart';
import '../reranking_model/reranking_model.dart';
import '../skills/skills.dart';
import '../speech_model/speech_model.dart';
import '../transcription_model/transcription_model.dart';
import '../video_model/video_model.dart';

/// provider 规范版本。
const providerSpecVersion = 'v4';

/// provider 入口:按 id 解析出语言模型或 embedding 模型的实现。
///
/// provider 是"某家服务 / 某套 wire 协议"的注册表:上层用中性的 `modelId`
/// 向它索要一个满足对应契约的模型,而无需知道底层是哪家、走哪套协议。
/// 本期暴露语言模型、embedding、image、transcription、speech、video 与 reranking 入口。
abstract interface class Provider {
  /// provider 规范版本。
  String get specificationVersion;

  /// 按 [modelId] 解析出一个语言模型实现。
  ///
  /// 命中已知 id 时返回对应的 [LanguageModel];遇到未知 id 时**抛出**
  /// [NoSuchModelError](`modelType: ModelType.languageModel`)。这是唯一
  /// 允许抛异常的路径——因为"这个 id 根本不存在"是调用方用法错误(契约被
  /// 违反),而非"模型这一轮的结果",故不走"错误即事件"。
  LanguageModel languageModel(String modelId);

  /// 按 [modelId] 解析出一个文本 embedding 模型实现。
  ///
  /// 命中已知 id 时返回对应的 [EmbeddingModel];遇到未知 id 时**抛出**
  /// [NoSuchModelError](`modelType: ModelType.embeddingModel`)——与
  /// [languageModel] 同一条"调用方用法错误即抛异常"的规则,理由同上。
  EmbeddingModel embeddingModel(String modelId);

  /// 按 [modelId] 解析出一个 image 模型实现。
  ///
  /// 命中已知 id 时返回对应的 [ImageModel];遇到未知 id 时**抛出**
  /// [NoSuchModelError](`modelType: ModelType.imageModel`)。
  ImageModel imageModel(String modelId);

  /// 按 [modelId] 解析出一个 transcription 模型实现。
  ///
  /// 命中已知 id 时返回对应的 [TranscriptionModel];遇到未知 id 时**抛出**
  /// [NoSuchModelError](`modelType: ModelType.transcriptionModel`)。
  TranscriptionModel transcriptionModel(String modelId);

  /// 按 [modelId] 解析出一个 speech 模型实现。
  ///
  /// 命中已知 id 时返回对应的 [SpeechModel];遇到未知 id 时**抛出**
  /// [NoSuchModelError](`modelType: ModelType.speechModel`)。
  SpeechModel speechModel(String modelId);

  /// 按 [modelId] 解析出一个 video 模型实现。
  ///
  /// 命中已知 id 时返回对应的 [VideoModel];遇到未知 id 时**抛出**
  /// [NoSuchModelError](`modelType: ModelType.videoModel`)。
  VideoModel videoModel(String modelId);

  /// 按 [modelId] 解析出一个 reranking 模型实现。
  ///
  /// 命中已知 id 时返回对应的 [RerankingModel];遇到未知 id 时**抛出**
  /// [NoSuchModelError](`modelType: ModelType.rerankingModel`)。
  RerankingModel rerankingModel(String modelId);

  /// 返回 provider 的文件上传接口。
  ///
  /// provider 不支持文件上传时抛出 [UnsupportedFunctionalityError]。
  Files files();

  /// 返回 provider 的 skill 上传接口。
  ///
  /// provider 不支持 skill 上传时抛出 [UnsupportedFunctionalityError]。
  Skills skills();
}
