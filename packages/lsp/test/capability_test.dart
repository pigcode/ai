import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('interprets boolean, object, nested, and numeric capabilities', () {
    final snapshot = LspCapabilitySnapshot.fromInitialize(
      connectionId: 7,
      generation: 1,
      serverCapabilities: <String, Object?>{
        'hoverProvider': true,
        'definitionProvider': false,
        'completionProvider': <String, Object?>{'resolveProvider': true},
        'textDocumentSync': 2,
        'workspace': <String, Object?>{
          'workspaceFolders': <String, Object?>{
            'supported': true,
            'changeNotifications': 'workspace-folders',
          },
        },
      },
    );

    expect(snapshot.supportsMethod('textDocument/hover'), isTrue);
    expect(snapshot.supportsMethod('textDocument/definition'), isFalse);
    expect(snapshot.supportsMethod('completionItem/resolve'), isTrue);
    expect(snapshot.supportsMethod('textDocument/didOpen'), isTrue);
    expect(
      snapshot.supportsMethod('workspace/didChangeWorkspaceFolders'),
      isTrue,
    );
    expect(snapshot.supportsMethod('shutdown'), isTrue);
  });

  test('client rejects optional methods before allocating an id', () {
    final connection = LspConnection()
      ..beginInitialize()
      ..completeInitialize(<String, Object?>{'hoverProvider': false})
      ..sendInitialized();

    expect(
      () => connection.beginRequest('textDocument/hover'),
      throwsA(isA<LspCapabilityException>()),
    );
    expect(connection.nextRequestId, 1);
  });
}
