import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/availability.dart';
import '../common/errors.dart';
import 'generated/inventory.g.dart';
import 'version.dart';

abstract class VmServiceSchemaValue {
  const VmServiceSchemaValue(
    this.value, {
    required this.definitionName,
  });

  final JsonObject value;
  final String definitionName;

  JsonObject toJson() => value;
}

final class VmServiceTypeValue {
  factory VmServiceTypeValue.parse(String value) {
    final normalized = value.startsWith('@') ? value.substring(1) : value;
    return VmServiceTypeValue._(
      value: value,
      isKnown:
          VmServiceModelRegistry.instance.currentTypeNames.contains(normalized),
    );
  }

  const VmServiceTypeValue._({
    required this.value,
    required this.isKnown,
  });

  final String value;
  final bool isKnown;
}

final class VmServiceEventKind {
  factory VmServiceEventKind.parse(String value) => VmServiceEventKind._(
        value: value,
        isKnown:
            VmServiceModelRegistry.instance.currentEventKinds.contains(value),
      );

  const VmServiceEventKind._({
    required this.value,
    required this.isKnown,
  });

  final String value;
  final bool isKnown;
}

final class VmServiceSentinel {
  VmServiceSentinel._(this.value);

  factory VmServiceSentinel.fromJson(Map<String, Object?> value) {
    if (value['type'] != 'Sentinel' ||
        value['kind'] is! String ||
        value['valueAsString'] is! String) {
      throw const ToolingSchemaError(
        'vm_service_sentinel_invalid',
        'VM Service Sentinel is malformed.',
      );
    }
    return VmServiceSentinel._(_freezeObject(value));
  }

  final JsonObject value;

  String get kind => value['kind']! as String;
  String get valueAsString => value['valueAsString']! as String;
}

final class VmServiceExtensionResult {
  VmServiceExtensionResult._(this.value);

  factory VmServiceExtensionResult.fromJson(Map<String, Object?> value) {
    if (value['type'] is! String) {
      throw const ToolingSchemaError(
        'vm_service_extension_result_invalid',
        'VM Service extension result requires a string type.',
      );
    }
    return VmServiceExtensionResult._(_freezeObject(value));
  }

  final JsonObject value;

  String get type => value['type']! as String;
}

final class VmServiceModelRegistry {
  VmServiceModelRegistry._()
      : _document = jsonDecode(vmServiceGeneratedInventoryJson)
            as Map<String, Object?> {
    final minimum = _object(_document['minimum'], 'minimum');
    final current = _object(_document['current'], 'current');
    if (minimum['runtimeVersion'] !=
            vmServiceMinimumRuntimeVersion.toString() ||
        current['runtimeVersion'] !=
            vmServiceCurrentRuntimeVersion.toString() ||
        minimum['revision'] != vmServiceMinimumSourceIdentity.sourceRevision ||
        current['revision'] != vmServiceCurrentSourceIdentity.sourceRevision) {
      throw const ToolingVersionError(
        'vm_service_generated_identity_mismatch',
        'Generated VM Service identity does not match the public pins.',
      );
    }
  }

  static final VmServiceModelRegistry instance = VmServiceModelRegistry._();

  final Map<String, Object?> _document;

  Set<String> get minimumRpcNames =>
      _strings(_object(_document['minimum'], 'minimum')['rpcNames']);
  Set<String> get currentRpcNames =>
      _strings(_object(_document['current'], 'current')['rpcNames']);
  Set<String> get minimumTypeNames =>
      _strings(_object(_document['minimum'], 'minimum')['typeNames']);
  Set<String> get currentTypeNames =>
      _strings(_object(_document['current'], 'current')['typeNames']);
  Set<String> get minimumEventKinds =>
      _strings(_object(_document['minimum'], 'minimum')['eventKinds']);
  Set<String> get currentEventKinds =>
      _strings(_object(_document['current'], 'current')['eventKinds']);
  Set<String> get currentOnlyRpcNames => _strings(_document['currentOnlyRpcs']);
  Set<String> get currentOnlyTypeNames =>
      _strings(_document['currentOnlyTypes']);
  Set<String> get unclassifiedDifferences =>
      _strings(_document['unclassifiedDifferences']);

  bool isRpcAvailable(String method, VmServiceWireVersion version) =>
      _isAvailable(_rpcs, method, version);

  bool isTypeAvailable(String type, VmServiceWireVersion version) =>
      _isAvailable(_types, type, version);

  bool isEventKindAvailable(String kind, VmServiceWireVersion version) =>
      _isAvailable(_eventKinds, kind, version);

  JsonObject validateParams(
    String method,
    Object? value, {
    VmServiceWireVersion version = vmServiceCurrentRuntimeVersion,
  }) {
    if (!_rpcs.containsKey(method)) {
      if (!_isExtensionMethod(method)) {
        throw const ToolingCodecError(
          'vm_service_method_unknown',
          'VM Service method is not fixed or a valid extension.',
        );
      }
    } else if (!isRpcAvailable(method, version)) {
      throw ToolingVersionError(
        'vm_service_method_unavailable',
        'VM Service method is unavailable in protocol $version.',
      );
    }
    if (value is! Map<String, Object?>) {
      throw const ToolingSchemaError(
        'vm_service_params_invalid',
        'VM Service params must be an object.',
      );
    }
    return _freezeObject(value);
  }

