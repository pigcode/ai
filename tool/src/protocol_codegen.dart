import 'dart:convert';
import 'dart:io';

import 'analysis_server_codegen.dart';
import 'dtd_codegen.dart';
import 'protocol_inventory.dart';
import 'protocol_sources.dart';
import 'vm_service_codegen.dart';

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
  final toolingInventory = buildPhase2bToolingInventory(root);
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
  final lspMetaModelText = File.fromUri(
    root.absolute.uri.resolve(
      'tool/upstream/protocols/lsp/3.18-b7f5132/metaModel.json',
    ),
  ).readAsStringSync();
  final lspMetaModel = jsonDecode(lspMetaModelText) as Map<String, Object?>;
  final dapSchemaText = File.fromUri(
    root.absolute.uri.resolve(
      'tool/upstream/protocols/dap/v1.71.0/debugAdapterProtocol.json',
    ),
  ).readAsStringSync();
  final dapSchema = jsonDecode(dapSchemaText) as Map<String, Object?>;
  final analysisServer = buildAnalysisServerGeneratedArtifacts(root);
  final dtd = buildDtdGeneratedArtifacts(root);
  final vmService = buildVmServiceGeneratedArtifacts(root);
  return <String, String>{
    'compatibility/upstream/phase-2a-protocol-inventory.json':
        '${const JsonEncoder.withIndent('  ').convert(inventory.toJson())}\n',
    'compatibility/upstream/phase-2b-tooling-inventory.json':
        '${const JsonEncoder.withIndent('  ').convert(toolingInventory)}\n',
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
    'packages/lsp/lib/src/generated/lsp_inventory.g.dart': _formatGeneratedDart(
      root,
      _buildLspGeneratedInventory(lspMetaModelText, lspMetaModel),
    ),
    'packages/lsp/lib/src/generated/lsp_stable_models.g.dart':
        _formatGeneratedDart(
      root,
      _buildLspModels(lspMetaModel, proposed: false),
    ),
    'packages/lsp/lib/src/generated/lsp_proposed_models.g.dart':
        _formatGeneratedDart(
      root,
      _buildLspModels(lspMetaModel, proposed: true),
    ),
    'packages/lsp/test/fixtures/golden/stable_messages.json':
        _buildLspGoldenFixtures(lspMetaModel),
    'packages/dap/lib/src/generated/dap_inventory.g.dart': _formatGeneratedDart(
      root,
      _buildDapGeneratedInventory(dapSchemaText, dapSchema),
      package: 'dap',
    ),
    'packages/dap/lib/src/generated/dap_models.g.dart': _formatGeneratedDart(
      root,
      _buildDapModels(dapSchema),
      package: 'dap',
    ),
    'packages/dap/test/fixtures/golden/messages.json':
        _buildDapGoldenFixtures(dapSchema),
    'packages/dart/lib/src/analysis_server/generated/inventory.g.dart':
        _formatGeneratedDart(
      root,
      analysisServer.inventoryDart,
      package: 'dart',
    ),
    'packages/dart/lib/src/analysis_server/generated/models.g.dart':
        _formatGeneratedDart(
      root,
      analysisServer.modelsDart,
      package: 'dart',
    ),
    'packages/dart/lib/src/dtd/generated/inventory.g.dart':
        _formatGeneratedDart(
      root,
      dtd.inventoryDart,
      package: 'dart',
    ),
    'packages/dart/lib/src/vm_service/generated/inventory.g.dart':
        _formatGeneratedDart(
      root,
      vmService.inventoryDart,
      package: 'dart',
    ),
    'packages/dart/lib/src/vm_service/generated/models.g.dart':
        _formatGeneratedDart(
      root,
      vmService.modelsDart,
      package: 'dart',
    ),
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

String _formatGeneratedDart(
  Directory root,
  String source, {
  String package = 'lsp',
}) {
  final generatedDirectory = Directory.fromUri(
    root.absolute.uri.resolve('packages/$package/lib/src/generated/'),
  )..createSync(recursive: true);
  final temporary = generatedDirectory.createTempSync(
    '.pigcode_protocol_codegen_format_',
  );
  try {
    final file = File.fromUri(temporary.uri.resolve('generated.dart'))
      ..writeAsStringSync(source);
    final result = Process.runSync(
      Platform.resolvedExecutable,
      <String>['format', file.path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'dart format failed for generated protocol source: ${result.stderr}',
      );
    }
    return file.readAsStringSync();
  } finally {
    temporary.deleteSync(recursive: true);
  }
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
      : definitions =
            (root[r'$defs'] ?? root['definitions'])! as Map<String, Object?>,
        referencePrefix =
            root.containsKey(r'$defs') ? r'#/$defs/' : '#/definitions/';

  final Map<String, Object?> definitions;
  final String referencePrefix;
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
      if (!reference.startsWith(referencePrefix)) {
        throw StateError('Unsupported ACP schema reference: $reference');
      }
      result = sampleDefinition(reference.substring(referencePrefix.length));
    } else if (schema.containsKey('const')) {
      result = schema['const'];
    } else if (schema.containsKey('default')) {
      result = schema['default'];
    } else if (schema['enum'] case final List<Object?> values
        when values.isNotEmpty) {
      result = values.first;
    } else if (schema['_enum'] case final List<Object?> values
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

String _buildLspGeneratedInventory(
  String metaModelText,
  Map<String, Object?> metaModel,
) {
  final buffer = StringBuffer(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// Source: LSP 3.18 audit snapshot b7f5132, generator format 1.\n\n',
  )
    ..writeln("const lspGeneratedSpecificationVersion = '3.18.0';")
    ..writeln("const lspGeneratedSourceRelease = '3.18-audit-snapshot';")
    ..writeln(
      "const lspGeneratedSourceRevision = "
      "'b7f5132c95261c0898ae5124e7a91707abc48fcd';",
    )
    ..writeln(
      "const lspGeneratedMetaModelSha256 = "
      "'caae8df639a4248520a3f589fd72945365e9d8ebca5baf564161a515430d9d41';",
    )
    ..writeln(
      "const lspGeneratedSchemaDialect = "
      "'http://json-schema.org/draft-07/schema#';",
    )
    ..writeln()
    ..writeln("const lspGeneratedMetaModelJson = r'''$metaModelText''';")
    ..writeln()
    ..writeln(
      'const lspGeneratedMethodMetadata = <Map<String, String?>>[',
    );
  final methods = <Map<String, Object?>>[
    for (final request in (metaModel['requests']! as List<Object?>)
        .cast<Map<String, Object?>>())
      <String, Object?>{...request, '_kind': 'request'},
    for (final notification in (metaModel['notifications']! as List<Object?>)
        .cast<Map<String, Object?>>())
      <String, Object?>{...notification, '_kind': 'notification'},
  ]..sort(
      (left, right) =>
          (left['method']! as String).compareTo(right['method']! as String),
    );
  for (final method in methods) {
    buffer
      ..writeln('  <String, String?>{')
      ..writeln(
        "    'method': '${_escapeDartString(method['method']! as String)}',",
      )
      ..writeln("    'kind': '${method['_kind']}',")
      ..writeln("    'direction': '${method['messageDirection']}',")
      ..writeln(
        "    'serverCapability': "
        "${_dartNullableString(method['serverCapability'] as String?)},",
      )
      ..writeln(
        "    'params': ${_dartNullableString(_encodedLspType(method['params']))},",
      )
      ..writeln(
        "    'result': ${_dartNullableString(_encodedLspType(method['result']))},",
      )
      ..writeln('  },');
  }
  buffer
    ..writeln('];')
    ..writeln()
    ..writeln(
      'const lspGeneratedDefinitionClassifications = <String, String>{',
    );
  final definitions = _lspDefinitions(metaModel);
  for (final definition in definitions) {
    buffer.writeln(
      "  '${_escapeDartString(definition['name']! as String)}': "
      "'${definition['proposed'] == true ? 'proposed' : 'stable'}',",
    );
  }
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('const lspGeneratedProposedDefinitionNames = <String>{');
  _writeStrings(
    buffer,
    definitions
        .where((definition) => definition['proposed'] == true)
        .map((definition) => definition['name']! as String),
  );
  buffer.writeln('};');
  return buffer.toString();
}

String? _encodedLspType(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! Map<String, Object?>) {
    throw StateError('LSP type descriptor must be an object.');
  }
  return jsonEncode(value);
}

List<Map<String, Object?>> _lspDefinitions(
  Map<String, Object?> metaModel,
) {
  final definitions = <Map<String, Object?>>[
    ...(metaModel['structures']! as List<Object?>).cast<Map<String, Object?>>(),
    ...(metaModel['enumerations']! as List<Object?>)
        .cast<Map<String, Object?>>(),
    ...(metaModel['typeAliases']! as List<Object?>)
        .cast<Map<String, Object?>>(),
  ]..sort(
      (left, right) =>
          (left['name']! as String).compareTo(right['name']! as String),
    );
  return definitions;
}

String _buildLspModels(
  Map<String, Object?> metaModel, {
  required bool proposed,
}) {
  final definitions = _lspDefinitions(metaModel)
      .where((definition) => (definition['proposed'] == true) == proposed)
      .toList();
  final buffer = StringBuffer(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// Source: LSP 3.18 audit snapshot b7f5132, generator format 1.\n',
  );
  if (definitions.isEmpty) {
    return '${buffer.toString()}\n'
        '// The pinned snapshot contains no proposed named definitions.\n';
  }
  buffer.write(
    '\n// ignore_for_file: camel_case_types\n\n'
    "import 'package:pigcode_ai_protocol_utils/"
    "pigcode_ai_protocol_utils.dart';\n\n"
    "import '../models.dart';\n\n",
  );
  for (final definition in definitions) {
    final name = definition['name']! as String;
    final className = 'Lsp$name';
    buffer
      ..writeln('/// Validated LSP `$name` value.')
      ..writeln('final class $className extends LspSchemaValue {')
      ..writeln('  factory $className.fromJson(JsonValue value) {')
      ..writeln('    return $className._(')
      ..writeln(
        "      LspModelRegistry.instance.validateNamed('$name', value),",
      )
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $className._(super.value)')
      ..writeln("      : super(definitionName: '$name');")
      ..writeln('}')
      ..writeln();
  }
  return '${buffer.toString().trimRight()}\n';
}

String _buildLspGoldenFixtures(Map<String, Object?> metaModel) {
  final sampler = _LspMetaModelSampler(metaModel);
  final cases = <Map<String, Object?>>[];
  var requestId = 1;
  final requests = (metaModel['requests']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .toList()
    ..sort(
      (left, right) =>
          (left['method']! as String).compareTo(right['method']! as String),
    );
  for (final request in requests) {
    final method = request['method']! as String;
    final requestSender = _lspGoldenRequestSender(
      request['messageDirection']! as String,
    );
    final requestEnvelope = <String, Object?>{
      'jsonrpc': '2.0',
      'id': requestId++,
      'method': method,
      if (request['params'] case final Map<String, Object?> params)
        'params': _lspGoldenParams(sampler, params),
    };
    cases.add(<String, Object?>{
      'id': 'request:$method',
      'kind': 'request',
      'sender': requestSender,
      'method': method,
      'envelope': requestEnvelope,
    });
    cases.add(<String, Object?>{
      'id': 'response:$method',
      'kind': 'response',
      'sender': requestSender == 'client' ? 'server' : 'client',
      'method': method,
      'responseMethod': method,
      'envelope': <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestId++,
        'result': sampler.sampleType(
          request['result']! as Map<String, Object?>,
        ),
      },
    });
  }
  final notifications = (metaModel['notifications']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .toList()
    ..sort(
      (left, right) =>
          (left['method']! as String).compareTo(right['method']! as String),
    );
  for (final notification in notifications) {
    final method = notification['method']! as String;
    cases.add(<String, Object?>{
      'id': 'notification:$method',
      'kind': 'notification',
      'sender': _lspGoldenRequestSender(
        notification['messageDirection']! as String,
      ),
      'method': method,
      'envelope': <String, Object?>{
        'jsonrpc': '2.0',
        'method': method,
        if (notification['params'] case final Map<String, Object?> params)
          'params': _lspGoldenParams(sampler, params),
      },
    });
  }
  final definitionSamples = <String, Object?>{};
  for (final definition in _lspDefinitions(metaModel)) {
    final name = definition['name']! as String;
    definitionSamples[name] = sampler.sampleDefinition(name);
  }
  return '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'formatVersion': 1,
        'source': <String, Object?>{
          'release': '3.18-audit-snapshot',
          'revision': 'b7f5132c95261c0898ae5124e7a91707abc48fcd',
          'sha256':
              'caae8df639a4248520a3f589fd72945365e9d8ebca5baf564161a515430d9d41',
        },
        'cases': cases,
        'definitionSamples': definitionSamples,
      })}\n';
}

