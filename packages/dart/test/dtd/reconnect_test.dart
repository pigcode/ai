import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';
import 'package:test/test.dart';

void main() {
  test('reconnect closes pending work and replaces every generation', () {
    final client = DtdClient();
    final pending = client.connection.beginRequest(
      'FileSystem.getIDEWorkspaceRoots',
      params: const <String, Object?>{},
    );
    final oldConnectionId = client.connection.connectionId;

    final replacement = client.reconnect();

    expect(pending.done, isTrue);
    expect(pending.failure, isA<ToolingProtocolStateError>());
    expect(replacement.connection.connectionId, isNot(oldConnectionId));
    expect(client.connection.lifecycle, DtdConnectionLifecycle.closed);
    expect(replacement.connection.lifecycle, DtdConnectionLifecycle.open);
  });
}
