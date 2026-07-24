import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';

const _draft202012 = 'https://json-schema.org/draft/2020-12/schema';
const _eventSchemaPath = 'tool/schema/agent_kernel/agent-event-v1.schema.json';
const _manifestSchemaPath =
    'tool/schema/agent_kernel/store-manifest-v1.schema.json';
const _inventoryPath = 'tool/schema/agent_kernel/event-inventory-v1.json';
const _rootManifestFixturePath =
    'tool/fixtures/agent_kernel/schema/valid-root-manifest.json';
const _sessionManifestFixturePath =
    'tool/fixtures/agent_kernel/schema/valid-session-manifest.json';

const agentKernelSchemaAssetPaths = <String>[
  _eventSchemaPath,
  'tool/schema/agent_kernel/store-transaction-v1.schema.json',
  'tool/schema/agent_kernel/snapshot-v1.schema.json',
  _manifestSchemaPath,
  _inventoryPath,
  'tool/fixtures/agent_kernel/schema/valid-event.json',
  'tool/fixtures/agent_kernel/schema/invalid-event-missing-id.json',
  'tool/fixtures/agent_kernel/schema/invalid-event-version.json',
  _rootManifestFixturePath,
  _sessionManifestFixturePath,
];

const _schemaPaths = <String>[
  _eventSchemaPath,
  'tool/schema/agent_kernel/store-transaction-v1.schema.json',
  'tool/schema/agent_kernel/snapshot-v1.schema.json',
  _manifestSchemaPath,
];

const _fixtureExpectations = <String, bool>{
  'tool/fixtures/agent_kernel/schema/valid-event.json': true,
  'tool/fixtures/agent_kernel/schema/invalid-event-missing-id.json': false,
  'tool/fixtures/agent_kernel/schema/invalid-event-version.json': false,
};

const _expectedEventsByFamily = <String, Set<String>>{
  'session': <String>{
    'session.created',
    'session.capabilitiesPinned',
    'session.attachmentChanged',
    'session.runtimeLivenessChanged',
    'session.resumeStateStored',
    'session.tombstoned',
  },
  'run': <String>{
    'run.created',
    'run.inputRecorded',
    'run.attemptStarted',
    'run.started',
    'run.cancelRequested',
    'run.suspendRequested',
    'run.suspended',
    'run.resumeRequested',
    'run.reconciling',
  },
  'runTerminal': <String>{
    'run.completed',
    'run.failed',
    'run.cancelled',
    'run.interrupted',
  },
  'work': <String>{
    'work.proposed',
    'work.policyEvaluated',
    'work.approvalRequested',
    'work.approvalResolved',
    'work.executionStarted',
    'work.cancellationRequested',
    'work.succeeded',
    'work.failed',
    'work.cancelled',
    'work.outcomeUnknown',
  },
  'deferred': <String>{
    'deferred.created',
    'deferred.ownershipTransferred',
    'deferred.completed',
    'deferred.failed',
    'deferred.cancelled',
    'deferred.outcomeUnknown',
  },
  'resource': <String>{
    'resource.registered',
    'resource.ownershipTransferred',
    'resource.updated',
    'resource.released',
    'resource.outcomeUnknown',
  },
  'driverAudit': <String>{
    'driver.proposalRejected',
    'driver.sourceDrained',
    'effect.observed',
    'history.imported',
  },
};

const _inventoryEntryKeys = <String>{
  'type',
  'family',
  'requiredContextIds',
  'payloadSchemaRef',
  'introducedIdPaths',
  'terminal',
  'runBusinessEvent',
  'allowedAfterRunTerminal',
};

const _contextIdPaths = <String>{
  'sessionId',
  'runId',
  'attemptId',
  'workItemId',
  'payload.approvalId',
  'payload.deferredOperationId',
  'payload.runtimeResourceId',
};

const _introducedIdPaths = <String>{
  'sessionId',
  'runId',
  'attemptId',
  'workItemId',
  'payload.approvalId',
  'payload.deferredOperationId',
  'payload.runtimeResourceId',
};

