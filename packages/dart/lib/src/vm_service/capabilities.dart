import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/availability.dart';
import '../common/errors.dart';
import 'models.dart';

final class VmServiceSupportedProtocol {
  const VmServiceSupportedProtocol({
    required this.name,
    required this.major,
    required this.minor,
  });

  final String name;
  final int major;
  final int minor;
}

/// Immutable VM Service version and middleware protocol snapshot.
final class VmServiceCapabilitySnapshot {
  VmServiceCapabilitySnapshot._({
    required this.connectionId,
    required this.generation,
    required this.wireVersion,
    required this.protocols,
    required this.rawResult,
  });

  factory VmServiceCapabilitySnapshot.fromResult({
    required int connectionId,
    required VmServiceWireVersion wireVersion,
    required Map<String, Object?> result,
  }) {
    if (result['type'] != 'ProtocolList' ||
        result['protocols'] is! List<Object?>) {
      throw const ToolingSchemaError(
        'vm_service_protocol_list_invalid',
        'VM Service ProtocolList result is malformed.',
      );
    }
    final protocols = <VmServiceSupportedProtocol>[];
    for (final value in result['protocols']! as List<Object?>) {
      if (value is! Map<String, Object?> ||
          value['protocolName'] is! String ||
          value['major'] is! int ||
          value['minor'] is! int) {
        throw const ToolingSchemaError(
          'vm_service_supported_protocol_invalid',
          'VM Service supported protocol entry is malformed.',
        );
      }
      protocols.add(
        VmServiceSupportedProtocol(
          name: value['protocolName']! as String,
          major: value['major']! as int,
          minor: value['minor']! as int,
        ),
      );
    }
    return VmServiceCapabilitySnapshot._(
      connectionId: connectionId,
      generation: 1,
      wireVersion: wireVersion,
      protocols: List<VmServiceSupportedProtocol>.unmodifiable(protocols),
      rawResult: freezeJsonObject(result),
    );
  }

  final int connectionId;
  final int generation;
  final VmServiceWireVersion wireVersion;
  final List<VmServiceSupportedProtocol> protocols;
  final JsonObject rawResult;

  bool supportsRpc(String method) =>
      VmServiceModelRegistry.instance.isRpcAvailable(method, wireVersion);

  bool supportsProtocol(
    String name, {
    int? minimumMajor,
    int? minimumMinor,
  }) {
    for (final protocol in protocols) {
      if (protocol.name != name) {
        continue;
      }
      if (minimumMajor != null && protocol.major < minimumMajor) {
        return false;
      }
      if (minimumMajor != null &&
          protocol.major == minimumMajor &&
          minimumMinor != null &&
          protocol.minor < minimumMinor) {
        return false;
      }
      return true;
    }
    return false;
  }
}
