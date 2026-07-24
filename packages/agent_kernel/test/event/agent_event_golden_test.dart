import 'dart:io';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('canonical event bytes preserve every stable field', () {
    final file = File.fromUri(
      _workspaceRoot().uri.resolve(
            'packages/agent_kernel/test/fixtures/events/canonical-event.json',
          ),
    );
    final golden = file.readAsStringSync().trim();
    final event = AgentEventCodec.instance.decode(golden);

    expect(AgentEventCodec.instance.encode(event), golden);
    expect(event.type, AgentEventType.sessionCreated);
    expect(event.sequence, 1);
    expect(event.recordedAt, DateTime.utc(2026, 7, 24));
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