final class AgentKernelSchemaViolation {
  const AgentKernelSchemaViolation(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

List<AgentKernelSchemaViolation> validateAgentKernelSchemaAssets(
  Directory root,
) {
  final violations = <AgentKernelSchemaViolation>[];
  final documents = <String, Map<String, Object?>>{};

  for (final path in agentKernelSchemaAssetPaths) {
    final file = File.fromUri(root.uri.resolve(path));
    if (!file.existsSync()) {
      violations.add(
        AgentKernelSchemaViolation(
          'missing_schema_asset',
          'Required Agent Kernel schema asset is missing: $path',
        ),
      );
      continue;
    }
    final document = _readObject(file, path, violations);
    if (document != null) {
      documents[path] = document;
    }
  }
  if (violations.isNotEmpty) {
    return violations;
  }

  final validators = <String, JsonSchema>{};
  for (final path in _schemaPaths) {
    final document = documents[path]!;
    if (document[r'$schema'] != _draft202012) {
      violations.add(
        AgentKernelSchemaViolation(
          'wrong_schema_draft',
          '$path must declare JSON Schema Draft 2020-12.',
        ),
      );
      continue;
    }
    try {
      validators[path] = JsonSchema.create(
        document,
        schemaVersion: SchemaVersion.draft2020_12,
      );
    } on Object catch (error) {
      violations.add(
        AgentKernelSchemaViolation(
          'invalid_json_schema',
          '$path could not be compiled as Draft 2020-12: $error',
        ),
      );
    }
  }

  final eventSchema = documents[_eventSchemaPath]!;
  final inventory = documents[_inventoryPath]!;
  _validateInventory(eventSchema, inventory, violations);

  final eventValidator = validators[_eventSchemaPath];
  if (eventValidator != null) {
    for (final expectation in _fixtureExpectations.entries) {
      final fixture = documents[expectation.key]!;
      final actual = eventValidator.validate(fixture).isValid;
      if (actual != expectation.value) {
        violations.add(
          AgentKernelSchemaViolation(
            'fixture_classification_mismatch',
            '${expectation.key} expected valid=${expectation.value}, '
                'found valid=$actual.',
          ),
        );
      }
    }

    final validFixture = documents[_fixtureExpectations.keys.first]!;
    final futureVersion = _copyObject(validFixture)..['schemaVersion'] = 2;
    if (eventValidator.validate(futureVersion).isValid) {
      violations.add(
        const AgentKernelSchemaViolation(
          'future_version_accepted',
          'AgentEvent v1 schema accepted schemaVersion 2.',
        ),
      );
    }
    final unknownType = _copyObject(validFixture)..['type'] = 'run.futureState';
    if (eventValidator.validate(unknownType).isValid) {
      violations.add(
        const AgentKernelSchemaViolation(
          'unknown_event_type_accepted',
          'AgentEvent v1 schema accepted an unknown event type.',
        ),
      );
    }
  }

  final manifestValidator = validators[_manifestSchemaPath];
  if (manifestValidator != null) {
    for (final path in <String>[
      _rootManifestFixturePath,
      _sessionManifestFixturePath,
    ]) {
      if (!manifestValidator.validate(documents[path]).isValid) {
        violations.add(
          AgentKernelSchemaViolation(
            'invalid_store_manifest_fixture',
            '$path does not satisfy the immutable Store manifest schema.',
          ),
        );
      }
    }

    final futureRoot = _copyObject(documents[_rootManifestFixturePath]!)
      ..['formatVersion'] = 2;
    if (manifestValidator.validate(futureRoot).isValid) {
      violations.add(
        const AgentKernelSchemaViolation(
          'future_manifest_version_accepted',
          'Store manifest v1 schema accepted formatVersion 2.',
        ),
      );
    }

    final driftedSession = _copyObject(documents[_sessionManifestFixturePath]!)
      ..remove('retention');
    if (manifestValidator.validate(driftedSession).isValid) {
      violations.add(
        const AgentKernelSchemaViolation(
          'store_manifest_shape_drift_accepted',
          'Store manifest v1 schema accepted a Session without retention.',
        ),
      );
    }
  }

  return violations;
}

List<AgentKernelSchemaViolation> validateAgentEventDocument(
  Directory root,
  Object? document,
) {
  final violations = <AgentKernelSchemaViolation>[];
  final schema = _readObject(
    File.fromUri(root.uri.resolve(_eventSchemaPath)),
    _eventSchemaPath,
    violations,
  );
  if (schema == null) {
    return violations;
  }
  try {
    final validator = JsonSchema.create(
      schema,
      schemaVersion: SchemaVersion.draft2020_12,
    );
    final result = validator.validate(document);
    if (!result.isValid) {
      violations.add(
        AgentKernelSchemaViolation(
          'invalid_agent_event',
          result.errors.isEmpty
              ? 'AgentEvent does not satisfy v1 schema.'
              : result.errors.first.toString(),
        ),
      );
    }
  } on Object catch (error) {
    violations.add(
      AgentKernelSchemaViolation(
        'invalid_json_schema',
        'AgentEvent schema could not be compiled: $error',
      ),
    );
  }
  return violations;
}

List<AgentKernelSchemaViolation> validateAgentStoreManifestDocument(
  Directory root,
  Object? document,
) {
  final violations = <AgentKernelSchemaViolation>[];
  final schema = _readObject(
    File.fromUri(root.uri.resolve(_manifestSchemaPath)),
    _manifestSchemaPath,
    violations,
  );
  if (schema == null) {
    return violations;
  }
  try {
    final validator = JsonSchema.create(
      schema,
      schemaVersion: SchemaVersion.draft2020_12,
    );
    final result = validator.validate(document);
    if (!result.isValid) {
      violations.add(
        AgentKernelSchemaViolation(
          'invalid_store_manifest',
          result.errors.isEmpty
              ? 'Store manifest does not satisfy v1 schema.'
              : result.errors.first.toString(),
        ),
      );
    }
  } on Object catch (error) {
    violations.add(
      AgentKernelSchemaViolation(
        'invalid_json_schema',
        'Store manifest schema could not be compiled: $error',
      ),
    );
  }
  return violations;
}

void _validateInventory(
  Map<String, Object?> eventSchema,
  Map<String, Object?> inventory,
  List<AgentKernelSchemaViolation> violations,
) {
  if (!_sameSet(inventory.keys.toSet(), const <String>{
    'formatVersion',
    'schemaVersion',
    'events',
  })) {
    violations.add(
      const AgentKernelSchemaViolation(
        'invalid_inventory_shape',
        'Event inventory root keys must be formatVersion/schemaVersion/events.',
      ),
    );
  }
  if (inventory['formatVersion'] != 1 || inventory['schemaVersion'] != 1) {
    violations.add(
      const AgentKernelSchemaViolation(
        'invalid_inventory_version',
        'Event inventory formatVersion and schemaVersion must both be 1.',
      ),
    );
  }

  final rawEvents = inventory['events'];
  if (rawEvents is! List<Object?>) {
    violations.add(
      const AgentKernelSchemaViolation(
        'invalid_inventory_events',
        'Event inventory events must be an array.',
      ),
    );
    return;
  }

  final definitions = _object(eventSchema[r'$defs']);
  final schemaTypes = _eventTypeEnum(eventSchema);
  final actualByFamily = <String, Set<String>>{};
  final seenTypes = <String>{};
  final terminalTypes = <String>{};

  for (var index = 0; index < rawEvents.length; index += 1) {
    final event = _object(rawEvents[index]);
    if (event == null) {
      violations.add(
        AgentKernelSchemaViolation(
          'invalid_inventory_entry',
          'events[$index] must be an object.',
        ),
      );
      continue;
    }
    if (!_sameSet(event.keys.toSet(), _inventoryEntryKeys)) {
      violations.add(
        AgentKernelSchemaViolation(
          'invalid_inventory_entry',
          'events[$index] has missing or unknown fields.',
        ),
      );
      continue;
    }

    final type = event['type'];
    final family = event['family'];
    final requiredIds = _stringList(event['requiredContextIds']);
    final introducedIds = _stringList(event['introducedIdPaths']);
    final payloadRef = event['payloadSchemaRef'];
    final terminal = event['terminal'];
    final runBusinessEvent = event['runBusinessEvent'];
    final allowedAfterRunTerminal = event['allowedAfterRunTerminal'];
    if (type is! String ||
        family is! String ||
        requiredIds == null ||
        introducedIds == null ||
        payloadRef is! String ||
        terminal is! bool ||
        runBusinessEvent is! bool ||
        allowedAfterRunTerminal is! bool) {
      violations.add(
        AgentKernelSchemaViolation(
          'invalid_inventory_entry',
          'events[$index] contains a field with the wrong type.',
        ),
      );
      continue;
    }

    if (!seenTypes.add(type)) {
      violations.add(
        AgentKernelSchemaViolation(
          'duplicate_event_type',
          'Event type is duplicated: $type',
        ),
      );
    }
    actualByFamily.putIfAbsent(family, () => <String>{}).add(type);
    if (terminal) {
      terminalTypes.add(type);
    }
    if (requiredIds.length != requiredIds.toSet().length ||
        !requiredIds.every(_contextIdPaths.contains)) {
      violations.add(
        AgentKernelSchemaViolation(
          'invalid_required_context_ids',
          'Event $type has invalid or duplicate requiredContextIds.',
        ),
      );
    }
    if (introducedIds.length != introducedIds.toSet().length ||
        !introducedIds.every(_introducedIdPaths.contains)) {
      violations.add(
        AgentKernelSchemaViolation(
          'invalid_introduced_id_paths',
          'Event $type has invalid or duplicate introducedIdPaths.',
        ),
      );
    }
    final definitionName = _localDefinitionName(payloadRef);
    if (definitionName == null || definitions?[definitionName] == null) {
      violations.add(
        AgentKernelSchemaViolation(
          'missing_payload_schema_ref',
          'Event $type references missing payload schema $payloadRef.',
        ),
      );
    }
    if (runBusinessEvent && allowedAfterRunTerminal) {
      violations.add(
        AgentKernelSchemaViolation(
          'invalid_terminal_policy',
          'Run business event $type cannot be allowed after terminal.',
        ),
      );
    }
  }

  if (!_sameNestedSet(actualByFamily, _expectedEventsByFamily)) {
    violations.add(
      const AgentKernelSchemaViolation(
        'event_family_drift',
        'Event inventory does not exactly match the approved family set.',
      ),
    );
  }
  final expectedTypes =
      _expectedEventsByFamily.values.expand((events) => events).toSet();
  if (!_sameSet(seenTypes, expectedTypes)) {
    violations.add(
      const AgentKernelSchemaViolation(
        'event_type_drift',
        'Event inventory does not exactly match the approved event set.',
      ),
    );
  }
  if (!_sameSet(terminalTypes, _expectedEventsByFamily['runTerminal']!)) {
    violations.add(
      const AgentKernelSchemaViolation(
        'terminal_event_drift',
        'Exactly the four approved Run terminal events must be terminal.',
      ),
    );
  }
  if (!_sameSet(schemaTypes, expectedTypes)) {
    violations.add(
      const AgentKernelSchemaViolation(
        'schema_event_type_drift',
        'AgentEvent schema type enum and inventory must match exactly.',
      ),
    );
  }
}

Map<String, Object?>? _readObject(
  File file,
  String path,
  List<AgentKernelSchemaViolation> violations,
) {
  if (!file.existsSync()) {
    violations.add(
      AgentKernelSchemaViolation(
        'missing_schema_asset',
        'Required Agent Kernel schema asset is missing: $path',
      ),
    );
    return null;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    violations.add(
      AgentKernelSchemaViolation(
        'invalid_json_object',
        '$path must contain a JSON object.',
      ),
    );
  } on Object catch (error) {
    violations.add(
      AgentKernelSchemaViolation(
        'invalid_json',
        '$path is not valid JSON: $error',
      ),
    );
  }
  return null;
}

Set<String> _eventTypeEnum(Map<String, Object?> schema) {
  final properties = _object(schema['properties']);
  final type = _object(properties?['type']);
  return _stringList(type?['enum'])?.toSet() ?? <String>{};
}

String? _localDefinitionName(String reference) {
  const prefix = r'#/$defs/';
  if (!reference.startsWith(prefix) ||
      reference.length == prefix.length ||
      reference.substring(prefix.length).contains('/')) {
    return null;
  }
  return reference.substring(prefix.length);
}

Map<String, Object?> _copyObject(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

Map<String, Object?>? _object(Object? value) =>
    value is Map<String, Object?> ? value : null;

List<String>? _stringList(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    return null;
  }
  return value.cast<String>();
}

bool _sameSet(Set<String> actual, Set<String> expected) =>
    actual.length == expected.length && actual.containsAll(expected);

bool _sameNestedSet(
  Map<String, Set<String>> actual,
  Map<String, Set<String>> expected,
) {
  if (!_sameSet(actual.keys.toSet(), expected.keys.toSet())) {
    return false;
  }
  return expected.entries.every(
    (entry) => _sameSet(actual[entry.key] ?? <String>{}, entry.value),
  );
}
