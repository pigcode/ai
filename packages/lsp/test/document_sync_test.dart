import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('opens, incrementally changes, and closes versioned documents', () {
    final documents = LspDocumentStore(connectionId: 9);
    final opened = documents.open(
      uri: 'file:///sample.dart',
      languageId: 'dart',
      version: 1,
      text: 'a\nbc',
    );
    expect(opened.generation, 1);

    final changed = documents.change(
      uri: opened.uri,
      version: 2,
      changes: const [
        LspContentChange(
          range: LspTextRange(
            start: LspTextPosition(line: 1, character: 1),
            end: LspTextPosition(line: 1, character: 2),
          ),
          text: 'x',
        ),
      ],
    );
    expect(changed.text, 'a\nbx');
    expect(changed.version, 2);
    expect(changed.generation, 2);

    final closed = documents.close(opened.uri);
    expect(closed.generation, 3);
    expect(documents.contains(opened.uri), isFalse);
  });
}
