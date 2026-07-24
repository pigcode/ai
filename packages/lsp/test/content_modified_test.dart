import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('rejects stale versions and invalid ranges as content modified', () {
    final documents = LspDocumentStore(connectionId: 1)
      ..open(
        uri: 'file:///a.dart',
        languageId: 'dart',
        version: 4,
        text: 'abc',
      );

    expect(
      () => documents.change(
        uri: 'file:///a.dart',
        version: 4,
        changes: const [LspContentChange(text: 'new')],
      ),
      throwsA(
        isA<LspDocumentException>().having(
          (error) => error.code,
          'code',
          'lsp_content_modified',
        ),
      ),
    );
    expect(
      () => documents.change(
        uri: 'file:///a.dart',
        version: 5,
        changes: const [
          LspContentChange(
            range: LspTextRange(
              start: LspTextPosition(line: 0, character: 4),
              end: LspTextPosition(line: 0, character: 5),
            ),
            text: 'x',
          ),
        ],
      ),
      throwsA(isA<LspDocumentException>()),
    );
  });

  test('rejects a document snapshot from another connection generation', () {
    final first = LspDocumentStore(connectionId: 1);
    final snapshot = first.open(
      uri: 'file:///a.dart',
      languageId: 'dart',
      version: 1,
      text: '',
    );
    final replacement = LspDocumentStore(connectionId: 2);
    expect(
      () => replacement.assertCurrent(snapshot),
      throwsA(isA<LspDocumentException>()),
    );
  });
}
