import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'generated/lsp_inventory.g.dart';

/// Classification for every named model in the pinned meta-model.
final Map<String, String> lspDefinitionClassifications =
    Map<String, String>.unmodifiable(
  lspGeneratedDefinitionClassifications,
);

/// Immutable JSON-backed value validated against one named LSP definition.
abstract class LspSchemaValue {
  const LspSchemaValue(
    this.value, {
    required this.definitionName,
  });

  final JsonValue value;
  final String definitionName;

  JsonValue toJson() => value;

  @override
  String toString() => '$runtimeType($definitionName)';
}

/// Runtime validator for the exact vendored LSP 3.18 meta-model.
final class LspModelRegistry {
  LspModelRegistry._()
      : _document = freezeJsonObject(
          jsonDecode(lspGeneratedMetaModelJson) as Map<String, Object?>,
        ) {
    _index(_document['structures'], _structures);
    _index(_document['enumerations'], _enumerations);
    _index(_document['typeAliases'], _typeAliases);
  }

  static final LspModelRegistry instance = LspModelRegistry._();

  final JsonObject _document;
  final Map<String, JsonObject> _structures = <String, JsonObject>{};
  final Map<String, JsonObject> _enumerations = <String, JsonObject>{};
  final Map<String, JsonObject> _typeAliases = <String, JsonObject>{};

  Set<String> get definitionNames =>
      Set<String>.unmodifiable(lspDefinitionClassifications.keys);

  /// Validates and deeply freezes a value against one named LSP model.
  JsonValue validateNamed(String definitionName, JsonValue value) {
    if (!lspDefinitionClassifications.containsKey(definitionName)) {
      throw LspSchemaException(
        'lsp_unknown_definition',
        'Unknown LSP 3.18 meta-model definition.',
        definition: definitionName,
      );
    }
    late final JsonValue frozen;
    try {
      frozen = freezeJsonValue(value);
    } on JsonValueException catch (error) {
      throw LspSchemaException(
        'lsp_schema_invalid_json',
        'LSP value is not immutable JSON-compatible data.',
        definition: definitionName,
        cause: error,
      );
    }
    _validateReference(
      definitionName,
      frozen,
      path: r'$',
      definition: definitionName,
      active: <String>{},
    );
    return frozen;
  }

  /// Validates a value against an inline meta-model type descriptor.
  JsonValue validateType(
    JsonObject type,
    JsonValue value, {
    required String context,
  }) {
    late final JsonValue frozen;
    try {
      frozen = freezeJsonValue(value);
    } on JsonValueException catch (error) {
      throw LspSchemaException(
        'lsp_schema_invalid_json',
        'LSP value is not immutable JSON-compatible data.',
        definition: context,
        cause: error,
      );
    }
    _validateType(
      type,
      frozen,
      path: r'$',
      definition: context,
      active: <String>{},
    );
    return frozen;
  }

  void _index(Object? values, Map<String, JsonObject> target) {
    for (final value in (values! as List<Object?>).cast<JsonObject>()) {
      target[value['name']! as String] = value;
    }
  }

  void _validateReference(
    String name,
    JsonValue value, {
    required String path,
    required String definition,
    required Set<String> active,
  }) {
    final structure = _structures[name];
    if (structure != null) {
      _validateStructure(
        name,
        structure,
        value,
        path: path,
        definition: definition,
        active: active,
      );
      return;
    }
    final enumeration = _enumerations[name];
    if (enumeration != null) {
      _validateEnumeration(
        name,
        enumeration,
        value,
        path: path,
        definition: definition,
      );
      return;
    }
    final alias = _typeAliases[name];
    if (alias != null) {
      _validateType(
        alias['type']! as JsonObject,
        value,
        path: path,
        definition: definition,
        active: active,
      );
      return;
    }
    _fail(
      'lsp_unknown_reference',
      'LSP meta-model contains an unknown type reference: $name.',
      definition,
      path,
    );
  }

  void _validateStructure(
    String name,
    JsonObject structure,
    JsonValue value, {
    required String path,
    required String definition,
    required Set<String> active,
  }) {
    if (value is! Map<String, Object?>) {
      _fail(
        'lsp_schema_invalid',
        'Expected an object for LSP structure $name.',
        definition,
        path,
      );
    }
    final activation = '$name:${identityHashCode(value)}';
    if (!active.add(activation)) {
      return;
    }
    try {
      for (final relationName in const <String>['extends', 'mixins']) {
        final relations = structure[relationName];
        if (relations is List<Object?>) {
          for (final relation in relations.cast<JsonObject>()) {
            _validateType(
              relation,
              value,
              path: path,
              definition: definition,
              active: active,
            );
          }
        }
      }
      final properties = structure['properties'];
      if (properties is! List<Object?>) {
        return;
      }
      for (final property in properties.cast<JsonObject>()) {
        final propertyName = property['name']! as String;
        if (!value.containsKey(propertyName)) {
          if (property['optional'] == true) {
            continue;
          }
          _fail(
            'lsp_schema_required',
            'Missing required LSP property: $propertyName.',
            definition,
            '$path.$propertyName',
          );
        }
        _validateType(
          property['type']! as JsonObject,
          value[propertyName],
          path: '$path.$propertyName',
          definition: definition,
          active: active,
        );
      }
    } finally {
      active.remove(activation);
    }
  }

