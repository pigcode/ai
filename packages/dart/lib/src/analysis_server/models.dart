import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/availability.dart';
import '../common/errors.dart';
import 'generated/inventory.g.dart';
import 'version.dart';

abstract class AnalysisServerSchemaValue {
  const AnalysisServerSchemaValue(
    this.value, {
    required this.definitionName,
  });

  final JsonValue value;
  final String definitionName;

  JsonValue toJson() => value;
}

final class AnalysisServerEnumValue {
  factory AnalysisServerEnumValue.parse(String enumName, String value) {
    final values = AnalysisServerModelRegistry.instance.enumValues(enumName);
    return AnalysisServerEnumValue._(
      enumName: enumName,
      value: value,
      isKnown: values.contains(value),
    );
  }

  const AnalysisServerEnumValue._({
    required this.enumName,
    required this.value,
    required this.isKnown,
  });

  final String enumName;
  final String value;
  final bool isKnown;

  String toJson() => value;

  @override
  String toString() => value;
}

final class AnalysisServerModelRegistry {
  AnalysisServerModelRegistry._()
      : _document = jsonDecode(analysisServerGeneratedInventoryJson)
            as Map<String, Object?> {
    final minimum = _map(_document['minimum'], 'minimum');
    final current = _map(_document['current'], 'current');
    if (minimum['apiVersion'] != analysisServerMinimumApiVersion.toString() ||
        current['apiVersion'] != analysisServerCurrentApiVersion.toString() ||
        minimum['revision'] !=
            analysisServerMinimumSourceIdentity.sourceRevision ||
        current['revision'] !=
            analysisServerCurrentSourceIdentity.sourceRevision ||
        minimum['specSha256'] !=
            analysisServerMinimumSourceIdentity.artifactSha256 ||
        current['specSha256'] !=
            analysisServerCurrentSourceIdentity.artifactSha256) {
      throw const ToolingVersionError(
        'analysis_server_generated_identity_mismatch',
        'Generated Analysis Server identity does not match the public pin.',
      );
    }
  }

  static final AnalysisServerModelRegistry instance =
      AnalysisServerModelRegistry._();

  final Map<String, Object?> _document;

  Set<String> get minimumRequestNames =>
      _stringSet(_document['minimumRequestNames']);

  Set<String> get currentRequestNames =>
      _stringSet(_document['currentRequestNames']);

  Set<String> get minimumNotificationNames =>
      _stringSet(_document['minimumNotificationNames']);

  Set<String> get currentNotificationNames =>
      _stringSet(_document['currentNotificationNames']);

  Set<String> get currentOnlyNotificationNames =>
      _stringSet(_document['currentOnlyNotificationNames']);

  Set<String> get minimumOnlyNames => _stringSet(_document['minimumOnlyNames']);

  Set<String> get typeNames => Set<String>.unmodifiable(_types.keys);

  Set<String> get enumNames => Set<String>.unmodifiable(_enums.keys);

  Set<String> get changedDefinitions =>
      _stringSet(_document['changedDefinitions']);

  Set<String> get unclassifiedChangedDefinitions =>
      _stringSet(_document['unclassifiedChangedDefinitions']);

  Set<String> enumValues(String enumName) {
    final values = _enums[enumName];
    if (values is! List<Object?>) {
      throw ToolingSchemaError(
        'analysis_server_enum_unknown',
        'Unknown Analysis Server enum: $enumName.',
      );
    }
    return Set<String>.unmodifiable(values.cast<String>());
  }

  bool isRequestAvailable(
    String method,
    AnalysisServerApiVersion version,
  ) =>
      _isAvailable(_requests, method, version);

  bool isNotificationAvailable(
    String event,
    AnalysisServerApiVersion version,
  ) =>
      _isAvailable(_notifications, event, version);

  JsonValue validateType(String name, JsonValue value) {
    final shape = _types[name];
    if (shape is! Map<String, Object?>) {
      throw ToolingSchemaError(
        'analysis_server_type_unknown',
        'Unknown Analysis Server type: $name.',
      );
    }
    _validateShape(shape, value, path: name, depth: 0);
    return freezeJsonValue(value);
  }