String _lspGoldenRequestSender(String direction) => switch (direction) {
      'clientToServer' || 'both' => 'client',
      'serverToClient' => 'server',
      _ => throw StateError('Unknown LSP message direction: $direction.'),
    };

Object _lspGoldenParams(
  _LspMetaModelSampler sampler,
  Map<String, Object?> type,
) {
  final sample = sampler.sampleType(type);
  return sample is Map<String, Object?> || sample is List<Object?>
      ? sample!
      : <String, Object?>{};
}

final class _LspMetaModelSampler {
  _LspMetaModelSampler(Map<String, Object?> metaModel) {
    for (final definition in _lspDefinitions(metaModel)) {
      _definitions[definition['name']! as String] = definition;
    }
    for (final structure in (metaModel['structures']! as List<Object?>)
        .cast<Map<String, Object?>>()) {
      _structureNames.add(structure['name']! as String);
    }
    for (final enumeration in (metaModel['enumerations']! as List<Object?>)
        .cast<Map<String, Object?>>()) {
      _enumerationNames.add(enumeration['name']! as String);
    }
  }

  final Map<String, Map<String, Object?>> _definitions =
      <String, Map<String, Object?>>{};
  final Set<String> _structureNames = <String>{};
  final Set<String> _enumerationNames = <String>{};
  final Map<String, Object?> _cache = <String, Object?>{};
  final Set<String> _active = <String>{};

