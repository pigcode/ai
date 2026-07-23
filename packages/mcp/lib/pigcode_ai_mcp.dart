/// Portable Model Context Protocol `2025-11-25` surface.
///
/// VM-only adapters live in `pigcode_ai_mcp_io.dart` and are not re-exported.
library;

export 'src/ai/content_mapping.dart';
export 'src/ai/mapping_policy.dart';
export 'src/ai/prompt_mapping.dart';
export 'src/ai/resource_mapping.dart';
export 'src/ai/tool_mapping.dart';
export 'src/capabilities.dart';
export 'src/cancellation_adapter.dart';
export 'src/client.dart';
export 'src/codec.dart';
export 'src/completion.dart';
export 'src/connection.dart';
export 'src/errors.dart';
export 'src/generated/mcp_models.g.dart'
    hide McpClientCapabilities, McpServerCapabilities;
export 'src/handlers.dart';
export 'src/logging.dart';
export 'src/models.dart';
export 'src/pagination.dart';
export 'src/progress.dart';
export 'src/prompts.dart';
export 'src/recording.dart';
export 'src/resources.dart';
export 'src/reverse_requests.dart';
export 'src/schema.dart';
export 'src/server.dart';
export 'src/tasks.dart';
export 'src/tools.dart';
export 'src/transport/stdio.dart';
export 'src/version.dart';
