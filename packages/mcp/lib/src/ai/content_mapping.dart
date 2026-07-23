import 'package:pigcode_ai/pigcode_ai.dart' hide JsonObject, JsonValue;
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../generated/mcp_models.g.dart';
import 'mapping_policy.dart';

/// Converts a validated MCP tool result into the neutral Pigcode AI result
/// union without confusing model-visible tool errors with protocol failures.
ToolResultOutput mapMcpToolResult(McpCallToolResult result) {
  final raw = result.toJson()! as JsonObject;
  final content = (raw['content']! as List<Object?>)
      .cast<JsonObject>()
      .map((item) => mapMcpToolContent(McpContentBlock.fromJson(item)))
      .toList(growable: true);
  final structured = raw['structuredContent'];
  final isError = raw['isError'] == true;
  final resultMeta = <String, Object?>{
    if (raw['_meta'] case final JsonObject meta) '_meta': meta,
    if (structured != null) 'structuredContent': structured,
    if (isError) 'isError': true,
  };

  if (content.isEmpty && structured != null) {
    return isError
        ? ToolResultErrorJson(
            structured,
            providerOptions: mcpProviderOptions(resultMeta),
          )
        : ToolResultJson(
            structured,
            providerOptions: mcpProviderOptions(resultMeta),
          );
  }
  if (content.length == 1 &&
      content.single is ToolResultTextItem &&
      structured == null) {
    final textItem = content.single as ToolResultTextItem;
    final providerOptions = mcpProviderOptions(<String, Object?>{
      ...?textItem.providerOptions?['mcp'],
      ...resultMeta,
    });
    return isError
        ? ToolResultErrorText(
            textItem.text,
            providerOptions: providerOptions,
          )
        : ToolResultText(
            textItem.text,
            providerOptions: providerOptions,
          );
  }

  if (resultMeta.isNotEmpty) {
    content.add(
      ToolResultCustomItem(
        providerOptions: mcpProviderOptions(resultMeta),
      ),
    );
  }
  return ToolResultContentOutput(List<ToolResultContentItem>.unmodifiable(
    content,
  ));
}

/// Converts one MCP tool-result content block.
ToolResultContentItem mapMcpToolContent(McpContentBlock content) {
  final raw = content.toJson()! as JsonObject;
  final type = raw['type'];
  final metadata = mcpProviderOptions(<String, Object?>{
    'contentType': type,
    if (raw['annotations'] != null) 'annotations': raw['annotations'],
    if (raw['_meta'] != null) '_meta': raw['_meta'],
  });

  return switch (type) {
    'text' => ToolResultTextItem(
        raw['text']! as String,
        providerOptions: metadata,
      ),
    'image' || 'audio' => ToolResultFileItem(
        data: FileDataBase64(raw['data']! as String),
        mediaType: raw['mimeType']! as String,
        providerOptions: metadata,
      ),
    'resource' => _mapEmbeddedResource(raw, metadata),
    'resource_link' => ToolResultCustomItem(
        providerOptions: mcpProviderOptions(<String, Object?>{
          'contentType': 'resource_link',
          'resourceLink': raw,
          'dereferenced': false,
        }),
      ),
    _ => throw McpMappingException(
        'mcp_unknown_content_type',
        'MCP content type is not supported by the pinned mapping.',
        mcpType: type?.toString(),
      ),
  };
}

ToolResultFileItem _mapEmbeddedResource(
  JsonObject block,
  ProviderOptions metadata,
) {
  final resource = block['resource']! as JsonObject;
  final uri = resource['uri']! as String;
  final mimeType = resource['mimeType'] as String? ??
      (resource.containsKey('text')
          ? 'text/plain'
          : 'application/octet-stream');
  final filename = _filenameFromUri(uri);
  final resourceMetadata = mcpProviderOptions(<String, Object?>{
    'contentType': 'resource',
    'uri': uri,
    if (resource['mimeType'] != null) 'mimeType': resource['mimeType'],
    if (block['annotations'] != null) 'annotations': block['annotations'],
    if (block['_meta'] != null) '_meta': block['_meta'],
    if (resource['_meta'] != null) 'resourceMeta': resource['_meta'],
  });
  return ToolResultFileItem(
    data: resource['text'] is String
        ? FileDataText(resource['text']! as String)
        : FileDataBase64(resource['blob']! as String),
    mediaType: mimeType,
    filename: filename,
    providerOptions:
        resourceMetadata['mcp']!.isEmpty ? metadata : resourceMetadata,
  );
}

String? _filenameFromUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.pathSegments.isEmpty) return null;
  final name = uri.pathSegments.last;
  return name.isEmpty ? null : name;
}
