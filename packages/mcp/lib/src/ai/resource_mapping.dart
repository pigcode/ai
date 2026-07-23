import 'package:pigcode_ai/pigcode_ai.dart' hide JsonObject, JsonValue;
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../generated/mcp_models.g.dart';
import 'mapping_policy.dart';

/// Converts an explicit `resources/read` result to model input.
///
/// This function performs no network or filesystem I/O. In particular, an MCP
/// resource link is never dereferenced by this mapping layer.
List<UserContentPart> mapMcpReadResourceResult(
  McpReadResourceResult result, {
  McpTextResourceMapping textMapping = McpTextResourceMapping.filePart,
}) {
  final raw = result.toJson()! as JsonObject;
  return List<UserContentPart>.unmodifiable(
    (raw['contents']! as List<Object?>).cast<JsonObject>().map(
          (resource) => mapMcpResourceContents(
            McpResourceContents.fromJson(resource),
            textMapping: textMapping,
          ),
        ),
  );
}

/// Converts one validated MCP resource payload to neutral user content.
UserContentPart mapMcpResourceContents(
  McpResourceContents contents, {
  McpTextResourceMapping textMapping = McpTextResourceMapping.filePart,
}) {
  final raw = contents.toJson()! as JsonObject;
  final uri = raw['uri']! as String;
  final providerOptions = mcpProviderOptions(<String, Object?>{
    'contentType': 'resource',
    'uri': uri,
    if (raw['mimeType'] != null) 'mimeType': raw['mimeType'],
    if (raw['_meta'] != null) '_meta': raw['_meta'],
  });
  if (raw['text'] case final String text) {
    if (textMapping == McpTextResourceMapping.textPart) {
      return TextPart(text, providerOptions: providerOptions);
    }
    return FilePart(
      data: DataText(text),
      mediaType: raw['mimeType'] as String? ?? 'text/plain',
      filename: _filenameFromUri(uri),
      providerOptions: providerOptions,
    );
  }
  if (raw['blob'] case final String blob) {
    return FilePart(
      data: DataBase64(blob),
      mediaType: raw['mimeType'] as String? ?? 'application/octet-stream',
      filename: _filenameFromUri(uri),
      providerOptions: providerOptions,
    );
  }
  throw const McpMappingException(
    'mcp_resource_contents_missing_payload',
    'MCP resource contents have neither text nor blob data.',
    mcpType: 'resource',
  );
}

/// Converts a prompt content block to user content.
UserContentPart mapMcpPromptUserContent(
  McpContentBlock content, {
  McpLossyMappingPolicy policy = McpLossyMappingPolicy.strict,
}) =>
    _mapPromptContent(content, policy: policy) as UserContentPart;

/// Converts a prompt content block to assistant content.
AssistantContentPart mapMcpPromptAssistantContent(
  McpContentBlock content, {
  McpLossyMappingPolicy policy = McpLossyMappingPolicy.strict,
}) =>
    _mapPromptContent(content, policy: policy) as AssistantContentPart;

Object _mapPromptContent(
  McpContentBlock content, {
  required McpLossyMappingPolicy policy,
}) {
  final raw = content.toJson()! as JsonObject;
  final type = raw['type'];
  final providerOptions = mcpProviderOptions(<String, Object?>{
    'contentType': type,
    if (raw['annotations'] != null) 'annotations': raw['annotations'],
    if (raw['_meta'] != null) '_meta': raw['_meta'],
  });
  return switch (type) {
    'text' => TextPart(
        raw['text']! as String,
        providerOptions: providerOptions,
      ),
    'image' || 'audio' => FilePart(
        data: DataBase64(raw['data']! as String),
        mediaType: raw['mimeType']! as String,
        providerOptions: providerOptions,
      ),
    'resource' => _mapEmbeddedResource(raw),
    'resource_link' => _mapResourceLink(raw, policy),
    _ => throw McpMappingException(
        'mcp_unknown_content_type',
        'MCP prompt content type is not supported by the pinned mapping.',
        mcpType: type?.toString(),
      ),
  };
}

FilePart _mapEmbeddedResource(JsonObject block) {
  final resource = block['resource']! as JsonObject;
  final uri = resource['uri']! as String;
  return FilePart(
    data: resource['text'] is String
        ? DataText(resource['text']! as String)
        : DataBase64(resource['blob']! as String),
    mediaType: resource['mimeType'] as String? ??
        (resource.containsKey('text')
            ? 'text/plain'
            : 'application/octet-stream'),
    filename: _filenameFromUri(uri),
    providerOptions: mcpProviderOptions(<String, Object?>{
      'contentType': 'resource',
      'uri': uri,
      if (resource['mimeType'] != null) 'mimeType': resource['mimeType'],
      if (block['annotations'] != null) 'annotations': block['annotations'],
      if (block['_meta'] != null) '_meta': block['_meta'],
      if (resource['_meta'] != null) 'resourceMeta': resource['_meta'],
    }),
  );
}

TextPart _mapResourceLink(
  JsonObject raw,
  McpLossyMappingPolicy policy,
) {
  if (policy == McpLossyMappingPolicy.strict) {
    throw const McpMappingException(
      'mcp_resource_link_has_no_neutral_equivalent',
      'MCP resource links require preserveWithMetadata mapping.',
      mcpType: 'resource_link',
    );
  }
  final name = raw['name']! as String;
  final uri = raw['uri']! as String;
  return TextPart(
    'MCP resource link: $name ($uri)',
    providerOptions: mcpProviderOptions(<String, Object?>{
      'contentType': 'resource_link',
      'resourceLink': raw,
      'dereferenced': false,
    }),
  );
}

String? _filenameFromUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.pathSegments.isEmpty) return null;
  final name = uri.pathSegments.last;
  return name.isEmpty ? null : name;
}
