import 'errors.dart';

/// Zero-based UTF-16 position in an LSP text document.
final class LspTextPosition {
  const LspTextPosition({
    required this.line,
    required this.character,
  });

  final int line;
  final int character;
}

/// Half-open LSP text range.
final class LspTextRange {
  const LspTextRange({
    required this.start,
    required this.end,
  });

  final LspTextPosition start;
  final LspTextPosition end;
}

/// Full-document or ranged text change.
final class LspContentChange {
  const LspContentChange({
    this.range,
    required this.text,
  });

  final LspTextRange? range;
  final String text;
}

/// Immutable snapshot of one open document generation.
final class LspDocumentSnapshot {
  const LspDocumentSnapshot._({
    required this.connectionId,
    required this.generation,
    required this.uri,
    required this.languageId,
    required this.version,
    required this.text,
    required this.open,
  });

  final int connectionId;
  final int generation;
  final String uri;
  final String languageId;
  final int version;
  final String text;
  final bool open;
}

/// In-memory LSP document state; never reads or writes the filesystem.
final class LspDocumentStore {
  LspDocumentStore({required this.connectionId});

  final int connectionId;
  int _generation = 0;
  final Map<String, LspDocumentSnapshot> _documents =
      <String, LspDocumentSnapshot>{};

  bool contains(String uri) => _documents.containsKey(uri);

  LspDocumentSnapshot open({
    required String uri,
    required String languageId,
    required int version,
    required String text,
  }) {
    if (_documents.containsKey(uri)) {
      throw LspDocumentException(
        'lsp_document_already_open',
        'LSP document is already open.',
        uri: uri,
      );
    }
    final snapshot = LspDocumentSnapshot._(
      connectionId: connectionId,
      generation: ++_generation,
      uri: uri,
      languageId: languageId,
      version: version,
      text: text,
      open: true,
    );
    _documents[uri] = snapshot;
    return snapshot;
  }

  LspDocumentSnapshot change({
    required String uri,
    required int version,
    required List<LspContentChange> changes,
  }) {
    final current = _requireOpen(uri);
    if (version <= current.version) {
      throw LspDocumentException(
        'lsp_content_modified',
        'LSP document version must advance monotonically.',
        uri: uri,
      );
    }
    if (changes.isEmpty) {
      throw LspDocumentException(
        'lsp_content_change_empty',
        'LSP document change list must be non-empty.',
        uri: uri,
      );
    }
    var text = current.text;
    for (final change in changes) {
      final range = change.range;
      if (range == null) {
        text = change.text;
        continue;
      }
      final start = _offset(text, range.start, uri);
      final end = _offset(text, range.end, uri);
      if (end < start) {
        throw LspDocumentException(
          'lsp_content_range_invalid',
          'LSP content-change range end precedes its start.',
          uri: uri,
        );
      }
      text = text.replaceRange(start, end, change.text);
    }
    final snapshot = LspDocumentSnapshot._(
      connectionId: connectionId,
      generation: ++_generation,
      uri: uri,
      languageId: current.languageId,
      version: version,
      text: text,
      open: true,
    );
    _documents[uri] = snapshot;
    return snapshot;
  }

  LspDocumentSnapshot close(String uri) {
    final current = _requireOpen(uri);
    _documents.remove(uri);
    return LspDocumentSnapshot._(
      connectionId: connectionId,
      generation: ++_generation,
      uri: uri,
      languageId: current.languageId,
      version: current.version,
      text: current.text,
      open: false,
    );
  }

  LspDocumentSnapshot current(String uri) => _requireOpen(uri);

  void assertCurrent(LspDocumentSnapshot snapshot) {
    final current = _documents[snapshot.uri];
    if (snapshot.connectionId != connectionId ||
        current == null ||
        current.generation != snapshot.generation) {
      throw LspDocumentException(
        'lsp_document_generation_stale',
        'LSP document snapshot belongs to a stale connection generation.',
        uri: snapshot.uri,
      );
    }
  }

  LspDocumentSnapshot _requireOpen(String uri) {
    final document = _documents[uri];
    if (document == null) {
      throw LspDocumentException(
        'lsp_document_not_open',
        'LSP document is not open.',
        uri: uri,
      );
    }
    return document;
  }
}

int _offset(String text, LspTextPosition position, String uri) {
  if (position.line < 0 || position.character < 0) {
    throw LspDocumentException(
      'lsp_content_position_invalid',
      'LSP text position cannot be negative.',
      uri: uri,
    );
  }
  var line = 0;
  var lineStart = 0;
  while (line < position.line) {
    final newline = text.indexOf('\n', lineStart);
    if (newline < 0) {
      throw LspDocumentException(
        'lsp_content_position_invalid',
        'LSP text position line is outside the document.',
        uri: uri,
      );
    }
    lineStart = newline + 1;
    line += 1;
  }
  final newline = text.indexOf('\n', lineStart);
  var lineEnd = newline < 0 ? text.length : newline;
  if (lineEnd > lineStart && text.codeUnitAt(lineEnd - 1) == 13) {
    lineEnd -= 1;
  }
  if (position.character > lineEnd - lineStart) {
    throw LspDocumentException(
      'lsp_content_position_invalid',
      'LSP text position character is outside the line.',
      uri: uri,
    );
  }
  return lineStart + position.character;
}
