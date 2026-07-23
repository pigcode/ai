import 'dart:io';
import 'dart:convert';

import '../src/protocol_inventory.dart';

void main() {
  final inventory = buildProtocolInventory(Directory.current);

  _expect(inventory.acpDefinitionCount == 142, 'ACP definition drift.');
  _expect(inventory.acpMethodCount == 23, 'ACP method drift.');
  _expect(
    _sameSet(
      inventory.acpMessageRoots,
      const <String>{'Agent', 'Client', 'ProtocolLevel'},
    ),
    'ACP message-root drift: ${inventory.acpMessageRoots}',
  );
  _expect(inventory.mcpDefinitionCount == 145, 'MCP definition drift.');
  _expect(
    _sameSet(
      inventory.mcpRoleDefinitions,
      const <String>{
        'ClientRequest',
        'ServerRequest',
        'ClientNotification',
        'ServerNotification',
        'ClientResult',
        'ServerResult',
      },
    ),
    'MCP role-definition drift: ${inventory.mcpRoleDefinitions}',
  );
  _expect(
    inventory.mcpClientConformanceScenarios.length == 18,
    'MCP client conformance inventory drift.',
  );
  _expect(
    _sameSet(
      inventory.mcpClientConformanceScenarios.toSet(),
      _expectedClientScenarios,
    ),
    'MCP client conformance scenario names drifted.',
  );
  _expect(
    inventory.mcpServerConformanceScenarios.length == 32,
    'MCP server conformance inventory drift.',
  );
  _expect(
    _sameSet(
      inventory.mcpServerConformanceScenarios.toSet(),
      _expectedServerScenarios,
    ),
    'MCP server conformance scenario names drifted.',
  );
  _testMcpEntryRoots();
  _expect(
    !inventory
        .toJson()
        .toString()
        .contains(RegExp('draft|unstable|2026-07-28')),
    'Stable inventory contains draft, unstable, or RC material.',
  );

  stdout.writeln('Protocol inventory validation passed.');
}

void _testMcpEntryRoots() {
  final schema = jsonDecode(
    File(
      'tool/upstream/protocols/mcp/2025-11-25/schema.json',
    ).readAsStringSync(),
  ) as Map<String, Object?>;

  for (final ref in <String>[
    r'#/$defs/JSONRPCMessage',
    r'#/$defs/ClientRequest',
    r'#/$defs/InitializeRequest',
  ]) {
    validateMcpEntryRefs(schema, <String>[ref]);
  }

  for (final invalidRefs in <List<String>>[
    const <String>[],
    const <String>['#'],
    const <String>[r'#/$defs/DoesNotExist'],
  ]) {
    try {
      validateMcpEntryRefs(schema, invalidRefs);
    } on FormatException {
      continue;
    }
    throw StateError('Expected MCP entry references to fail: $invalidRefs');
  }
}

bool _sameSet(Set<String> actual, Set<String> expected) =>
    actual.length == expected.length &&
    actual.containsAll(expected) &&
    expected.containsAll(actual);

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

const _expectedClientScenarios = <String>{
  'initialize',
  'tools_call',
  'elicitation-sep1034-client-defaults',
  'sse-retry',
  'auth/metadata-default',
  'auth/metadata-var1',
  'auth/metadata-var2',
  'auth/metadata-var3',
  'auth/basic-cimd',
  'auth/scope-from-www-authenticate',
  'auth/scope-from-scopes-supported',
  'auth/scope-omitted-when-undefined',
  'auth/scope-step-up',
  'auth/scope-retry-limit',
  'auth/token-endpoint-auth-basic',
  'auth/token-endpoint-auth-post',
  'auth/token-endpoint-auth-none',
  'auth/pre-registration',
};

const _expectedServerScenarios = <String>{
  'server-initialize',
  'logging-set-level',
  'ping',
  'completion-complete',
  'tools-list',
  'tools-call-simple-text',
  'tools-call-image',
  'tools-call-audio',
  'tools-call-embedded-resource',
  'tools-call-mixed-content',
  'tools-call-with-logging',
  'tools-call-error',
  'tools-call-with-progress',
  'tools-call-sampling',
  'tools-call-elicitation',
  'json-schema-2020-12',
  'elicitation-sep1034-defaults',
  'server-sse-polling',
  'server-sse-multiple-streams',
  'elicitation-sep1330-enums',
  'resources-list',
  'resources-read-text',
  'resources-read-binary',
  'resources-templates-read',
  'resources-subscribe',
  'resources-unsubscribe',
  'prompts-list',
  'prompts-get-simple',
  'prompts-get-with-args',
  'prompts-get-embedded-resource',
  'prompts-get-with-image',
  'dns-rebinding-protection',
};
