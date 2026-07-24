import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('enforces initialize, shutdown, and exit ordering', () {
    final connection = _initializedConnection();
    final request = connection.beginRequest('textDocument/hover');
    expect(request.id, 1);
    connection.completeRequest(request.id);

    connection.beginShutdown();
    expect(connection.lifecycle, LspConnectionLifecycle.shutdownPending);
    expect(
      () => connection.beginRequest('textDocument/hover'),
      throwsA(isA<LspStateException>()),
    );
    expect(() => connection.sendExit(), throwsA(isA<LspStateException>()));

    connection.completeShutdown();
    expect(connection.lifecycle, LspConnectionLifecycle.shutdown);
    connection.sendExit();
    expect(connection.lifecycle, LspConnectionLifecycle.exited);
  });

  test('close completes pending requests exactly once', () {
    final connection = _initializedConnection();
    final request = connection.beginRequest('shutdown');
    connection.close();

    expect(request.done, isTrue);
    expect(request.failure, isA<LspStateException>());
    expect(() => connection.close(), returnsNormally);
  });
}

LspConnection _initializedConnection() {
  final connection = LspConnection();
  connection
    ..beginInitialize()
    ..completeInitialize(<String, Object?>{'hoverProvider': true})
    ..sendInitialized();
  return connection;
}
