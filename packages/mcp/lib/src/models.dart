import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'generated/mcp_inventory.g.dart';

enum McpParticipant {
  client,
  server,
}

enum McpMessageRole {
  clientRequest,
  serverRequest,
  clientNotification,
  serverNotification,
  clientResult,
  serverResult,
}

final class McpMethodBinding {
  const McpMethodBinding({
    required this.method,
    required this.sender,
    required this.role,
    required this.kind,
    required this.definition,
    required this.resultDefinition,
  });

  final String method;
  final McpParticipant sender;
  final McpMessageRole role;
  final String kind;
  final String definition;
  final String? resultDefinition;

  bool get isRequest => kind == 'request';
  bool get isNotification => kind == 'notification';
}

final List<McpMethodBinding> mcpMethodBindings =
    List<McpMethodBinding>.unmodifiable(
  mcpGeneratedMethodMetadata.map(
    (metadata) => McpMethodBinding(
      method: metadata['method']!,
      sender: McpParticipant.values.byName(metadata['sender']!),
      role: McpMessageRole.values.byName(
        _lowerCamel(metadata['role']!),
      ),
      kind: metadata['kind']!,
      definition: metadata['definition']!,
      resultDefinition: metadata['result'],
    ),
  ),
);

final Map<String, List<McpMethodBinding>> mcpMethodBindingsByName =
    Map<String, List<McpMethodBinding>>.unmodifiable(
  <String, List<McpMethodBinding>>{
    for (final method
        in mcpMethodBindings.map((binding) => binding.method).toSet())
      method: List<McpMethodBinding>.unmodifiable(
        mcpMethodBindings.where((binding) => binding.method == method),
      ),
  },
);

final Set<String> mcpRoleDefinitions =
    Set<String>.unmodifiable(mcpGeneratedRoleDefinitions);

final Map<String, String> mcpDefinitionClassifications =
    Map<String, String>.unmodifiable(
  mcpGeneratedDefinitionClassifications,
);

abstract class McpSchemaValue {
  const McpSchemaValue(
    this.value, {
    required this.definitionName,
  });

  final JsonValue value;
  final String definitionName;

  JsonValue toJson() => value;

  @override
  String toString() => '$runtimeType($definitionName)';
}

final class McpDecodedMessage {
  const McpDecodedMessage({
    required this.role,
    required this.message,
    required this.methodBinding,
  });

  final McpMessageRole role;
  final JsonRpcMessage message;
  final McpMethodBinding methodBinding;

  JsonObject toJson() => message.toJson();
}

String _lowerCamel(String value) =>
    '${value.substring(0, 1).toLowerCase()}${value.substring(1)}';
