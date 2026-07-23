import 'dart:convert';
import 'dart:io';

import 'protocol_inventory.dart';
import 'protocol_sources.dart';

final class ProtocolGeneratedCheckResult {
  const ProtocolGeneratedCheckResult(this.differences);

  final List<String> differences;

  bool get isClean => differences.isEmpty;
}

Map<String, String> buildProtocolGeneratedOutputs(Directory root) {
  final sourceViolations = validateProtocolSources(root);
  if (sourceViolations.isNotEmpty) {
    throw StateError(
      'Protocol source validation failed: '
      '${sourceViolations.map((violation) => violation.toString()).join('; ')}',
    );
  }
  final inventory = buildProtocolInventory(root);
  final acpSchemaText = File.fromUri(
    root.absolute.uri.resolve(
      'tool/upstream/protocols/acp/schema-v1.20.0/schema.json',
    ),
  ).readAsStringSync();
  final acpSchema = jsonDecode(acpSchemaText) as Map<String, Object?>;
  final mcpSchemaText = File.fromUri(
    root.absolute.uri.resolve(
      'tool/upstream/protocols/mcp/2025-11-25/schema.json',
    ),
  ).readAsStringSync();
  final mcpSchema = jsonDecode(mcpSchemaText) as Map<String, Object?>;
  return <String, String>{
    'compatibility/upstream/phase-2a-protocol-inventory.json':
        '${const JsonEncoder.withIndent('  ').convert(inventory.toJson())}\n',
    'packages/acp/lib/src/generated/acp_inventory.g.dart':
        _buildAcpInventory(inventory),
    'packages/acp/lib/src/generated/acp_schema.g.dart':
        _buildAcpSchema(acpSchemaText),
    'packages/acp/lib/src/generated/acp_models.g.dart':
        _buildAcpModels(acpSchema),
    'packages/acp/test/fixtures/golden/stable_messages.json':
        _buildAcpGoldenFixtures(inventory, acpSchema),
    'packages/mcp/lib/src/generated/mcp_inventory.g.dart':
        _buildMcpInventory(inventory),
    'packages/mcp/lib/src/generated/mcp_schema.g.dart':
        _buildMcpSchema(mcpSchemaText),
    'packages/mcp/lib/src/generated/mcp_models.g.dart':
        _buildMcpModels(mcpSchema),
    'packages/mcp/test/fixtures/golden/stable_messages.json':
        _buildMcpGoldenFixtures(inventory, mcpSchema),
  };
}