  Object? sampleDefinition(String name) {
    if (_cache.containsKey(name)) {
      return _cache[name];
    }
    if (!_active.add(name)) {
      return <String, Object?>{};
    }
    final definition = _definitions[name];
    if (definition == null) {
      throw StateError('Unknown LSP definition: $name.');
    }
    try {
      late final Object? sample;
      if (_structureNames.contains(name)) {
        sample = _sampleStructure(definition);
      } else if (_enumerationNames.contains(name)) {
        sample = ((definition['values']! as List<Object?>).first
            as Map<String, Object?>)['value'];
      } else {
        sample = sampleType(definition['type']! as Map<String, Object?>);
      }
      _cache[name] = sample;
      return sample;
    } finally {
      _active.remove(name);
    }
  }

  Object? sampleType(Map<String, Object?> type) {
    return switch (type['kind']) {
      'base' => _sampleBase(type['name']! as String),
      'reference' => sampleDefinition(type['name']! as String),
      'array' => <Object?>[],
      'map' => <String, Object?>{},
      'or' => _sampleUnion(type['items']! as List<Object?>),
      'tuple' => <Object?>[
          for (final item
              in (type['items']! as List<Object?>).cast<Map<String, Object?>>())
            sampleType(item),
        ],
      'literal' => _sampleProperties(
          ((type['value']! as Map<String, Object?>)['properties']!
                  as List<Object?>)
              .cast<Map<String, Object?>>(),
        ),
      'stringLiteral' => type['value'],
      _ => throw StateError('Unknown LSP type kind: ${type['kind']}.'),
    };
  }

