import 'package:pigcode_ai_provider/pigcode_ai_provider.dart'
    show ProviderOptions;
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// Policy for an MCP value that has no exactly equivalent Pigcode AI value.
enum McpLossyMappingPolicy {
  /// Reject the conversion instead of silently changing its meaning.
  strict,

  /// Use the closest neutral value and retain the original MCP value under
  /// `providerOptions['mcp']`.
  preserveWithMetadata,
}

/// Selects the neutral representation for textual resource contents.
enum McpTextResourceMapping {
  /// Expose the text directly to the model.
  textPart,

  /// Retain file semantics, including media type and filename.
  filePart,
}

/// Controls how MCP tool names are exposed to a model.
sealed class McpToolNamePolicy {
  const McpToolNamePolicy();

  const factory McpToolNamePolicy.exact() = McpExactToolNames;

  const factory McpToolNamePolicy.prefixed(
    String prefix, {
    String separator,
  }) = McpPrefixedToolNames;

  String map(String mcpName);
}

final class McpExactToolNames extends McpToolNamePolicy {
  const McpExactToolNames();

  @override
  String map(String mcpName) => mcpName;
}

final class McpPrefixedToolNames extends McpToolNamePolicy {
  const McpPrefixedToolNames(
    this.prefix, {
    this.separator = '_',
  }) : assert(prefix != '');

  final String prefix;
  final String separator;

  @override
  String map(String mcpName) => '$prefix$separator$mcpName';
}

/// A validated MCP value cannot be represented under the selected policy.
final class McpMappingException implements Exception {
  const McpMappingException(
    this.code,
    this.message, {
    this.mcpType,
  });

  final String code;
  final String message;
  final String? mcpType;

  @override
  String toString() => 'McpMappingException($code): $message';
}

/// Two MCP tools would occupy the same model-visible name.
final class McpToolNameCollisionException implements Exception {
  const McpToolNameCollisionException(this.name);

  final String name;

  @override
  String toString() => 'McpToolNameCollisionException($name)';
}

/// A protocol, schema, or transport failure while executing an MCP tool.
///
/// This is intentionally distinct from an MCP `CallToolResult` whose
/// `isError` field is true. The latter is returned to the model as a normal
/// tool result so the model can self-correct.
final class McpToolExecutionException implements Exception {
  const McpToolExecutionException({
    required this.toolName,
    required this.cause,
  });

  final String toolName;
  final Object cause;

  String? get protocolCode =>
      cause is ProtocolException ? (cause as ProtocolException).code : null;

  @override
  String toString() => 'McpToolExecutionException($toolName)';
}

ProviderOptions mcpProviderOptions(
  JsonObject metadata,
) =>
    <String, JsonObject>{
      'mcp': Map<String, Object?>.unmodifiable(metadata),
    };
