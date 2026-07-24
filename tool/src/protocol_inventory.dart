import 'dart:convert';
import 'dart:io';

import 'dap_inventory.dart';
import 'dart_tooling_inventory.dart';
import 'lsp_inventory.dart';

Map<String, Object?> buildPhase2bToolingInventory(Directory root) =>
    <String, Object?>{
      'formatVersion': 1,
      'lsp': buildLspInventory(root).toJson(),
      'dap': buildDapInventory(root).toJson(),
      'dartTooling': buildDartToolingInventory(root).toJson(),
    };

final class ProtocolInventory {
  const ProtocolInventory({
    required this.acpDefinitionNames,
    required this.acpMethodNames,
    required this.acpMessageRoots,
    required this.acpMethodBindings,
    required this.mcpDefinitionNames,
    required this.mcpRoleDefinitions,
    required this.mcpMethodBindings,
    required this.mcpClientConformanceScenarios,
    required this.mcpServerConformanceScenarios,
    required this.mcpPendingServerScenarios,
  });

  final Set<String> acpDefinitionNames;
  final Set<String> acpMethodNames;
  final Set<String> acpMessageRoots;
  final List<AcpMethodBinding> acpMethodBindings;
  final Set<String> mcpDefinitionNames;
  final Set<String> mcpRoleDefinitions;
  final List<McpMethodBinding> mcpMethodBindings;
  final List<String> mcpClientConformanceScenarios;
  final List<String> mcpServerConformanceScenarios;
  final Set<String> mcpPendingServerScenarios;

  int get acpDefinitionCount => acpDefinitionNames.length;
  int get acpMethodCount => acpMethodNames.length;
  int get mcpDefinitionCount => mcpDefinitionNames.length;

  Map<String, Object?> toJson() => <String, Object?>{
        'formatVersion': 1,
        'acp': <String, Object?>{
          'schemaRelease': 'schema-v1.20.0',
          'wireVersion': '1',
          'definitionCount': acpDefinitionCount,
          'definitions': _sorted(acpDefinitionNames),
          'methodCount': acpMethodCount,
          'methods': _sorted(acpMethodNames),
          'messageRoots': _sorted(acpMessageRoots),
          'methodBindings': <Map<String, Object?>>[
            for (final binding in acpMethodBindings) binding.toJson(),
          ],
        },
        'mcp': <String, Object?>{
          'specificationVersion': '2025-11-25',
          'definitionCount': mcpDefinitionCount,
          'definitions': _sorted(mcpDefinitionNames),
          'roleDefinitions': _sorted(mcpRoleDefinitions),
          'methodBindings': <Map<String, Object?>>[
            for (final binding in mcpMethodBindings) binding.toJson(),
          ],
          'officialConformance': <String, Object?>{
            'harnessVersion': 'v0.1.16',
            'client': mcpClientConformanceScenarios,
            'server': mcpServerConformanceScenarios,
            'serverPendingInHarness': _sorted(mcpPendingServerScenarios),
          },
        },
      };
}

final class AcpMethodBinding {
  const AcpMethodBinding({
    required this.method,
    required this.side,
    required this.definition,
    required this.kind,
  });

  final String method;
  final String side;
  final String definition;
  final String kind;

  Map<String, Object?> toJson() => <String, Object?>{
        'method': method,
        'side': side,
        'definition': definition,
        'kind': kind,
      };
}

final class McpMethodBinding {
  const McpMethodBinding({
    required this.method,
    required this.sender,
    required this.role,
    required this.definition,
    required this.kind,
    required this.resultDefinition,
  });

  final String method;
  final String sender;
  final String role;
  final String definition;
  final String kind;
  final String? resultDefinition;

  Map<String, Object?> toJson() => <String, Object?>{
        'method': method,
        'sender': sender,
        'role': role,
        'definition': definition,
        'kind': kind,
        if (resultDefinition != null) 'resultDefinition': resultDefinition,
      };
}

