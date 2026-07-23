import 'dart:convert';

import 'package:json_schema/json_schema.dart' as upstream;
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'generated/mcp_inventory.g.dart';
import 'generated/mcp_schema.g.dart';

final class McpSchema {
  McpSchema._()
      : document = freezeJsonObject(
          jsonDecode(mcpGeneratedSchemaJson) as Map<String, Object?>,
        );

  static final McpSchema instance = McpSchema._();

  final JsonObject document;
  final Map<String, upstream.JsonSchema> _validators =
      <String, upstream.JsonSchema>{};

  Set<String> get definitionNames =>
      Set<String>.unmodifiable(mcpGeneratedDefinitionNames);

  JsonValue validateDefinition(String definitionName, JsonValue value) {
    if (!mcpGeneratedDefinitionNames.contains(definitionName)) {
      throw McpSchemaException(
        'mcp_unknown_definition',
        'Unknown MCP 2025-11-25 schema definition.',
        definition: definitionName,
      );
    }
    return _validateNamed(definitionName, value);
  }

  JsonValue validateRole(String roleName, JsonValue value) {
    if (!mcpGeneratedRoleDefinitions.contains(roleName)) {
      throw McpSchemaException(
        'mcp_unknown_role',
        'Unknown or empty MCP role validation root.',
        role: roleName,
      );
    }
    return _validateNamed(roleName, value, role: roleName);
  }

  JsonValue _validateNamed(
    String definitionName,
    JsonValue value, {
    String? role,
  }) {
    late final JsonValue frozen;
    try {
      frozen = freezeJsonValue(value);
    } on JsonValueException catch (error) {
      throw McpSchemaException(
        'mcp_schema_invalid_json',
        'MCP value is not immutable JSON-compatible data.',
        definition: definitionName,
        role: role,
        cause: error,
      );
    }
    final validator = _validators.putIfAbsent(
      definitionName,
      () => upstream.JsonSchema.create(
        <String, Object?>{
          r'$schema': document[r'$schema'],
          r'$ref': '#/\$defs/$definitionName',
          r'$defs': document[r'$defs'],
        },
      ),
    );
    // The pinned 2025-11-25 schema accidentally declares NumberSchema
    // default/minimum/maximum and ElicitResult numeric content as JSON
    // `integer`. SEP-1034 and the pinned official conformance scenario use a
    // fractional default and expect it in the result. Validate a
    // shape-equivalent copy with only those fractional values normalized,
    // while returning and retaining the exact original value.
    final result = validator.validate(_normalizePinnedSchemaDefects(frozen));
    if (!result.isValid) {
      throw McpSchemaException(
        'mcp_schema_invalid',
        'MCP value does not satisfy the pinned 2025-11-25 schema.',
        definition: definitionName,
        role: role,
        instancePath:
            result.errors.isEmpty ? null : result.errors.first.instancePath,
      );
    }
    return frozen;
  }
}

JsonValue _normalizePinnedSchemaDefects(JsonValue value) => switch (value) {
      final Map<String, Object?> object => <String, Object?>{
          for (final entry in object.entries)
            entry.key: _isPinnedFractionalNumberSchemaKeyword(object, entry)
                ? 0
                : object['action'] == 'accept' &&
                        entry.key == 'content' &&
                        entry.value is Map<String, Object?>
                    ? <String, Object?>{
                        for (final contentEntry
                            in (entry.value! as Map<String, Object?>).entries)
                          contentEntry.key: contentEntry.value is num &&
                                  contentEntry.value is! int
                              ? 0
                              : _normalizePinnedSchemaDefects(
                                  contentEntry.value,
                                ),
                      }
                    : _normalizePinnedSchemaDefects(entry.value),
        },
      final List<Object?> list => <Object?>[
          for (final item in list) _normalizePinnedSchemaDefects(item),
        ],
      _ => value,
    };

bool _isPinnedFractionalNumberSchemaKeyword(
  Map<String, Object?> object,
  MapEntry<String, Object?> entry,
) =>
    object['type'] == 'number' &&
    const <String>{'default', 'minimum', 'maximum'}.contains(entry.key) &&
    entry.value is num &&
    entry.value is! int;
