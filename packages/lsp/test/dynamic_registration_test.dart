import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('register and unregister atomically advance snapshot generation', () {
    final connection = LspConnection()
      ..beginInitialize()
      ..completeInitialize(<String, Object?>{'hoverProvider': false})
      ..sendInitialized();

    final first = connection.capabilities;
    connection.registerCapability(
      const LspDynamicRegistration(
        id: 'hover-1',
        method: 'textDocument/hover',
        registerOptions: <String, Object?>{},
      ),
    );
    final registered = connection.capabilities;
    expect(registered.generation, first.generation + 1);
    expect(registered.supportsMethod('textDocument/hover'), isTrue);
    expect(first.supportsMethod('textDocument/hover'), isFalse);
    expect(
      () => connection.registerCapability(
        const LspDynamicRegistration(
          id: 'hover-1',
          method: 'textDocument/hover',
          registerOptions: <String, Object?>{},
        ),
      ),
      throwsA(isA<LspRegistrationException>()),
    );

    connection.unregisterCapability('hover-1');
    expect(connection.capabilities.generation, registered.generation + 1);
    expect(
        connection.capabilities.supportsMethod('textDocument/hover'), isFalse);
    expect(
      () => connection.unregisterCapability('hover-1'),
      throwsA(isA<LspRegistrationException>()),
    );
  });

  test('handler registry rejects missing and duplicate handlers', () {
    final handlers = LspHandlerRegistry();
    expect(
      () => handlers.dispatch('workspace/configuration', const {}),
      throwsA(isA<LspHandlerException>()),
    );
    handlers.register('workspace/configuration', (params) => params);
    expect(
      () => handlers.register('workspace/configuration', (params) => params),
      throwsA(isA<LspHandlerException>()),
    );
    expect(
      handlers
          .dispatch('workspace/configuration', const {'items': <Object?>[]}),
      const {'items': <Object?>[]},
    );
  });
}