  Object? _sampleUnion(List<Object?> values) {
    final types = values.cast<Map<String, Object?>>();
    final nullType = types.where(
      (type) => type['kind'] == 'base' && type['name'] == 'null',
    );
    if (nullType.isNotEmpty) {
      return null;
    }
    return sampleType(types.first);
  }

  Object? _sampleStructure(Map<String, Object?> structure) {
    final sample = <String, Object?>{};
    for (final relationName in const <String>['extends', 'mixins']) {
      final relations = structure[relationName];
      if (relations is List<Object?>) {
        for (final relation in relations.cast<Map<String, Object?>>()) {
          final parent = sampleType(relation);
          if (parent is Map<String, Object?>) {
            sample.addAll(parent);
          }
        }
      }
    }
    final properties = structure['properties'];
    if (properties is List<Object?>) {
      sample.addAll(
        _sampleProperties(properties.cast<Map<String, Object?>>()),
      );
    }
    return sample;
  }

  Map<String, Object?> _sampleProperties(
    List<Map<String, Object?>> properties,
  ) {
    return <String, Object?>{
      for (final property in properties)
        if (property['optional'] != true)
          property['name']! as String:
              sampleType(property['type']! as Map<String, Object?>),
    };
  }

  Object? _sampleBase(String name) => switch (name) {
        'URI' || 'DocumentUri' => 'file:///sample.dart',
        'string' => '',
        'integer' || 'uinteger' => 0,
        'decimal' => 0.0,
        'boolean' => false,
        'null' => null,
        _ => throw StateError('Unknown LSP base type: $name.'),
      };
}

