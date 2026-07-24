import 'dart:convert';
import 'dart:io';

import '../src/agent_kernel_schema.dart';

typedef _TestBody = void Function();

void main() {
  final root = Directory.current;
  final validEvent = _readObject(
    'tool/fixtures/agent_kernel/schema/valid-event.json',
  );
  final validRootManifest = _readObject(
    'tool/fixtures/agent_kernel/schema/valid-root-manifest.json',
  );
  final validSessionManifest = _readObject(
    'tool/fixtures/agent_kernel/schema/valid-session-manifest.json',
  );
  final tests = <String, _TestBody>{
    'all schema assets and inventory invariants pass': () {
      final violations = validateAgentKernelSchemaAssets(root);
      _expect(
        violations.isEmpty,
        'Expected no violations, got ${violations.join('; ')}',
      );
    },
    'valid event fixture is accepted': () {
      _expect(
        validateAgentEventDocument(root, validEvent).isEmpty,
        'Valid fixture was rejected.',
      );
    },
    'missing event ID is rejected': () {
      final missingId = _copy(validEvent)..remove('eventId');
      _expect(
        validateAgentEventDocument(root, missingId).isNotEmpty,
        'Missing eventId was accepted.',
      );
    },
    'future event schema version is rejected': () {
      final future = _copy(validEvent)..['schemaVersion'] = 2;
      _expect(
        validateAgentEventDocument(root, future).isNotEmpty,
        'Future schemaVersion was accepted.',
      );
    },
    'unknown event type is rejected': () {
      final unknown = _copy(validEvent)..['type'] = 'run.futureState';
      _expect(
        validateAgentEventDocument(root, unknown).isNotEmpty,
        'Unknown event type was accepted.',
      );
    },
    'real root and Session manifest shapes are accepted': () {
      _expect(
        validateAgentStoreManifestDocument(root, validRootManifest).isEmpty,
        'Root manifest fixture was rejected.',
      );
      _expect(
        validateAgentStoreManifestDocument(root, validSessionManifest).isEmpty,
        'Session manifest fixture was rejected.',
      );
    },
    'future and drifted Store manifests are rejected': () {
      final future = _copy(validRootManifest)..['formatVersion'] = 2;
      final drifted = _copy(validSessionManifest)..remove('retention');
      _expect(
        validateAgentStoreManifestDocument(root, future).isNotEmpty,
        'Future Store manifest version was accepted.',
      );
      _expect(
        validateAgentStoreManifestDocument(root, drifted).isNotEmpty,
        'Session manifest without retention was accepted.',
      );
    },
    'missing assets fail closed': () {
      final empty = Directory.systemTemp.createTempSync(
        'agent_kernel_schema_test_',
      );
      try {
        final violations = validateAgentKernelSchemaAssets(empty);
        _expect(
          violations.length == agentKernelSchemaAssetPaths.length,
          'Expected every missing asset to be reported, got '
          '${violations.length}.',
        );
        _expect(
          violations.every(
            (violation) => violation.code == 'missing_schema_asset',
          ),
          'Missing assets did not fail with the stable code.',
        );
      } finally {
        empty.deleteSync(recursive: true);
      }
    },
    'duplicate event types fail closed': () {
      _withAssetFixture(root, (fixture) {
        final inventoryFile = File.fromUri(
          fixture.uri.resolve(
            'tool/schema/agent_kernel/event-inventory-v1.json',
          ),
        );
        final inventory = _readFileObject(inventoryFile);
        final events = inventory['events']! as List<Object?>;
        final first = events.first! as Map<String, Object?>;
        final second = events[1]! as Map<String, Object?>;
        second['type'] = first['type'];
        _writeObject(inventoryFile, inventory);

        final violations = validateAgentKernelSchemaAssets(fixture);
        _expect(
          violations.any(
            (violation) => violation.code == 'duplicate_event_type',
          ),
          'Duplicate event type was not rejected.',
        );
      });
    },
    'missing payload ref and extra terminal fail closed': () {
      _withAssetFixture(root, (fixture) {
        final inventoryFile = File.fromUri(
          fixture.uri.resolve(
            'tool/schema/agent_kernel/event-inventory-v1.json',
          ),
        );
        final inventory = _readFileObject(inventoryFile);
        final events = inventory['events']! as List<Object?>;
        final first = events.first! as Map<String, Object?>;
        first
          ..['payloadSchemaRef'] = r'#/$defs/doesNotExist'
          ..['terminal'] = true;
        _writeObject(inventoryFile, inventory);

        final codes = validateAgentKernelSchemaAssets(
          fixture,
        ).map((violation) => violation.code).toSet();
        _expect(
          codes.contains('missing_payload_schema_ref') &&
              codes.contains('terminal_event_drift'),
          'Missing payload ref or extra terminal was not rejected: $codes',
        );
      });
    },
    'wrong JSON Schema draft fails closed': () {
      _withAssetFixture(root, (fixture) {
        final schemaFile = File.fromUri(
          fixture.uri.resolve(
            'tool/schema/agent_kernel/snapshot-v1.schema.json',
          ),
        );
        final schema = _readFileObject(schemaFile)
          ..[r'$schema'] = 'http://json-schema.org/draft-07/schema#';
        _writeObject(schemaFile, schema);

        final violations = validateAgentKernelSchemaAssets(fixture);
        _expect(
          violations.any(
            (violation) => violation.code == 'wrong_schema_draft',
          ),
          'Wrong JSON Schema draft was not rejected.',
        );
      });
    },
  };

  var failures = 0;
  for (final entry in tests.entries) {
    try {
      entry.value();
      stdout.writeln('PASS ${entry.key}');
    } on Object catch (error, stackTrace) {
      failures += 1;
      stderr.writeln('FAIL ${entry.key}: $error');
      stderr.writeln(stackTrace);
    }
  }
  if (failures != 0) {
    stderr.writeln('$failures test(s) failed.');
    exitCode = 1;
  }
}

Map<String, Object?> _readObject(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Map<String, Object?> _readFileObject(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

Map<String, Object?> _copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

void _writeObject(File file, Map<String, Object?> value) {
  file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(value)}\n');
}

void _withAssetFixture(
  Directory sourceRoot,
  void Function(Directory fixture) body,
) {
  final fixture = Directory.systemTemp.createTempSync(
    'agent_kernel_schema_assets_',
  );
  try {
    for (final path in agentKernelSchemaAssetPaths) {
      final source = File.fromUri(sourceRoot.uri.resolve(path));
      final target = File.fromUri(fixture.uri.resolve(path));
      target.parent.createSync(recursive: true);
      source.copySync(target.path);
    }
    body(fixture);
  } finally {
    fixture.deleteSync(recursive: true);
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
