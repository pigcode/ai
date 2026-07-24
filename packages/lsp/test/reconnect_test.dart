import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('reconnect invalidates old identity, requests, and capabilities', () {
    final original = LspConnection()
      ..beginInitialize()
      ..completeInitialize(<String, Object?>{'hoverProvider': true})
      ..sendInitialized();
    final oldSnapshot = original.capabilities;
    final pending = original.beginRequest('textDocument/hover');

    final replacement = original.reconnect();

    expect(replacement.connectionId, isNot(original.connectionId));
    expect(replacement.lifecycle, LspConnectionLifecycle.created);
    expect(pending.done, isTrue);
    expect(
      () => replacement.assertCurrentSnapshot(oldSnapshot),
      throwsA(isA<LspStateException>()),
    );
    expect(
      () => original.beginInitialize(),
      throwsA(isA<LspStateException>()),
    );
  });
}
