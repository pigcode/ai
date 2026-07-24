import 'dart:convert';

import 'package:json_schema/json_schema.dart' as upstream;
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'generated/dap_inventory.g.dart';

final Map<String, String> dapDefinitionClassifications =
    Map<String, String>.unmodifiable(
  dapGeneratedDefinitionClassifications,
);

abstract class DapSchemaValue {
  const DapSchemaValue(
    this.value, {
    required this.definitionName,
  });

  final JsonValue value;
  final String definitionName;

  JsonValue toJson() => value;
}

final class DapModelRegistry {
  DapModelRegistry._()
      : document = freezeJsonObject(
          jsonDecode(dapGeneratedSchemaJson) as Map<String, Object?>,
        );

  static final DapModelRegistry instance = DapModelRegistry._();

  final JsonObject document;
  final Map<String, upstream.JsonSchema> _validators =
      <String, upstream.JsonSchema>{};

  JsonValue validateNamed(String definitionName, JsonValue value) {
    if (!dapDefinitionClassifications.containsKey(definitionName)) {
      throw DapSchemaException(
        'dap_unknown_definition',
        'Unknown DAP 1.71.0 schema definition.',
        definition: definitionName,
      );
    }
    late final JsonValue frozen;
    try {
      frozen = freezeJsonValue(value);
    } on JsonValueException catch (error) {
      throw DapSchemaException(
        'dap_schema_invalid_json',
        'DAP value is not immutable JSON-compatible data.',
        definition: definitionName,
        cause: error,
      );
    }
    final validator = _validators.putIfAbsent(
      definitionName,
      () => upstream.JsonSchema.create(
        <String, Object?>{
          r'$schema': document[r'$schema'],
          r'$ref': '#/definitions/$definitionName',
          'definitions': document['definitions'],
        },
      ),
    );
    final result = validator.validate(frozen);
    if (!result.isValid) {
      throw DapSchemaException(
        'dap_schema_invalid',
        'DAP value does not satisfy the pinned 1.71.0 schema.',
        definition: definitionName,
        instancePath:
            result.errors.isEmpty ? null : result.errors.first.instancePath,
      );
    }
    return frozen;
  }
}