  JsonObject? validateRequestParams(
    String method,
    Object? value, {
    required AnalysisServerApiVersion version,
  }) {
    final descriptor = _availableDescriptor(
      _requests,
      method,
      version,
      kind: 'request',
    );
    return _validatePayload(
      descriptor['params'],
      value,
      path: '$method params',
    );
  }

  JsonObject? validateResponseResult(
    String method,
    Object? value, {
    required AnalysisServerApiVersion version,
  }) {
    final descriptor = _availableDescriptor(
      _requests,
      method,
      version,
      kind: 'request',
    );
    return _validatePayload(
      descriptor['result'],
      value,
      path: '$method result',
    );
  }

  JsonObject? validateNotificationParams(
    String event,
    Object? value, {
    required AnalysisServerApiVersion version,
  }) {
    final descriptor = _availableDescriptor(
      _notifications,
      event,
      version,
      kind: 'notification',
    );
    return _validatePayload(
      descriptor['params'],
      value,
      path: '$event params',
    );
  }

  Map<String, Object?> get _requests => _map(_document['requests'], 'requests');

  Map<String, Object?> get _notifications =>
      _map(_document['notifications'], 'notifications');

  Map<String, Object?> get _types => _map(_document['types'], 'types');

  Map<String, Object?> get _enums => _map(_document['enums'], 'enums');

  bool _isAvailable(
    Map<String, Object?> descriptors,
    String name,
    AnalysisServerApiVersion version,
  ) {
    final descriptor = descriptors[name];
    if (descriptor is! Map<String, Object?>) {
      return false;
    }
    final introduced = _parseVersion(descriptor['introduced']);
    return analysisServerVersionPolicy.supports(version) &&
        introduced.compareTo(version) <= 0;
  }

  Map<String, Object?> _availableDescriptor(
    Map<String, Object?> descriptors,
    String name,
    AnalysisServerApiVersion version, {
    required String kind,
  }) {
    final descriptor = descriptors[name];
    if (descriptor is! Map<String, Object?>) {
      throw ToolingCodecError(
        'analysis_server_${kind}_unknown',
        'Unknown Analysis Server $kind: $name.',
      );
    }
    if (!_isAvailable(descriptors, name, version)) {
      throw ToolingVersionError(
        'analysis_server_${kind}_unavailable',
        'Analysis Server $kind is unavailable in API $version.',
      );
    }
    return descriptor;
  }

  JsonObject? _validatePayload(
    Object? shapeValue,
    Object? value, {
    required String path,
  }) {
    if (shapeValue == null) {
      if (value != null && value is! Map<String, Object?>) {
        throw ToolingSchemaError(
          'analysis_server_unexpected_payload',
          '$path must be an object when present.',
        );
      }
      return value == null
          ? null
          : freezeJsonObject(value as Map<String, Object?>);
    }
    if (value is! Map<String, Object?>) {
      throw ToolingSchemaError(
        'analysis_server_payload_required',
        '$path must be an object.',
      );
    }
    _validateShape(
      _map(shapeValue, path),
      value,
      path: path,
      depth: 0,
    );
    return freezeJsonObject(value);
  }