String _buildDapGeneratedInventory(
  String schemaText,
  Map<String, Object?> schema,
) {
  final definitions = _dapDefinitions(schema);
  final requests = _dapRequestDefinitions(schema);
  final events = _dapEventDefinitions(schema);
  final enumCounts = _dapEnumCounts(definitions);
  final buffer = StringBuffer(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// Source: DAP v1.71.0, generator format 1.\n\n',
  )
    ..writeln("const dapGeneratedSpecificationVersion = '1.71.0';")
    ..writeln("const dapGeneratedSourceRelease = 'v1.71.0';")
    ..writeln(
      "const dapGeneratedSourceRevision = "
      "'51d95ea4e692b34c5d06601bbd1bebc1ff3fbdd4';",
    )
    ..writeln(
      "const dapGeneratedSchemaSha256 = "
      "'ff8ae4c6cfd588a050e9346c35fd104748a27ef4518d1c3268529ca6f8ff5818';",
    )
    ..writeln(
      "const dapGeneratedSchemaDialect = "
      "'http://json-schema.org/draft-04/schema#';",
    )
    ..writeln('const dapGeneratedClosedEnumCount = ${enumCounts.$1};')
    ..writeln('const dapGeneratedOpenEnumCount = ${enumCounts.$2};')
    ..writeln()
    ..writeln("const dapGeneratedSchemaJson = r'''$schemaText''';")
    ..writeln()
    ..writeln(
      'const dapGeneratedDefinitionClassifications = <String, String>{',
    );
  for (final name in definitions.keys.toList()..sort()) {
    buffer.writeln(
      "  '${_escapeDartString(name)}': "
      "'${_dapClassification(name, requests, events)}',",
    );
  }
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln(
      'const dapGeneratedRequestMetadata = <Map<String, String?>>[',
    );
  for (final entry in requests.entries) {
    final command = _dapLiteralProperty(entry.value, 'command');
    final responseDefinition =
        entry.key.replaceFirst(RegExp(r'Request$'), 'Response');
    if (!definitions.containsKey(responseDefinition)) {
      throw StateError('DAP response is missing for ${entry.key}.');
    }
    buffer
      ..writeln('  <String, String?>{')
      ..writeln("    'command': '${_escapeDartString(command)}',")
      ..writeln("    'request': '${_escapeDartString(entry.key)}',")
      ..writeln(
        "    'response': '${_escapeDartString(responseDefinition)}',",
      )
      ..writeln(
        "    'arguments': "
        "${_dartNullableString(_dapArgumentsDefinition(entry.value))},",
      )
      ..writeln('  },');
  }
  buffer
    ..writeln('];')
    ..writeln()
    ..writeln(
      'const dapGeneratedEventMetadata = <Map<String, String>>[',
    );
  for (final entry in events.entries) {
    buffer
      ..writeln('  <String, String>{')
      ..writeln(
        "    'event': "
        "'${_escapeDartString(_dapLiteralProperty(entry.value, 'event'))}',",
      )
      ..writeln("    'definition': '${_escapeDartString(entry.key)}',")
      ..writeln('  },');
  }
  buffer.writeln('];');
  return buffer.toString();
}