  JsonObject validateType(
    String type,
    Map<String, Object?> value, {
    VmServiceWireVersion version = vmServiceCurrentRuntimeVersion,
  }) {
    if (!isTypeAvailable(type, version)) {
      throw ToolingVersionError(
        'vm_service_type_unavailable',
        'VM Service type is unavailable in protocol $version.',
      );
    }
    final wireType = value['type'];
    if (wireType != null && wireType != type && wireType != '@$type') {
      throw const ToolingSchemaError(
        'vm_service_type_discriminator_invalid',
        'VM Service response type discriminator does not match its model.',
      );
    }
    return _freezeObject(value);
  }

  Object validateResult(
    String method,
    Object? value, {
    VmServiceWireVersion version = vmServiceCurrentRuntimeVersion,
  }) {
    final methodDescriptor = _rpcs[method];
    if (methodDescriptor == null) {
      if (!_isExtensionMethod(method)) {
        throw const ToolingCodecError(
          'vm_service_method_unknown',
          'VM Service response method is unknown.',
        );
      }
    } else if (!isRpcAvailable(method, version)) {
      throw ToolingVersionError(
        'vm_service_method_unavailable',
        'VM Service method is unavailable in protocol $version.',
      );
    }
    if (value is! Map<String, Object?> || value['type'] is! String) {
      throw const ToolingSchemaError(
        'vm_service_result_invalid',
        'VM Service result must be a typed object.',
      );
    }
    final type = value['type']! as String;
    final normalized = type.startsWith('@') ? type.substring(1) : type;
    if (methodDescriptor is Map<String, Object?>) {
      final resultTypes = _strings(methodDescriptor['resultTypes']);
      if (!resultTypes.contains(normalized)) {
        throw const ToolingSchemaError(
          'vm_service_result_type_invalid',
          'VM Service result type does not match the fixed RPC signature.',
        );
      }
    }
    if (type == 'Sentinel') {
      return VmServiceSentinel.fromJson(value);
    }
    final parsedType = VmServiceTypeValue.parse(type);
    if (!parsedType.isKnown) {
      return VmServiceExtensionResult.fromJson(value);
    }
    final validated = validateType(normalized, value, version: version);
    if (method == 'getVersion' &&
        (validated['major'] is! int || validated['minor'] is! int)) {
      throw const ToolingSchemaError(
        'vm_service_version_result_invalid',
        'VM Service Version result requires integer major and minor.',
      );
    }
    return validated;
  }

  VmServiceEventKind validateEventKind(
    String value, {
    VmServiceWireVersion version = vmServiceCurrentRuntimeVersion,
  }) {
    final kind = VmServiceEventKind.parse(value);
    if (kind.isKnown && !isEventKindAvailable(value, version)) {
      throw ToolingVersionError(
        'vm_service_event_unavailable',
        'VM Service event kind is unavailable in protocol $version.',
      );
    }
    return kind;
  }

  Map<String, Object?> get _rpcs => _object(_document['rpcs'], 'rpcs');
  Map<String, Object?> get _types => _object(_document['types'], 'types');
  Map<String, Object?> get _eventKinds =>
      _object(_document['eventKinds'], 'eventKinds');

  bool _isAvailable(
    Map<String, Object?> inventory,
    String name,
    VmServiceWireVersion version,
  ) {
    final descriptor = inventory[name];
    if (descriptor is! Map<String, Object?> ||
        !vmServiceVersionPolicy.supports(version)) {
      return false;
    }
    final introduced = _parseVersion(descriptor['introduced']);
    return introduced.compareTo(version) <= 0;
  }
}

bool _isExtensionMethod(String method) =>
    RegExp(r'^(?:ext|service)\.[A-Za-z0-9_.-]+$').hasMatch(method);

VmServiceWireVersion _parseVersion(Object? value) {
  if (value is! String) {
    throw const ToolingVersionError(
      'vm_service_generated_version_invalid',
      'Generated VM Service version is invalid.',
    );
  }
  final parts = value.split('.');
  if (parts.length != 2) {
    throw const ToolingVersionError(
      'vm_service_generated_version_invalid',
      'Generated VM Service version is invalid.',
    );
  }
  return VmServiceWireVersion(int.parse(parts[0]), int.parse(parts[1]));
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw ToolingVersionError(
      'vm_service_generated_inventory_invalid',
      'Generated VM Service $label must be an object.',
    );
  }
  return value;
}

Set<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((element) => element is! String)) {
    throw const ToolingVersionError(
      'vm_service_generated_inventory_invalid',
      'Generated VM Service string inventory is invalid.',
    );
  }
  return Set<String>.unmodifiable(value.cast<String>());
}

JsonObject _freezeObject(Map<String, Object?> value) {
  try {
    return freezeJsonObject(value);
  } on Object catch (error) {
    throw ToolingSchemaError(
      'vm_service_json_value_invalid',
      'VM Service value is not JSON-safe.',
      cause: error,
    );
  }
}
