/// pigcode_ai 核心脊柱的公共入口。
///
/// 仅通过本 barrel 暴露公共 API:用户面消息层(`ModelMessage`/`Prompt`/
/// content part)、工具系统(`Tool`/`tool()`/`ToolSet`)、循环引擎的停止条件
/// 与 `StepResult`、流式分块 `TextStreamPart`、入口函数
/// `generateText`/`streamText`/`smoothStream`/`embed`/`embedMany`/
/// `generateImage`/`generateVideo`/`transcribe`/`rerank`/`uploadFile`/
/// `uploadSkill`、向量工具
/// `cosineSimilarity`,以及中间件包装工具和 provider registry 工具。
/// `lib/src/*` 为内部实现,外部代码不得直接 import。
///
/// 同时按 §3.5 命名策略 re-export pigcode_ai 公共 API 里出现的契约类型
/// (来自 `package:pigcode_ai_provider`);契约的输入侧 part/消息类型不在此
/// re-export 之列 —— 用户统一使用 pigcode_ai 自己的 `ModelMessage`/content part。
library;

export 'src/prompt/content_part.dart';
export 'src/prompt/model_message.dart';
export 'src/prompt/prompt.dart';
export 'src/ui/ui_message.dart';
export 'src/ui/convert_to_model_messages.dart';
export 'src/tool/tool.dart';
export 'src/agent/agent.dart';
export 'src/agent/tool_loop_agent.dart';
export 'src/generate_text/active_tools.dart';
export 'src/generate_text/context.dart';
export 'src/generate_text/tool_order.dart' show ToolOrder;
export 'src/generate_text/stop_condition.dart';
export 'src/generate_text/prune_messages.dart';
export 'src/generate_text/prepare_step.dart';
export 'src/generate_text/tool_approval.dart';
export 'src/generate_text/tool_call_repair.dart';
export 'src/generate_text/lifecycle_events.dart';
export 'src/generate_text/step_result.dart';
export 'src/generate_text/text_stream_part.dart';
export 'src/text_stream/to_text_stream.dart';
export 'src/ui_message_stream/ui_message_chunk.dart';
export 'src/ui_message_stream/to_ui_message_chunk.dart';
export 'src/ui_message_stream/to_ui_message_sse_stream.dart';
export 'src/ui_message_stream/to_ui_message_stream.dart';
export 'src/ui_message_stream/read_ui_message_stream.dart';
export 'src/generate_text/smooth_stream.dart';
export 'src/generate_text/output.dart' hide outputResponseFormat;
export 'src/generate_text/generate_text.dart';
export 'src/generate_text/stream_text.dart';
export 'src/generate_image/generate_image.dart';
export 'src/generate_video/generate_video.dart';
export 'src/generate_speech/generate_speech.dart';
export 'src/upload_file/upload_file.dart';
export 'src/upload_skill/upload_skill.dart';
export 'src/logger/log_warnings.dart';
export 'src/embed/embed.dart';
export 'src/embed/embed_many.dart';
export 'src/embed/cosine_similarity.dart';
export 'src/rerank/rerank.dart';
export 'src/transcribe/transcribe.dart';
export 'src/transcribe/stream_transcribe.dart';
export 'src/registry/custom_provider.dart';
export 'src/registry/provider_registry.dart';
export 'src/middleware/add_tool_input_examples_middleware.dart';
export 'src/middleware/default_embedding_settings_middleware.dart';
export 'src/middleware/default_settings_middleware.dart';
export 'src/middleware/extract_json_middleware.dart';
export 'src/middleware/extract_reasoning_middleware.dart';
export 'src/middleware/simulate_streaming_middleware.dart';
export 'src/middleware/wrap_embedding_model.dart';
export 'src/middleware/wrap_image_model.dart';
export 'src/middleware/wrap_language_model.dart';
export 'src/middleware/wrap_provider.dart';
export 'src/telemetry/telemetry.dart';
export 'src/telemetry/telemetry_events.dart';
export 'src/telemetry/telemetry_registry.dart';
export 'src/telemetry/telemetry_settings.dart';

