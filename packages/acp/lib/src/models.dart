import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'generated/acp_inventory.g.dart';

/// Which ACP participant handles a method.
enum AcpMethodHandlerSide {
  agent,
  client,
  protocol,
}

/// Which participant sent a decoded ACP message.
enum AcpMessageRoot {
  agent,
  client,
  protocolLevel,
}

/// Stable schema bindings for one ACP method.
final class AcpMethodDescriptor {
  const AcpMethodDescriptor({
    required this.method,
    required this.handlerSide,
    required this.requestDefinition,
    required this.responseDefinition,
    required this.notificationDefinition,
  });

  final String method;
  final AcpMethodHandlerSide handlerSide;
  final String? requestDefinition;
  final String? responseDefinition;
  final String? notificationDefinition;

  bool get isNotification => notificationDefinition != null;
}

/// Every ACP stable-v1 method, sorted by wire method name.
final List<AcpMethodDescriptor> acpMethodDescriptors =
    List<AcpMethodDescriptor>.unmodifiable(
  acpGeneratedMethodMetadata.map((metadata) {
    final method = metadata['method'];
    final side = metadata['side'];
    if (method == null || side == null) {
      throw StateError('Generated ACP method metadata is incomplete.');
    }
    return AcpMethodDescriptor(
      method: method,
      handlerSide: AcpMethodHandlerSide.values.byName(side),
      requestDefinition: metadata['request'],
      responseDefinition: metadata['response'],
      notificationDefinition: metadata['notification'],
    );
  }),
);

/// Stable method lookup by exact wire name.
final Map<String, AcpMethodDescriptor> acpMethodsByName =
    Map<String, AcpMethodDescriptor>.unmodifiable(
  <String, AcpMethodDescriptor>{
    for (final descriptor in acpMethodDescriptors)
      descriptor.method: descriptor,
  },
);

/// Exact generated stable message-root names.
final Set<String> acpMessageRoots =
    Set<String>.unmodifiable(acpGeneratedMessageRoots);

/// Classification for every pinned stable definition.
final Map<String, String> acpDefinitionClassifications =
    Map<String, String>.unmodifiable(
  acpGeneratedDefinitionClassifications,
);

/// Immutable JSON-backed model validated against one named ACP definition.
abstract class AcpSchemaValue {
  const AcpSchemaValue(
    this.value, {
    required this.definitionName,
  });

  final JsonValue value;
  final String definitionName;

  JsonValue toJson() => value;

  @override
  String toString() => '$runtimeType($definitionName)';
}

/// One common-envelope and ACP-role validated wire message.
final class AcpDecodedMessage {
  const AcpDecodedMessage({
    required this.root,
    required this.message,
    required this.methodDescriptor,
  });

  final AcpMessageRoot root;
  final JsonRpcMessage message;
  final AcpMethodDescriptor? methodDescriptor;

  JsonObject toJson() => message.toJson();
}
