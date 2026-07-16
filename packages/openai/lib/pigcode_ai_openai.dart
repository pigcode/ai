/// pigcode AI SDK 的 OpenAI 官方 provider 包。
///
/// 提供 `createOpenAi` 工厂与 `OpenAiProvider`,建在 `pigcode_ai_provider`
/// 契约与 `pigcode_ai_provider_utils` 共享工具之上,实现 Chat Completions
/// (`/chat/completions`)与 Responses(`/responses`)两套 wire 的
/// `LanguageModel`,Embeddings(`/embeddings`)的 `EmbeddingModel`,
/// Images(`/images/generations`)的 `ImageModel`,
/// Audio Transcriptions(`/audio/transcriptions`)的 `TranscriptionModel`,
/// Audio Speech(`/audio/speech`)的 `SpeechModel`,以及 Files(`/files`)和
/// Skills(`/skills`)上传接口。
///
/// 仅通过本 barrel 暴露公共 API;`lib/src/*` 为内部实现,外部代码不得
/// 直接 import。下方 export 列出当前对外公开的完整面:chat/responses
/// 两套 wire 的语言模型实现及其请求构造/wire 转换辅助、embedding 与
/// image/transcription/speech 模型实现、`OpenAiProvider` 工厂与配置、共享的能力表与错误类型。
library;

export 'src/chat/chat_language_model.dart';
export 'src/chat/chat_options.dart';
export 'src/chat/convert_messages.dart';
export 'src/chat/convert_usage.dart';
export 'src/chat/map_finish_reason.dart';
export 'src/chat/prepare_tools.dart';
export 'src/chat/response_metadata.dart';
export 'src/embedding/embedding_model.dart';
export 'src/embedding/embedding_options.dart';
export 'src/files/files.dart';
export 'src/files/files_options.dart';
export 'src/image/image_model.dart';
export 'src/image/image_options.dart';
export 'src/internal/capabilities.dart';
export 'src/internal/config.dart';
export 'src/internal/error.dart';
export 'src/internal/stream_error_probe.dart';
export 'src/provider/openai_provider.dart';
export 'src/responses/convert_input.dart';
export 'src/responses/convert_usage.dart';
export 'src/responses/map_finish_reason.dart';
export 'src/responses/prepare_tools.dart';
export 'src/responses/responses_language_model.dart';
export 'src/responses/responses_options.dart';
export 'src/skills/skills.dart';
export 'src/speech/speech_model.dart';
export 'src/speech/speech_options.dart';
export 'src/tool/openai_tools.dart';
export 'src/transcription/transcription_model.dart';
export 'src/transcription/transcription_options.dart';
