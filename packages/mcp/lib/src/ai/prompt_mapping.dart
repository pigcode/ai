import 'package:pigcode_ai/pigcode_ai.dart' hide JsonObject, JsonValue;
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../generated/mcp_models.g.dart';
import 'mapping_policy.dart';
import 'resource_mapping.dart';

/// A rendered MCP prompt plus prompt-level metadata.
final class McpMappedPrompt {
  McpMappedPrompt({
    required List<ModelMessage> messages,
    this.description,
    this.providerOptions,
  }) : messages = List<ModelMessage>.unmodifiable(messages);

  final String? description;
  final List<ModelMessage> messages;
  final ProviderOptions? providerOptions;
}

/// Converts a rendered MCP prompt into neutral model messages.
McpMappedPrompt mapMcpPrompt(
  McpGetPromptResult result, {
  McpLossyMappingPolicy policy = McpLossyMappingPolicy.strict,
}) {
  final raw = result.toJson()! as JsonObject;
  final promptMetadata = <String, Object?>{
    if (raw['_meta'] != null) '_meta': raw['_meta'],
  };
  return McpMappedPrompt(
    description: raw['description'] as String?,
    providerOptions:
        promptMetadata.isEmpty ? null : mcpProviderOptions(promptMetadata),
    messages: (raw['messages']! as List<Object?>)
        .cast<JsonObject>()
        .map(
          (message) => mapMcpPromptMessage(
            McpPromptMessage.fromJson(message),
            policy: policy,
          ),
        )
        .toList(growable: false),
  );
}

/// Converts one MCP prompt message while preserving its role.
ModelMessage mapMcpPromptMessage(
  McpPromptMessage message, {
  McpLossyMappingPolicy policy = McpLossyMappingPolicy.strict,
}) {
  final raw = message.toJson()! as JsonObject;
  final content = McpContentBlock.fromJson(raw['content']);
  return switch (raw['role']) {
    'user' => UserModelMessage(
        <UserContentPart>[
          mapMcpPromptUserContent(content, policy: policy),
        ],
      ),
    'assistant' => AssistantModelMessage(
        <AssistantContentPart>[
          mapMcpPromptAssistantContent(content, policy: policy),
        ],
      ),
    _ => throw McpMappingException(
        'mcp_unknown_prompt_role',
        'MCP prompt role is not supported by the pinned mapping.',
        mcpType: raw['role']?.toString(),
      ),
  };
}