  void _validateShape(
    Map<String, Object?> shape,
    Object? value, {
    required String path,
    required int depth,
  }) {
    if (depth > 64) {
      throw ToolingResourceLimitError(
        'analysis_server_shape_depth',
        'Analysis Server value exceeds the validation depth limit.',
      );
    }
    switch (shape['kind']) {
      case 'any':
        freezeJsonValue(value);
      case 'ref':
        _validateReference(
          shape['name'] as String,
          value,
          path: path,
          depth: depth + 1,
        );
      case 'enum':
        if (value is! String) {
          _invalid(path, 'a string enum value');
        }
      case 'object':
        if (value is! Map<String, Object?>) {
          _invalid(path, 'an object');
        }
        final fields = _map(shape['fields'], '$path fields');
        for (final entry in fields.entries) {
          final field = _map(entry.value, '$path.${entry.key}');
          final present = value.containsKey(entry.key);
          if (field['required'] == true &&
              (!present || value[entry.key] == null)) {
            _invalid('$path.${entry.key}', 'a required value');
          }
          if (present && value[entry.key] != null) {
            _validateShape(
              _map(field['shape'], '$path.${entry.key} shape'),
              value[entry.key],
              path: '$path.${entry.key}',
              depth: depth + 1,
            );
          }
        }
        freezeJsonObject(value);
      case 'list':
        if (value is! List<Object?>) {
          _invalid(path, 'a list');
        }
        final item = _map(shape['item'], '$path item');
        for (var index = 0; index < value.length; index += 1) {
          _validateShape(
            item,
            value[index],
            path: '$path[$index]',
            depth: depth + 1,
          );
        }
      case 'map':
        if (value is! Map<String, Object?>) {
          _invalid(path, 'an object map');
        }
        final keyShape = _map(shape['key'], '$path key');
        final valueShape = _map(shape['value'], '$path value');
        for (final entry in value.entries) {
          _validateShape(
            keyShape,
            entry.key,
            path: '$path key',
            depth: depth + 1,
          );
          _validateShape(
            valueShape,
            entry.value,
            path: '$path.${entry.key}',
            depth: depth + 1,
          );
        }
      case 'union':
        final options =
            (shape['options'] as List<Object?>?) ?? const <Object?>[];
        for (final option in options) {
          try {
            _validateShape(
              _map(option, '$path union option'),
              value,
              path: path,
              depth: depth + 1,
            );
            return;
          } on ToolingSchemaError {
            // Try the next declared union member.
          }
        }
        _invalid(path, 'a declared union member');
      default:
        throw ToolingSchemaError(
          'analysis_server_shape_unknown',
          'Unknown Analysis Server shape at $path.',
        );
    }
  }

  void _validateReference(
    String name,
    Object? value, {
    required String path,
    required int depth,
  }) {
    switch (name) {
      case 'String':
      case 'FilePath':
        if (value is! String) {
          _invalid(path, 'a string');
        }
      case 'bool':
        if (value is! bool) {
          _invalid(path, 'a boolean');
        }
      case 'int':
        if (value is! int) {
          _invalid(path, 'an integer');
        }
      case 'double':
      case 'num':
        if (value is! num) {
          _invalid(path, 'a number');
        }
      case 'object':
        if (value is! Map<String, Object?>) {
          _invalid(path, 'an object');
        }
      default:
        final referenced = _types[name];
        if (referenced is Map<String, Object?>) {
          _validateShape(
            referenced,
            value,
            path: path,
            depth: depth + 1,
          );
        } else {
          // Common analyzer protocol types are imported by spec_input.html.
          // Their exact models are outside this generated local inventory, but
          // values must still remain immutable JSON-compatible data.
          freezeJsonValue(value);
        }
    }
  }

  Never _invalid(String path, String expectation) {
    throw ToolingSchemaError(
      'analysis_server_schema_invalid',
      '$path must be $expectation.',
    );
  }
}

Map<String, Object?> _map(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw ToolingSchemaError(
      'analysis_server_generated_inventory_invalid',
      'Generated Analysis Server $name is invalid.',
    );
  }
  return value;
}

Set<String> _stringSet(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const ToolingSchemaError(
      'analysis_server_generated_inventory_invalid',
      'Generated Analysis Server string inventory is invalid.',
    );
  }
  return Set<String>.unmodifiable(value.cast<String>());
}

AnalysisServerApiVersion _parseVersion(Object? value) {
  if (value is! String) {
    throw const ToolingVersionError(
      'analysis_server_generated_version_invalid',
      'Generated Analysis Server version is invalid.',
    );
  }
  final parts = value.split('.');
  if (parts.length != 3) {
    throw ToolingVersionError(
      'analysis_server_generated_version_invalid',
      'Generated Analysis Server version is invalid: $value.',
    );
  }
  return AnalysisServerApiVersion(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}
