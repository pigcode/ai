/// pigcode AI SDK 的 OpenAI 兼容第三方服务基础实现层。
///
/// 提供 `createOpenAiCompatible` 工厂与 `OpenAiCompatibleProvider`,只建在
/// `pigcode_ai_provider` 契约与 `pigcode_ai_provider_utils` 共享工具之上(不依赖
/// `pigcode_ai_openai`),实现 Chat Completions(`/chat/completions`)一套 wire
/// 的 `LanguageModel` 与 Embeddings(`/embeddings`)一套 wire 的
/// `EmbeddingModel`。全部关键行为(错误体结构、usage 转换、请求体变换、
/// 元数据提取等)均为可插拔扩展点,专为下游二次封装第三方 OpenAI 兼容服务
/// 设计(v7 生态的 fireworks/togetherai 组合模式;cerebras 的继承模式在
/// 本包经 config 参数化覆盖,模型类保持 final)。
///
/// 仅通过本 barrel 暴露公共 API;`lib/src/*` 为内部实现,外部代码不得
/// 直接 import。除工厂函数外,直接导出语言模型实现类与配置类型
/// (`OpenAiCompatibleChatLanguageModel`/`OpenAiCompatibleChatConfig` 等),
/// 供下游包**组合**复用(下游工厂 new 本类并注入自己的 config)。
library;

export 'src/chat/chat_language_model.dart';
export 'src/chat/chat_options.dart';
export 'src/chat/convert_messages.dart';
export 'src/chat/convert_usage.dart';
export 'src/chat/map_finish_reason.dart';
export 'src/chat/prepare_tools.dart';
export 'src/chat/response_metadata.dart';
export 'src/embedding/embedding_config.dart';
export 'src/embedding/embedding_model.dart';
export 'src/embedding/embedding_options.dart';
export 'src/internal/error_structure.dart';
export 'src/provider/openai_compatible_provider.dart';
export 'src/utils/metadata_extractor.dart';