Map<String, Map<String, Object?>> _dapDefinitions(
  Map<String, Object?> schema,
) =>
    (schema['definitions']! as Map<String, Object?>).map(
      (name, definition) => MapEntry(
        name,
        definition! as Map<String, Object?>,
      ),
    );

Map<String, Map<String, Object?>> _dapRequestDefinitions(
  Map<String, Object?> schema,
) =>
    <String, Map<String, Object?>>{
      for (final entry in _dapDefinitions(schema).entries)
        if (entry.key != 'Request' && entry.key.endsWith('Request'))
          entry.key: entry.value,
    }..sortByKey();

Map<String, Map<String, Object?>> _dapEventDefinitions(
  Map<String, Object?> schema,
) =>
    <String, Map<String, Object?>>{
      for (final entry in _dapDefinitions(schema).entries)
        if (entry.key != 'Event' && entry.key.endsWith('Event'))
          entry.key: entry.value,
    }..sortByKey();

extension<K extends Comparable<K>, V> on Map<K, V> {
  Map<K, V> sortByKey() => Map<K, V>.fromEntries(
        entries.toList()
          ..sort(
            (left, right) => left.key.compareTo(right.key),
          ),
      );
}

String _dapLiteralProperty(
  Map<String, Object?> definition,
  String property,
) {
  final allOf = definition['allOf']! as List<Object?>;
  for (final component in allOf.cast<Map<String, Object?>>()) {
    final properties = component['properties'];
    if (properties is Map<String, Object?>) {
      final propertySchema = properties[property];
      if (propertySchema is Map<String, Object?>) {
        final values = propertySchema['enum'];
        if (values is List<Object?> &&
            values.length == 1 &&
            values.single is String) {
          return values.single! as String;
        }
      }
    }
  }
  throw StateError('DAP definition has no fixed $property property.');
}

String? _dapArgumentsDefinition(Map<String, Object?> definition) {
  final allOf = definition['allOf']! as List<Object?>;
  for (final component in allOf.cast<Map<String, Object?>>()) {
    final properties = component['properties'];
    if (properties is! Map<String, Object?>) {
      continue;
    }
    final arguments = properties['arguments'];
    if (arguments is! Map<String, Object?>) {
      continue;
    }
    final reference = arguments[r'$ref'];
    if (reference is String && reference.startsWith('#/definitions/')) {
      return reference.substring('#/definitions/'.length);
    }
  }
  return null;
}

String _dapClassification(
  String name,
  Map<String, Map<String, Object?>> requests,
  Map<String, Map<String, Object?>> events,
) {
  if (const <String>{
    'ProtocolMessage',
    'Request',
    'Response',
    'Event',
  }.contains(name)) {
    return 'envelope';
  }
  if (requests.containsKey(name)) {
    return 'request';
  }
  if (events.containsKey(name)) {
    return 'event';
  }
  if (name.endsWith('Response')) {
    return 'response';
  }
  if (name.endsWith('Arguments')) {
    return 'arguments';
  }
  return 'type';
}