export 'package:pigcode_ai_provider/pigcode_ai_provider.dart'
    show
        LanguageModel,
        Provider,
        LanguageModelContent,
        LanguageModelGenerateResult,
        LanguageModelStreamResult,
        LanguageModelStreamPart,
        LanguageModelCallOptions,
        ResponseFormat,
        ResponseFormatText,
        ResponseFormatJson,
        TextContent,
        ReasoningContent,
        SourceContent,
        SourceType,
        FileContent,
        ReasoningFileContent,
        OutputFileData,
        StreamStart,
        TextStart,
        TextDelta,
        TextEnd,
        ToolCall,
        ToolResult,
        ToolApprovalRequest,
        ToolChoice,
        ToolChoiceAuto,
        ToolChoiceNone,
        ToolChoiceRequired,
        ToolChoiceTool,
        ReasoningEffort,
        ToolResultOutput,
        ToolResultText,
        ToolResultJson,
        ToolResultExecutionDenied,
        ToolResultErrorText,
        ToolResultErrorJson,
        ToolResultContentOutput,
        ToolResultContentItem,
        ToolResultTextItem,
        ToolResultFileItem,
        ToolResultCustomItem,
        FileData,
        FileDataBytes,
        FileDataBase64,
        FileDataUrl,
        FileDataReference,
        FileDataText,
        JsonSchema,
        JsonObject,
        JsonValue,
        ProviderOptions,
        ProviderReference,
        CancellationSignal,
        CancellationController,
        LanguageModelMiddleware,
        LanguageModelUsage,
        InputTokens,
        OutputTokens,
        LanguageModelFinishReason,
        FinishReasonType,
        RequestInfo,
        ResponseInfo,
        Warning,
        UnsupportedWarning,
        CompatibilityWarning,
        DeprecatedWarning,
        OtherWarning,
        Embedding,
        EmbeddingModel,
        EmbeddingModelCallOptions,
        EmbeddingModelResult,
        EmbeddingUsage,
        EmbeddingResponseInfo,
        EmbeddingModelMiddleware,
        EmbeddingModelDoEmbed,
        RerankingModel,
        RerankingDocuments,
        RerankingDocumentsText,
        RerankingDocumentsObject,
        RerankingModelCallOptions,
        RerankingModelRanking,
        RerankingModelResult,
        ImageModel,
        ImageModelCallOptions,
        ImageModelFile,
        ImageModelFileBytes,
        ImageModelFileBase64,
        ImageModelFileUrl,
        ImageModelResult,
        ImageModelUsage,
        ImageModelMiddleware,
        ImageModelDoGenerate,
        VideoModel,
        VideoModelCallOptions,
        VideoModelFile,
        VideoModelFileBytes,
        VideoModelFileBase64,
        VideoModelFileUrl,
        VideoFrameType,
        VideoFrameImage,
        VideoModelResult,
        VideoModelVideoData,
        VideoModelVideoDataBytes,
        VideoModelVideoDataBase64,
        VideoModelVideoDataUrl,
        TranscriptionModel,
        TranscriptionModelCallOptions,
        TranscriptionModelResult,
        StreamableTranscriptionModel,
        TranscriptionInputAudioFormat,
        TranscriptionModelStreamOptions,
        TranscriptionModelStreamResult,
        TranscriptionModelStreamPart,
        TranscriptionStreamStart,
        TranscriptionDelta,
        TranscriptionPartial,
        TranscriptionFinal,
        TranscriptionResponseMetadata,
        TranscriptionFinish,
        TranscriptionRaw,
        TranscriptionStreamError,
        TranscriptionSegment,
        TranscriptionAudio,
        TranscriptionAudioBytes,
        TranscriptionAudioBase64,
        SpeechModel,
        SpeechModelCallOptions,
        SpeechModelResult,
        Files,
        FilesUploadOptions,
        FilesUploadResult,
        Skills,
        SkillFile,
        SkillsUploadOptions,
        SkillsUploadResult,
        FunctionTool,
        AiError,
        ModelType,
        ApiCallError,
        NoSuchModelError,
        NoSuchProviderError,
        NoSuchProviderReferenceError,
        TooManyEmbeddingValuesForCallError,
        InvalidPromptError,
        UnsupportedFunctionalityError,
        InvalidArgumentError,
        InvalidResponseDataError,
        JsonParseError,
        TypeValidationError,
        NoOutputGeneratedError,
        NoObjectGeneratedError,
        NoImageGeneratedError,
        NoVideoGeneratedError,
        NoTranscriptGeneratedError,
        NoSpeechGeneratedError,
        NoContentGeneratedError,
        EmptyResponseBodyError,
        LoadApiKeyError,
        LoadSettingError;
