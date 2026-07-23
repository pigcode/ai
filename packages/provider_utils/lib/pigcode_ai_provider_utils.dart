/// pigcode_ai_provider_utils 的公共入口。
///
/// 支撑各 provider 包(如 `pigcode_ai_openai`)chat/completion 主链路所需的
/// 共享工具:HTTP POST JSON/multipart(一次性 + 流式)、响应处理策略、SSE 帧解析、
/// JSON 解析与 JSON Schema 结构校验、流式工具调用增量拼接、媒体类型嗅探,
/// 以及 id 生成、baseURL 规整、设置加载、可取消 delay 等小件。
///
/// 仅通过本 barrel 暴露公共 API;`lib/src/*` 为内部实现,外部代码不得
/// 直接 import。
library;

export 'src/async.dart';
export 'src/http/http.dart';
export 'src/http/multipart.dart';
export 'src/http/response_handler.dart';
export 'src/http/sse.dart';
export 'src/http/url_security.dart';
export 'src/ids.dart';
export 'src/json/json.dart';
export 'src/media.dart';
export 'src/provider_reference.dart';
export 'src/settings.dart';
export 'src/streaming/streaming_tool_call.dart';