void writeProtocolGeneratedOutputs(Directory root) {
  for (final entry in buildProtocolGeneratedOutputs(root).entries) {
    final file = File.fromUri(root.absolute.uri.resolve(entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
}

ProtocolGeneratedCheckResult checkProtocolGeneratedOutputs(Directory root) {
  final differences = <String>[];
  final temporaryOutput = Directory.systemTemp.createTempSync(
    'pigcode_protocol_codegen_check_',
  );
  try {
    for (final entry in buildProtocolGeneratedOutputs(root).entries) {
      final expectedFile = File.fromUri(
        temporaryOutput.absolute.uri.resolve(entry.key),
      );
      expectedFile.parent.createSync(recursive: true);
      expectedFile.writeAsStringSync(entry.value);

      final trackedFile = File.fromUri(root.absolute.uri.resolve(entry.key));
      if (!trackedFile.existsSync()) {
        differences.add('missing ${entry.key}');
        continue;
      }
      if (!_sameBytes(
        trackedFile.readAsBytesSync(),
        expectedFile.readAsBytesSync(),
      )) {
        differences.add('changed ${entry.key}');
      }
    }
  } finally {
    temporaryOutput.deleteSync(recursive: true);
  }
  return ProtocolGeneratedCheckResult(
    List<String>.unmodifiable(differences),
  );
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

String _buildAcpInventory(ProtocolInventory inventory) {
  final buffer = StringBuffer(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// Source: ACP schema-v1.20.0, generator format 1.\n\n',
  )
    ..writeln('const acpGeneratedSchemaRelease = '
        "'schema-v1.20.0';")
    ..writeln('const acpGeneratedDefinitionNames = <String>{');
  _writeStrings(buffer, inventory.acpDefinitionNames);
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('const acpGeneratedMethodNames = <String>{');
  _writeStrings(buffer, inventory.acpMethodNames);
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('const acpGeneratedMessageRoots = <String>{');
  _writeStrings(buffer, inventory.acpMessageRoots);
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln(
      'const acpGeneratedMethodMetadata = <Map<String, String?>>[',
    );
  final bindingsByMethod = <String, List<AcpMethodBinding>>{};
  for (final binding in inventory.acpMethodBindings) {
    bindingsByMethod
        .putIfAbsent(binding.method, () => <AcpMethodBinding>[])
        .add(binding);
  }
  for (final method in bindingsByMethod.keys.toList()..sort()) {
    final bindings = bindingsByMethod[method]!;
    String? definitionFor(String kind) {
      for (final binding in bindings) {
        if (binding.kind == kind) {
          return binding.definition;
        }
      }
      return null;
    }

    buffer
      ..writeln('  <String, String?>{')
      ..writeln("    'method': '${_escapeDartString(method)}',")
      ..writeln(
        "    'side': '${_escapeDartString(bindings.first.side)}',",
      )
      ..writeln(
        "    'request': ${_dartNullableString(definitionFor('request'))},",
      )
      ..writeln(
        "    'response': ${_dartNullableString(definitionFor('response'))},",
      )
      ..writeln(
        "    'notification': "
        "${_dartNullableString(definitionFor('notification'))},",
      )
      ..writeln('  },');
  }
  buffer
    ..writeln('];')
    ..writeln()
    ..writeln(
      'const acpGeneratedDefinitionClassifications = <String, String>{',
    );
  final typedDefinitions =
      inventory.acpMethodBindings.map((binding) => binding.definition).toSet();
  for (final definition in inventory.acpDefinitionNames.toList()..sort()) {
    final classification =
        typedDefinitions.contains(definition) ? 'typed' : 'validated-extension';
    buffer.writeln(
      "  '${_escapeDartString(definition)}': '$classification',",
    );
  }
  buffer.writeln('};');
  return buffer.toString();
}

String _buildAcpSchema(String schemaText) => <String>[
      '// GENERATED CODE - DO NOT MODIFY BY HAND.',
      '// Source: ACP schema-v1.20.0, generator format 1.',
      '',
      "const acpGeneratedSchemaJson = r'''$schemaText''';",
      '',
    ].join('\n');

String _buildAcpModels(Map<String, Object?> schema) {
  final definitions = (schema[r'$defs']! as Map<String, Object?>).keys.toList()
    ..sort();
  final buffer = StringBuffer(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// Source: ACP schema-v1.20.0, generator format 1.\n\n'
    "import 'package:pigcode_ai_protocol_utils/"
    "pigcode_ai_protocol_utils.dart';\n\n"
    "import '../models.dart';\n"
    "import '../schema.dart';\n\n",
  );
  for (final definition in definitions) {
    final className = 'Acp$definition';
    buffer
      ..writeln('/// Validated ACP `$definition` value.')
      ..writeln('final class $className extends AcpSchemaValue {')
      ..writeln('  factory $className.fromJson(')
      ..writeln('    JsonValue value,')
      ..writeln('  ) {')
      ..writeln('    return $className._(')
      ..writeln(
        '      AcpSchema.instance.validateDefinition(',
      )
      ..writeln("        '$definition',")
      ..writeln('        value,')
      ..writeln('      ),')
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $className._(')
      ..writeln('    super.value,')
      ..writeln('  ) : super(')
      ..writeln("          definitionName: '$definition',")
      ..writeln('        );')
      ..writeln('}')
      ..writeln();
  }
  return '${buffer.toString().trimRight()}\n';
}

String _buildAcpGoldenFixtures(
  ProtocolInventory inventory,
  Map<String, Object?> schema,
) {
  final sampler = _AcpSchemaSampler(schema);
  final bindingsByMethod = <String, List<AcpMethodBinding>>{};
  for (final binding in inventory.acpMethodBindings) {
    bindingsByMethod
        .putIfAbsent(binding.method, () => <AcpMethodBinding>[])
        .add(binding);
  }
  var requestId = 1;
  final cases = <Map<String, Object?>>[];
  for (final method in bindingsByMethod.keys.toList()..sort()) {
    final bindings = bindingsByMethod[method]!;
    for (final kind in const <String>[
      'request',
      'response',
      'notification',
    ]) {
      final matching = bindings.where((binding) => binding.kind == kind);
      if (matching.isEmpty) {
        continue;
      }
      final binding = matching.single;
      final senderRoot = switch ((kind, binding.side)) {
        ('request' || 'notification', 'agent') => 'client',
        ('request' || 'notification', 'client') => 'agent',
        ('request' || 'notification', 'protocol') => 'protocolLevel',
        ('response', 'agent') => 'agent',
        ('response', 'client') => 'client',
        ('response', 'protocol') => 'protocolLevel',
        _ => throw StateError('Unsupported ACP golden binding.'),
      };
      final envelope = <String, Object?>{'jsonrpc': '2.0'};
      switch (kind) {
        case 'request':
          envelope
            ..['id'] = requestId++
            ..['method'] = method
            ..['params'] = sampler.sampleDefinition(binding.definition);
        case 'response':
          envelope
            ..['id'] = requestId++
            ..['result'] = sampler.sampleDefinition(binding.definition);
        case 'notification':
          envelope
            ..['method'] = method
            ..['params'] = sampler.sampleDefinition(binding.definition);
      }
      cases.add(<String, Object?>{
        'id': '$kind:$method',
        'kind': kind,
        'root': senderRoot,
        'method': method,
        'definition': binding.definition,
        if (kind == 'response') 'responseMethod': method,
        'envelope': envelope,
      });
    }
  }

  final definitionSamples = <String, Object?>{};
  for (final definition in inventory.acpDefinitionNames.toList()..sort()) {
    definitionSamples[definition] = sampler.sampleDefinition(definition);
  }
  return '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'formatVersion': 1,
        'source': <String, Object?>{
          'release': 'schema-v1.20.0',
          'sha256':
              '92c1dfcda10dd47e99127500a3763da2b471f9ac61e12b9bf0430c32cf953796',
        },
        'cases': cases,
        'definitionSamples': definitionSamples,
      })}\n';
}

final class _AcpSchemaSampler {
  _AcpSchemaSampler(Map<String, Object?> root)
      : definitions = root[r'$defs']! as Map<String, Object?>;

  final Map<String, Object?> definitions;
  final Map<String, Object?> _cache = <String, Object?>{};
  final Set<String> _active = <String>{};

  Object? sampleDefinition(String name) {
    if (_cache.containsKey(name)) {
      return _cache[name];
    }
    if (!_active.add(name)) {
      return <String, Object?>{};
    }
    final definition = definitions[name];
    if (definition is! Map<String, Object?>) {
      throw StateError('ACP definition is not an object: $name');
    }
    try {
      final sample = _sample(definition);
      _cache[name] = sample;
      return sample;
    } finally {
      _active.remove(name);
    }
  }

  Object? _sample(Map<String, Object?> schema) {
    Object? result;
    final reference = schema[r'$ref'];
    if (reference is String) {
      const prefix = r'#/$defs/';
      if (!reference.startsWith(prefix)) {
        throw StateError('Unsupported ACP schema reference: $reference');
      }
      result = sampleDefinition(reference.substring(prefix.length));
    } else if (schema.containsKey('const')) {
      result = schema['const'];
    } else if (schema.containsKey('default')) {
      result = schema['default'];
    } else if (schema['enum'] case final List<Object?> values
        when values.isNotEmpty) {
      result = values.first;
    } else {
      final alternatives = schema['oneOf'] ?? schema['anyOf'];
      if (alternatives is List<Object?> && alternatives.isNotEmpty) {
        result = _sampleObject(alternatives.first);
      } else {
        result = _sampleByType(schema);
      }
    }

    final required = schema['required'];
    final properties = schema['properties'];
    if (required is List<Object?> &&
        properties is Map<String, Object?> &&
        required.isNotEmpty) {
      final object = result is Map<String, Object?>
          ? Map<String, Object?>.from(result)
          : <String, Object?>{};
      for (final propertyName in required.cast<String>()) {
        object.putIfAbsent(
          propertyName,
          () => _sampleObject(properties[propertyName]),
        );
      }
      result = object;
    }

    final allOf = schema['allOf'];
    if (allOf is List<Object?>) {
      for (final component in allOf) {
        result = _mergeSamples(result, _sampleObject(component));
      }
    }
    return result;
  }

  Object? _sampleByType(Map<String, Object?> schema) {
    Object? type = schema['type'];
    if (type is List<Object?>) {
      type = type.cast<String>().firstWhere(
            (candidate) => candidate != 'null',
            orElse: () => 'null',
          );
    }
    if (type == null && schema['properties'] is Map<String, Object?>) {
      type = 'object';
    }
    return switch (type) {
      'object' => <String, Object?>{},
      'array' => <Object?>[
          for (var index = 0;
              index < (schema['minItems'] as int? ?? 0);
              index += 1)
            _sampleObject(schema['items']),
        ],
      'string' => List<String>.filled(
          schema['minLength'] as int? ?? 0,
          'x',
        ).join(),
      'integer' => schema['minimum'] as num? ?? 0,
      'number' => (schema['minimum'] as num? ?? 0).toDouble(),
      'boolean' => false,
      'null' => null,
      _ => <String, Object?>{},
    };
  }

  Object? _sampleObject(Object? value) {
    if (value is! Map<String, Object?>) {
      return null;
    }
    return _sample(value);
  }

  Object? _mergeSamples(Object? left, Object? right) {
    if (left is Map<String, Object?> && right is Map<String, Object?>) {
      return <String, Object?>{...left, ...right};
    }
    return right;
  }
}

String _buildMcpInventory(ProtocolInventory inventory) {
  final buffer = StringBuffer(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// Source: MCP 2025-11-25 and conformance v0.1.16, '
    'generator format 1.\n\n',
  )
    ..writeln('const mcpGeneratedSpecificationVersion = '
        "'2025-11-25';")
    ..writeln('const mcpGeneratedDefinitionNames = <String>{');
  _writeStrings(buffer, inventory.mcpDefinitionNames);
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('const mcpGeneratedRoleDefinitions = <String>{');
  _writeStrings(buffer, inventory.mcpRoleDefinitions);
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('const mcpGeneratedClientConformanceScenarios = <String>[');
  _writeStrings(buffer, inventory.mcpClientConformanceScenarios);
  buffer
    ..writeln('];')
    ..writeln()
    ..writeln('const mcpGeneratedServerConformanceScenarios = <String>[');
  _writeStrings(buffer, inventory.mcpServerConformanceScenarios);
  buffer
    ..writeln('];')
    ..writeln()
    ..writeln(
      'const mcpGeneratedMethodMetadata = <Map<String, String?>>[',
    );
  for (final binding in inventory.mcpMethodBindings) {
    buffer
      ..writeln('  <String, String?>{')
      ..writeln("    'method': '${_escapeDartString(binding.method)}',")
      ..writeln("    'sender': '${binding.sender}',")
      ..writeln("    'role': '${binding.role}',")
      ..writeln("    'kind': '${binding.kind}',")
      ..writeln("    'definition': '${binding.definition}',")
      ..writeln(
        "    'result': ${_dartNullableString(binding.resultDefinition)},",
      )
      ..writeln('  },');
  }
  buffer
    ..writeln('];')
    ..writeln()
    ..writeln(
      'const mcpGeneratedDefinitionClassifications = <String, String>{',
    );
  final typedDefinitions = <String>{
    for (final binding in inventory.mcpMethodBindings) binding.definition,
    for (final binding in inventory.mcpMethodBindings)
      if (binding.resultDefinition != null) binding.resultDefinition!,
  };
  for (final definition in inventory.mcpDefinitionNames.toList()..sort()) {
    final classification =
        typedDefinitions.contains(definition) ? 'typed' : 'validated-extension';
    buffer.writeln(
      "  '${_escapeDartString(definition)}': '$classification',",
    );
  }
  buffer.writeln('};');
  return buffer.toString();
}

String _buildMcpSchema(String schemaText) => <String>[
      '// GENERATED CODE - DO NOT MODIFY BY HAND.',
      '// Source: MCP 2025-11-25, generator format 1.',
      '',
      "const mcpGeneratedSchemaJson = r'''$schemaText''';",
      '',
    ].join('\n');

String _buildMcpModels(Map<String, Object?> schema) {
  final definitions = (schema[r'$defs']! as Map<String, Object?>).keys.toList()
    ..sort();
  final buffer = StringBuffer(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// Source: MCP 2025-11-25, generator format 1.\n\n'
    "import 'package:pigcode_ai_protocol_utils/"
    "pigcode_ai_protocol_utils.dart';\n\n"
    "import '../models.dart';\n"
    "import '../schema.dart';\n\n",
  );
  for (final definition in definitions) {
    final className = 'Mcp$definition';
    buffer
      ..writeln('/// Validated MCP `$definition` value.')
      ..writeln('final class $className extends McpSchemaValue {')
      ..writeln('  factory $className.fromJson(')
      ..writeln('    JsonValue value,')
      ..writeln('  ) {')
      ..writeln('    return $className._(')
      ..writeln('      McpSchema.instance.validateDefinition(')
      ..writeln("        '$definition',")
      ..writeln('        value,')
      ..writeln('      ),')
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $className._(')
      ..writeln('    super.value,')
      ..writeln('  ) : super(')
      ..writeln("          definitionName: '$definition',")
      ..writeln('        );')
      ..writeln('}')
      ..writeln();
  }
  return '${buffer.toString().trimRight()}\n';
}

String _buildMcpGoldenFixtures(
  ProtocolInventory inventory,
  Map<String, Object?> schema,
) {
  final sampler = _AcpSchemaSampler(schema);
  var requestId = 1;
  var responseId = 1;
  final cases = <Map<String, Object?>>[];
  for (final binding in inventory.mcpMethodBindings) {
    final role = switch ((binding.sender, binding.kind)) {
      ('client', 'request') => 'clientRequest',
      ('server', 'request') => 'serverRequest',
      ('client', 'notification') => 'clientNotification',
      ('server', 'notification') => 'serverNotification',
      _ => throw StateError('Unsupported MCP golden binding.'),
    };
    final envelope = jsonDecode(
      jsonEncode(sampler.sampleDefinition(binding.definition)),
    );
    if (binding.kind == 'request') {
      (envelope! as Map<String, Object?>)['id'] = requestId++;
    }
    if (binding.method == 'initialize') {
      final request = envelope! as Map<String, Object?>;
      final params = request['params']! as Map<String, Object?>;
      params['protocolVersion'] = '2025-11-25';
    }
    cases.add(<String, Object?>{
      'id': '${binding.kind}:${binding.sender}:${binding.method}',
      'kind': binding.kind,
      'role': role,
      'sender': binding.sender,
      'method': binding.method,
      'definition': binding.definition,
      'envelope': envelope,
    });
    if (binding.kind == 'request') {
      cases.add(<String, Object?>{
        'id': 'response:${binding.sender}:${binding.method}',
        'kind': 'response',
        'role': binding.sender == 'client' ? 'serverResult' : 'clientResult',
        'sender': binding.sender == 'client' ? 'server' : 'client',
        'method': binding.method,
        'definition': binding.resultDefinition,
        'responseMethod': binding.method,
        'envelope': <String, Object?>{
          'jsonrpc': '2.0',
          'id': responseId++,
          'result': sampler.sampleDefinition(binding.resultDefinition!),
        },
      });
    }
  }
  final definitionSamples = <String, Object?>{};
  for (final definition in inventory.mcpDefinitionNames.toList()..sort()) {
    definitionSamples[definition] = sampler.sampleDefinition(definition);
  }
  return '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'formatVersion': 1,
        'source': <String, Object?>{
          'release': '2025-11-25',
          'sha256':
              '1ffe4c5577974012f5fa02af14ea88df4b7146679df1abaaad497c8d9230ca8a',
        },
        'cases': cases,
        'definitionSamples': definitionSamples,
      })}\n';
}

void _writeStrings(StringBuffer buffer, Iterable<String> values) {
  final sorted = values.toList()..sort();
  for (final value in sorted) {
    buffer.writeln("  '${_escapeDartString(value)}',");
  }
}

String _escapeDartString(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll(r'$', r'\$')
    .replaceAll("'", r"\'");

String _dartNullableString(String? value) =>
    value == null ? 'null' : "'${_escapeDartString(value)}'";
