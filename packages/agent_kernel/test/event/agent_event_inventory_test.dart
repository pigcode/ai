import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('inventory, codec types, and checked-in fixtures are one-to-one', () {
    final root = _workspaceRoot();
    final inventory = _readObject(
      File.fromUri(
        root.uri.resolve(
          'tool/schema/agent_kernel/event-inventory-v1.json',
        ),
      ),
    );
    final inventoryEvents =
        (inventory['events']! as List<Object?>).cast<Map<String, Object?>>();
    final inventoryTypes =
        inventoryEvents.map((event) => event['type']! as String).toSet();

    final fixture = _readObject(
      File.fromUri(
        root.uri.resolve(
          'packages/agent_kernel/test/fixtures/events/all-events.json',
        ),
      ),
    );
    final fixtureTypes =
        (fixture['events']! as Map<String, Object?>).keys.toSet();
    final codecTypes =
        AgentEventType.values.map((type) => type.wireName).toSet();

    expect(inventoryTypes, codecTypes);
    expect(fixtureTypes, codecTypes);
  });

  test('every checked-in event fixture decodes with its exact discriminant',
      () {
    final root = _workspaceRoot();
    final fixture = _readObject(
      File.fromUri(
        root.uri.resolve(
          'packages/agent_kernel/test/fixtures/events/all-events.json',
        ),
      ),
    );
    final base = (fixture['base']! as Map<String, Object?>);
    final events = fixture['events']! as Map<String, Object?>;
    var sequence = 0;

    for (final entry in events.entries) {
      sequence += 1;
      final override = entry.value! as Map<String, Object?>;
      final document = <String, Object?>{
        ...base,
        ...override,
        'type': entry.key,
        'sequence': sequence,
      };
      final event = AgentEventCodec.instance.decodeObject(document);
      expect(event.type.wireName, entry.key);
    }
  });
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (!File.fromUri(current.uri.resolve('pubspec.yaml')).existsSync() ||
      !Directory.fromUri(current.uri.resolve('tool/')).existsSync()) {
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Unable to locate workspace root.');
    }
    current = parent;
  }
  return current;
}

Map<String, Object?> _readObject(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
