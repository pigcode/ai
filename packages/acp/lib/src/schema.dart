import 'dart:convert';

import 'package:json_schema/json_schema.dart' as upstream;
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'generated/acp_inventory.g.dart';
import 'generated/acp_schema.g.dart';

/// Runtime registry for the exact vendored ACP stable-v1 schema.
final class AcpSchema {
  AcpSchema._()
      : document = freezeJsonObject(
          jsonDecode(acpGeneratedSchemaJson) as Map<String, Object?>,
        );

  static final AcpSchema instance = AcpSchema._();

  final JsonObject document;
  final Map<String, upstream.JsonSchema> _definitionValidators =
      <String, upstream.JsonSchema>{};
  final Map<String, upstream.JsonSchema> _rootValidators =
      <String, upstream.JsonSchema>{};

  Set<String> get definitionNames =>
      Set<String>.unmodifiable(acpGeneratedDefinitionNames);

  /// Validates and freezes a value against one pinned `$defs` entry.
  JsonValue validateDefinition(String definitionName, JsonValue value) {
    if (!acpGeneratedDefinitionNames.contains(definitionName)) {
      throw AcpSchemaException(
        'acp_unknown_definition',
        'Unknown ACP stable schema definition.',
        definition: definitionName,
      );
    }
    final frozen = _freeze(value, definition: definitionName);
    final validator = _definitionValidators.putIfAbsent(
      definitionName,
      () => upstream.JsonSchema.create(
        <String, Object?>{
          r'$schema': document[r'$schema'],
          r'$ref': '#/\$defs/$definitionName',
          r'$defs': document[r'$defs'],
        },
      ),
    );
    _validate(
      validator,
      frozen,
      definition: definitionName,
    );
    return frozen;
  }

  /// Validates and freezes one complete Agent/Client/ProtocolLevel message.
  JsonObject validateRoot(String rootName, JsonObject value) {
    if (!acpGeneratedMessageRoots.contains(rootName)) {
      throw AcpSchemaException(
        'acp_unknown_root',
        'Unknown ACP stable message root.',
        root: rootName,
      );
    }
    final frozen = _freeze(value, root: rootName) as JsonObject;
    final validator = _rootValidators.putIfAbsent(
      rootName,
      () {
        final roots = document['anyOf']! as List<Object?>;
        final root = roots.cast<JsonObject>().singleWhere(
              (candidate) => candidate['title'] == rootName,
            );
        return upstream.JsonSchema.create(
          <String, Object?>{
            r'$schema': document[r'$schema'],
            r'$defs': document[r'$defs'],
            ...root,
          },
        );
      },
    );
    _validate(validator, frozen, root: rootName);
    return frozen;
  }

  JsonValue _freeze(
    JsonValue value, {
    String? definition,
    String? root,
  }) {
    try {
      return freezeJsonValue(value);
    } on JsonValueException catch (error) {
      throw AcpSchemaException(
        'acp_schema_invalid_json',
        'ACP value is not immutable JSON-compatible data.',
        definition: definition,
        root: root,
        cause: error,
      );
    }
  }

  void _validate(
    upstream.JsonSchema validator,
    JsonValue value, {
    String? definition,
    String? root,
  }) {
    final result = validator.validate(value);
    if (result.isValid) {
      return;
    }
    throw AcpSchemaException(
      'acp_schema_invalid',
      'ACP value does not satisfy the pinned stable-v1 schema.',
      definition: definition,
      root: root,
      instancePath:
          result.errors.isEmpty ? null : result.errors.first.instancePath,
    );
  }
}