(int, int) _dapEnumCounts(
  Map<String, Map<String, Object?>> definitions,
) {
  var closed = 0;
  var open = 0;
  void visit(Object? value) {
    switch (value) {
      case final Map<String, Object?> object:
        if (object.containsKey('enum')) {
          closed += 1;
        }
        if (object.containsKey('_enum')) {
          open += 1;
        }
        for (final child in object.values) {
          visit(child);
        }
      case final List<Object?> list:
        for (final child in list) {
          visit(child);
        }
    }
  }

  visit(definitions);
  return (closed, open);
}

String _buildDapModels(Map<String, Object?> schema) {
  final names = _dapDefinitions(schema).keys.toList()..sort();
  final buffer = StringBuffer(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// Source: DAP v1.71.0, generator format 1.\n\n'
    "import 'package:pigcode_ai_protocol_utils/"
    "pigcode_ai_protocol_utils.dart';\n\n"
    "import '../models.dart';\n\n",
  );
  for (final name in names) {
    final className = 'Dap$name';
    buffer
      ..writeln('/// Validated DAP `$name` value.')
      ..writeln('final class $className extends DapSchemaValue {')
      ..writeln('  factory $className.fromJson(JsonValue value) {')
      ..writeln('    return $className._(')
      ..writeln(
        "      DapModelRegistry.instance.validateNamed('$name', value),",
      )
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  $className._(super.value)')
      ..writeln("      : super(definitionName: '$name');")
      ..writeln('}')
      ..writeln();
  }
  return '${buffer.toString().trimRight()}\n';
}

String _buildDapGoldenFixtures(Map<String, Object?> schema) {
  final sampler = _AcpSchemaSampler(schema);
  final requests = _dapRequestDefinitions(schema);
  final events = _dapEventDefinitions(schema);
  var sequence = 1;
  var requestSequence = 1;
  final cases = <Map<String, Object?>>[];
  for (final entry in requests.entries) {
    final command = _dapLiteralProperty(entry.value, 'command');
    final request = _jsonObjectCopy(sampler.sampleDefinition(entry.key))
      ..['seq'] = sequence++
      ..['type'] = 'request'
      ..['command'] = command;
    cases.add(<String, Object?>{
      'id': 'request:$command',
      'kind': 'request',
      'name': command,
      'definition': entry.key,
      'envelope': request,
    });
    final responseDefinition =
        entry.key.replaceFirst(RegExp(r'Request$'), 'Response');
    final response =
        _jsonObjectCopy(sampler.sampleDefinition(responseDefinition))
          ..['seq'] = sequence++
          ..['type'] = 'response'
          ..['request_seq'] = requestSequence++
          ..['success'] = true
          ..['command'] = command;
    cases.add(<String, Object?>{
      'id': 'response:$command',
      'kind': 'response',
      'name': command,
      'definition': responseDefinition,
      'requestCommand': command,
      'envelope': response,
    });
  }
  for (final entry in events.entries) {
    final eventName = _dapLiteralProperty(entry.value, 'event');
    final event = _jsonObjectCopy(sampler.sampleDefinition(entry.key))
      ..['seq'] = sequence++
      ..['type'] = 'event'
      ..['event'] = eventName;
    cases.add(<String, Object?>{
      'id': 'event:$eventName',
      'kind': 'event',
      'name': eventName,
      'definition': entry.key,
      'envelope': event,
    });
  }
  final definitionSamples = <String, Object?>{};
  for (final name in _dapDefinitions(schema).keys.toList()..sort()) {
    definitionSamples[name] = sampler.sampleDefinition(name);
  }
  return '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'formatVersion': 1,
        'source': <String, Object?>{
          'release': 'v1.71.0',
          'revision': '51d95ea4e692b34c5d06601bbd1bebc1ff3fbdd4',
          'sha256':
              'ff8ae4c6cfd588a050e9346c35fd104748a27ef4518d1c3268529ca6f8ff5818',
        },
        'cases': cases,
        'definitionSamples': definitionSamples,
      })}\n';
}

Map<String, Object?> _jsonObjectCopy(Object? value) {
  if (value is! Map<String, Object?>) {
    throw StateError('Expected generated DAP sample to be an object.');
  }
  return Map<String, Object?>.from(value);
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
