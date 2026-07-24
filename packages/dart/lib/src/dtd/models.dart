import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/availability.dart';
import '../common/errors.dart';
import '../common/source_identity.dart';
import 'generated/inventory.g.dart';
import 'method.dart';

const dtdInventoryRevision = dtdGeneratedInventoryRevision;
const dtdInventorySha256 = dtdGeneratedInventorySha256;
const dtdInventoryPolicy = DtdInventoryPolicy(
  inventoryRevision: dtdInventoryRevision,
);

const dtdMinimumSourceIdentity = DtdSourceIdentity(
  sourceRelease: dtdGeneratedMinimumSdkRelease,
  sourceRevision: dtdGeneratedMinimumSdkRevision,
  artifactSha256: dtdGeneratedMinimumDocumentSha256,
  inventoryRevision: dtdInventoryRevision,
);

const dtdCurrentSourceIdentity = DtdSourceIdentity(
  sourceRelease: dtdGeneratedCurrentSdkRelease,
  sourceRevision: dtdGeneratedCurrentSdkRevision,
  artifactSha256: dtdGeneratedCurrentDocumentSha256,
  inventoryRevision: dtdInventoryRevision,
);

final class DtdErrorCode {
  factory DtdErrorCode.parse(int code) => DtdErrorCode._(
        code: code,
        isKnown: DtdModelRegistry.instance.errorCodes.contains(code),
      );

  const DtdErrorCode._({required this.code, required this.isKnown});

  final int code;
  final bool isKnown;
}

final class DtdModelRegistry {
  DtdModelRegistry._()
      : _document =
            jsonDecode(dtdGeneratedInventoryJson) as Map<String, Object?> {
    if (_document['inventoryRevision'] != dtdInventoryRevision ||
        _document['inventorySha256'] != dtdInventorySha256) {
      throw const ToolingVersionError(
        'dtd_generated_identity_mismatch',
        'Generated DTD inventory identity is inconsistent.',
      );
    }
  }

  static final DtdModelRegistry instance = DtdModelRegistry._();

  final Map<String, Object?> _document;

  Set<String> get fixedMethodNames => Set<String>.unmodifiable(_methods.keys);

  Set<String> get typeNames => Set<String>.unmodifiable(_types.keys);

  Set<int> get errorCodes => Set<int>.unmodifiable(
        (_document['errorCodes']! as List<Object?>).cast<int>(),
      );

  DtdMethodDescriptor? method(String name) {
    final value = _methods[name];
    if (value is! Map<String, Object?>) {
      return null;
    }
    return DtdMethodDescriptor(
      name: name,
      kind: value['kind'] == 'notification'
          ? DtdMethodKind.notification
          : DtdMethodKind.request,
      resultType: value['resultType'] as String?,
    );
  }

  bool isDynamicServiceMethod(String name) =>
      !_methods.containsKey(name) &&
      RegExp(_dynamic['methodPattern']! as String).hasMatch(name);

  JsonObject validateParams(String method, Object? value) {
    final descriptor = _methods[method];
    if (descriptor == null) {
      if (!isDynamicServiceMethod(method)) {
        throw ToolingCodecError(
          'dtd_method_unknown',
          'DTD method is not fixed or a valid dynamic service extension.',
        );
      }
      if (value is! Map<String, Object?>) {
        throw const ToolingSchemaError(
          'dtd_dynamic_params_invalid',
          'DTD dynamic service params must be an object.',
        );
      }
      return _freezeObject(value);
    }
    if (value is! Map<String, Object?>) {
      throw const ToolingSchemaError(
        'dtd_params_invalid',
        'DTD fixed method params must be an object.',
      );
    }
    _validateObject(
      value,
      _object(
        (descriptor as Map<String, Object?>)['params'],
        '$method params',
      ),
      path: '$method params',
    );
    return _freezeObject(value);
  }

  JsonValue validateResult(String method, Object? value) {
    final descriptor = _methods[method];
    if (descriptor == null) {
      if (!isDynamicServiceMethod(method)) {
        throw const ToolingCodecError(
          'dtd_method_unknown',
          'DTD response method is unknown.',
        );
      }
      return _freezeValue(value);
    }
    final resultType =
        (descriptor as Map<String, Object?>)['resultType'] as String?;
    if (resultType == null) {
      if (value != null) {
        throw const ToolingSchemaError(
          'dtd_notification_result_invalid',
          'DTD notification does not declare a result.',
        );
      }
      return null;
    }
    if (value is! Map<String, Object?>) {
      throw const ToolingSchemaError(
        'dtd_result_invalid',
        'DTD fixed method result must be an object.',
      );
    }
    final shape = _types[resultType];
    if (shape is! Map<String, Object?>) {
      throw const ToolingVersionError(
        'dtd_result_type_unknown',
        'DTD result type is absent from the fixed inventory.',
      );
    }
    _validateObject(value, shape, path: '$method result');
    return _freezeObject(value);
  }

  Map<String, Object?> get _methods => _object(_document['methods'], 'methods');
  Map<String, Object?> get _types => _object(_document['types'], 'types');
  Map<String, Object?> get _dynamic =>
      _object(_document['dynamicService'], 'dynamicService');

  void _validateObject(
    Map<String, Object?> value,
    Map<String, Object?> fields, {
    required String path,
  }) {
    for (final key in value.keys) {
      if (!fields.containsKey(key)) {
        throw ToolingSchemaError(
          'dtd_schema_unknown_field',
          '$path contains an unknown field.',
        );
      }
    }
    for (final entry in fields.entries) {
      final descriptor = _object(entry.value, '$path.${entry.key}');
      final present = value.containsKey(entry.key);
      if (descriptor['required'] == true &&
          (!present || value[entry.key] == null)) {
        throw ToolingSchemaError(
          'dtd_schema_required_field',
          '$path is missing a required field.',
        );
      }
      if (present && value[entry.key] != null) {
        _validateScalar(
          descriptor['type'],
          value[entry.key],
          path: '$path.${entry.key}',
        );
      }
    }
  }

  void _validateScalar(Object? type, Object? value, {required String path}) {
    final valid = switch (type) {
      'string' => value is String,
      'int' => value is int,
      'object' => value is Map<String, Object?>,
      'stringList' =>
        value is List<Object?> && value.every((element) => element is String),
      'serviceName' =>
        value is String && value.isNotEmpty && !value.contains('.'),
      final Object literal
          when literal is String && literal.startsWith('literal:') =>
        value == literal.substring('literal:'.length),
      _ => false,
    };
    if (!valid) {
      throw ToolingSchemaError(
        'dtd_schema_invalid',
        '$path does not satisfy the fixed DTD inventory.',
      );
    }
    _freezeValue(value);
  }
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw ToolingVersionError(
      'dtd_generated_inventory_invalid',
      'Generated DTD inventory $label must be an object.',
    );
  }
  return value;
}

JsonObject _freezeObject(Map<String, Object?> value) {
  try {
    return freezeJsonObject(value);
  } on Object catch (error) {
    throw ToolingSchemaError(
      'dtd_json_value_invalid',
      'DTD value is not JSON-safe.',
      cause: error,
    );
  }
}

JsonValue _freezeValue(Object? value) {
  try {
    return freezeJsonValue(value);
  } on Object catch (error) {
    throw ToolingSchemaError(
      'dtd_json_value_invalid',
      'DTD value is not JSON-safe.',
      cause: error,
    );
  }
}