ProtocolInventory buildProtocolInventory(Directory root) {
  final acpSchema = _readObject(
    root,
    'tool/upstream/protocols/acp/schema-v1.20.0/schema.json',
  );
  final acpMeta = _readObject(
    root,
    'tool/upstream/protocols/acp/schema-v1.20.0/meta.json',
  );
  final mcpSchema = _readObject(
    root,
    'tool/upstream/protocols/mcp/2025-11-25/schema.json',
  );
  final scenarios = _readObject(
    root,
    'tool/upstream/protocols/mcp-conformance/v0.1.16/scenarios.json',
  );

  final acpDefinitions = _object(acpSchema[r'$defs'], r'ACP $defs');
  final acpRoots = _list(acpSchema['anyOf'], 'ACP anyOf')
      .map((entry) => _object(entry, 'ACP root')['title'])
      .whereType<String>()
      .toSet();
  final acpMethods = <String>{};
  for (final sectionName in <String>[
    'agentMethods',
    'clientMethods',
    'protocolMethods',
  ]) {
    final section = _object(acpMeta[sectionName], 'ACP $sectionName');
    acpMethods.addAll(section.values.whereType<String>());
  }
  final acpMethodBindings = <AcpMethodBinding>[];
  for (final entry in acpDefinitions.entries) {
    final definition = _object(entry.value, 'ACP definition ${entry.key}');
    final method = definition['x-method'];
    if (method == null) {
      continue;
    }
    final side = definition['x-side'];
    if (method is! String ||
        !acpMethods.contains(method) ||
        side is! String ||
        !const <String>{'agent', 'client', 'protocol'}.contains(side)) {
      throw FormatException(
        'ACP method metadata is invalid for ${entry.key}.',
      );
    }
    final kind = entry.key.endsWith('Notification')
        ? 'notification'
        : entry.key.endsWith('Request')
            ? 'request'
            : entry.key.endsWith('Response')
                ? 'response'
                : null;
    if (kind == null) {
      throw FormatException(
        'ACP method definition has no recognized kind: ${entry.key}.',
      );
    }
    acpMethodBindings.add(
      AcpMethodBinding(
        method: method,
        side: side,
        definition: entry.key,
        kind: kind,
      ),
    );
  }
  acpMethodBindings.sort((left, right) {
    final methodOrder = left.method.compareTo(right.method);
    return methodOrder != 0
        ? methodOrder
        : left.definition.compareTo(right.definition);
  });
  _validateAcpMethodBindings(acpMethods, acpMethodBindings);

  final mcpDefinitions = _object(mcpSchema[r'$defs'], r'MCP $defs');
  const mcpRoles = <String>{
    'ClientRequest',
    'ServerRequest',
    'ClientNotification',
    'ServerNotification',
    'ClientResult',
    'ServerResult',
  };
  if (!mcpDefinitions.keys.toSet().containsAll(mcpRoles)) {
    throw const FormatException('MCP role definitions are incomplete.');
  }
  final mcpSource = _readMcpSource(root);
  validateMcpEntryRefs(mcpSchema, mcpSource.entryRefs);
  final mcpMethodBindings = <McpMethodBinding>[];
  for (final role in <(String, String, String)>[
    ('ClientRequest', 'client', 'request'),
    ('ServerRequest', 'server', 'request'),
    ('ClientNotification', 'client', 'notification'),
    ('ServerNotification', 'server', 'notification'),
  ]) {
    for (final definitionName in _mcpRoleReferences(
      mcpDefinitions,
      role.$1,
    )) {
      final definition = _object(
        mcpDefinitions[definitionName],
        'MCP definition $definitionName',
      );
      final properties = _object(
        definition['properties'],
        'MCP definition $definitionName properties',
      );
      final methodSchema = _object(
        properties['method'],
        'MCP definition $definitionName method',
      );
      final method = methodSchema['const'];
      if (method is! String || method.isEmpty) {
        throw FormatException(
          'MCP definition $definitionName has no fixed method.',
        );
      }
      mcpMethodBindings.add(
        McpMethodBinding(
          method: method,
          sender: role.$2,
          role: role.$1,
          definition: definitionName,
          kind: role.$3,
          resultDefinition: role.$3 == 'request'
              ? _mcpResultDefinition(definitionName, mcpDefinitions)
              : null,
        ),
      );
    }
  }
  mcpMethodBindings.sort((left, right) {
    final methodOrder = left.method.compareTo(right.method);
    if (methodOrder != 0) {
      return methodOrder;
    }
    final senderOrder = left.sender.compareTo(right.sender);
    return senderOrder != 0
        ? senderOrder
        : left.definition.compareTo(right.definition);
  });

  return ProtocolInventory(
    acpDefinitionNames: acpDefinitions.keys.toSet(),
    acpMethodNames: acpMethods,
    acpMessageRoots: acpRoots,
    acpMethodBindings: List<AcpMethodBinding>.unmodifiable(
      acpMethodBindings,
    ),
    mcpDefinitionNames: mcpDefinitions.keys.toSet(),
    mcpRoleDefinitions: mcpRoles,
    mcpMethodBindings: List<McpMethodBinding>.unmodifiable(
      mcpMethodBindings,
    ),
    mcpClientConformanceScenarios: _stringList(
      scenarios['client'],
      'conformance client scenarios',
    ),
    mcpServerConformanceScenarios: _stringList(
      scenarios['server'],
      'conformance server scenarios',
    ),
    mcpPendingServerScenarios: _stringList(
      scenarios['serverPendingInHarness'],
      'conformance pending server scenarios',
    ).toSet(),
  );
}