  void _validateEnumeration(
    String name,
    JsonObject enumeration,
    JsonValue value, {
    required String path,
    required String definition,
  }) {
    _validateBase(
      (enumeration['type']! as JsonObject)['name']! as String,
      value,
      path: path,
      definition: definition,
    );
    final values = (enumeration['values']! as List<Object?>)
        .cast<JsonObject>()
        .map((entry) => entry['value'])
        .toSet();
    if (!values.contains(value) &&
        enumeration['supportsCustomValues'] != true) {
      _fail(
        'lsp_closed_enum_unknown',
        'Unknown value for closed LSP enumeration $name.',
        definition,
        path,
      );
    }
  }

  void _validateType(
    JsonObject type,
    JsonValue value, {
    required String path,
    required String definition,
    required Set<String> active,
  }) {
    switch (type['kind']) {
      case 'base':
        _validateBase(
          type['name']! as String,
          value,
          path: path,
          definition: definition,
        );
      case 'reference':
        _validateReference(
          type['name']! as String,
          value,
          path: path,
          definition: definition,
          active: active,
        );
      case 'array':
        if (value is! List<Object?>) {
          _fail(
            'lsp_schema_invalid',
            'Expected an array.',
            definition,
            path,
          );
        }
        for (var index = 0; index < value.length; index += 1) {
          _validateType(
            type['element']! as JsonObject,
            value[index],
            path: '$path[$index]',
            definition: definition,
            active: active,
          );
        }
      case 'map':
        if (value is! Map<String, Object?>) {
          _fail(
            'lsp_schema_invalid',
            'Expected an object map.',
            definition,
            path,
          );
        }
        for (final entry in value.entries) {
          _validateType(
            type['value']! as JsonObject,
            entry.value,
            path: '$path.${entry.key}',
            definition: definition,
            active: active,
          );
        }
      case 'or':
        final items = (type['items']! as List<Object?>).cast<JsonObject>();
        for (final item in items) {
          try {
            _validateType(
              item,
              value,
              path: path,
              definition: definition,
              active: Set<String>.of(active),
            );
            return;
          } on LspSchemaException {
            // Try the next union member.
          }
        }
        _fail(
          'lsp_schema_invalid_union',
          'Value does not satisfy any LSP union member.',
          definition,
          path,
        );
      case 'tuple':
        final items = (type['items']! as List<Object?>).cast<JsonObject>();
        if (value is! List<Object?> || value.length != items.length) {
          _fail(
            'lsp_schema_invalid',
            'Expected an LSP tuple with ${items.length} items.',
            definition,
            path,
          );
        }
        for (var index = 0; index < items.length; index += 1) {
          _validateType(
            items[index],
            value[index],
            path: '$path[$index]',
            definition: definition,
            active: active,
          );
        }
      case 'literal':
        final literal = type['value']! as JsonObject;
        final properties = literal['properties']! as List<Object?>;
        if (value is! Map<String, Object?>) {
          _fail(
            'lsp_schema_invalid',
            'Expected an object literal.',
            definition,
            path,
          );
        }
        for (final property in properties.cast<JsonObject>()) {
          final propertyName = property['name']! as String;
          if (!value.containsKey(propertyName)) {
            if (property['optional'] == true) {
              continue;
            }
            _fail(
              'lsp_schema_required',
              'Missing required LSP literal property: $propertyName.',
              definition,
              '$path.$propertyName',
            );
          }
          _validateType(
            property['type']! as JsonObject,
            value[propertyName],
            path: '$path.$propertyName',
            definition: definition,
            active: active,
          );
        }
      case 'stringLiteral':
        if (value != type['value']) {
          _fail(
            'lsp_schema_invalid_literal',
            'Expected the pinned LSP string literal.',
            definition,
            path,
          );
        }
      default:
        _fail(
          'lsp_unknown_type_kind',
          'Unknown LSP meta-model type kind: ${type['kind']}.',
          definition,
          path,
        );
    }
  }

  void _validateBase(
    String name,
    JsonValue value, {
    required String path,
    required String definition,
  }) {
    final valid = switch (name) {
      'URI' || 'DocumentUri' || 'string' => value is String,
      'integer' => value is int,
      'uinteger' => value is int && value >= 0 && value <= 2147483647,
      'decimal' => value is num,
      'boolean' => value is bool,
      'null' => value == null,
      _ => false,
    };
    if (!valid) {
      _fail(
        'lsp_schema_invalid',
        'Value does not satisfy LSP base type $name.',
        definition,
        path,
      );
    }
  }

  Never _fail(
    String code,
    String message,
    String definition,
    String path,
  ) {
    throw LspSchemaException(
      code,
      message,
      definition: definition,
      instancePath: path,
    );
  }
}
