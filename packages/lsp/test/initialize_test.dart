import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('initialize completes once and publishes an immutable snapshot', () {
    final connection = LspConnection();

    connection.beginInitialize();
    expect(connection.lifecycle, LspConnectionLifecycle.initializePending);
    expect(
      () => connection.beginRequest('textDocument/hover'),
      throwsA(isA<LspStateException>()),
    );
    expect(
      () => connection.beginInitialize(),
      throwsA(isA<LspStateException>()),
    );

    final source = <String, Object?>{
      'hoverProvider': true,
      'completionProvider': <String, Object?>{'resolveProvider': true},
    };
    connection.completeInitialize(source);
    source['hoverProvider'] = false;
    connection.sendInitialized();

    expect(connection.lifecycle, LspConnectionLifecycle.initialized);
    expect(
        connection.capabilities.supportsMethod('textDocument/hover'), isTrue);
    expect(
      connection.capabilities.supportsMethod('completionItem/resolve'),
      isTrue,
    );
  });
}