List<String> _mcpRoleReferences(
  Map<String, Object?> definitions,
  String role,
) {
  final roleDefinition = _object(definitions[role], 'MCP role $role');
  final alternatives = _list(roleDefinition['anyOf'], 'MCP role $role anyOf');
  const prefix = r'#/$defs/';
  return <String>[
    for (final alternative in alternatives)
      switch (_object(alternative, 'MCP role $role member')[r'$ref']) {
        final String reference when reference.startsWith(prefix) =>
          reference.substring(prefix.length),
        final Object? reference => throw FormatException(
            'MCP role $role has invalid reference $reference.',
          ),
      },
  ];
}

String _mcpResultDefinition(
  String requestDefinition,
  Map<String, Object?> definitions,
) {
  if (!requestDefinition.endsWith('Request')) {
    throw FormatException(
      'MCP request definition has an unexpected name: $requestDefinition.',
    );
  }
  final resultDefinition =
      '${requestDefinition.substring(0, requestDefinition.length - 7)}Result';
  return definitions.containsKey(resultDefinition)
      ? resultDefinition
      : 'EmptyResult';
}

void _validateAcpMethodBindings(
  Set<String> methods,
  List<AcpMethodBinding> bindings,
) {
  final bindingsByMethod = <String, List<AcpMethodBinding>>{};
  for (final binding in bindings) {
    bindingsByMethod.putIfAbsent(binding.method, () => <AcpMethodBinding>[])
      ..add(binding);
  }
  if (bindingsByMethod.keys.toSet().length != methods.length ||
      !bindingsByMethod.keys.toSet().containsAll(methods)) {
    throw const FormatException(
      'ACP schema method bindings do not cover meta.json exactly.',
    );
  }
  for (final entry in bindingsByMethod.entries) {
    final sides = entry.value.map((binding) => binding.side).toSet();
    final kinds = entry.value.map((binding) => binding.kind).toSet();
    final isNotification = kinds.contains('notification');
    final validKinds = isNotification
        ? kinds.length == 1 && entry.value.length == 1
        : kinds.length == 2 &&
            kinds.containsAll(const <String>{'request', 'response'}) &&
            entry.value.length == 2;
    if (sides.length != 1 || !validKinds) {
      throw FormatException(
        'ACP method ${entry.key} has inconsistent schema bindings.',
      );
    }
  }
}

void validateMcpEntryRefs(
  Map<String, Object?> schema,
  Iterable<String> entryRefs,
) {
  final definitions = _object(schema[r'$defs'], r'MCP $defs');
  final refs = entryRefs.toList(growable: false);
  if (refs.isEmpty) {
    throw const FormatException(
      r'MCP validation requires an explicit #/$defs entry reference.',
    );
  }

  final definitionRef = RegExp(r'^#/\$defs/([^/]+)$');
  for (final ref in refs) {
    final match = definitionRef.firstMatch(ref);
    final definitionName = match?.group(1);
    if (definitionName == null || !definitions.containsKey(definitionName)) {
      throw FormatException(
        'MCP entry reference must identify JSONRPCMessage, a role union, '
        r'or a concrete #/$defs definition: '
        '$ref',
      );
    }
  }
}

_McpSource _readMcpSource(Directory root) {
  final sourceLock = _readObject(
    root,
    'tool/upstream/protocols/sources.json',
  );
  final sources = _list(sourceLock['sources'], 'protocol sources');
  for (final sourceValue in sources) {
    final source = _object(sourceValue, 'protocol source');
    if (source['sourceId'] == 'mcp-2025-11-25') {
      return _McpSource(
        _stringList(source['entryRefs'], 'MCP entry references'),
      );
    }
  }
  throw const FormatException(
    'Protocol source lock is missing mcp-2025-11-25.',
  );
}

final class _McpSource {
  const _McpSource(this.entryRefs);

  final List<String> entryRefs;
}

Map<String, Object?> _readObject(Directory root, String relativePath) {
  final file = File.fromUri(root.absolute.uri.resolve(relativePath));
  return _object(jsonDecode(file.readAsStringSync()), relativePath);
}

Map<String, Object?> _object(Object? value, String location) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$location must be a JSON object.');
  }
  return value;
}

List<Object?> _list(Object? value, String location) {
  if (value is! List<Object?>) {
    throw FormatException('$location must be a JSON array.');
  }
  return value;
}

List<String> _stringList(Object? value, String location) {
  final values = _list(value, location);
  final result = <String>[];
  for (var index = 0; index < values.length; index += 1) {
    final item = values[index];
    if (item is! String || item.isEmpty) {
      throw FormatException('$location[$index] must be a non-empty string.');
    }
    result.add(item);
  }
  if (result.toSet().length != result.length) {
    throw FormatException('$location contains duplicate values.');
  }
  return List<String>.unmodifiable(result);
}

List<String> _sorted(Iterable<String> values) =>
    (values.toList()..sort()).toList(growable: false);
