import 'dart:convert';
import 'dart:io';

import '../src/lsp_inventory.dart';
import '../src/schema/draft_07.dart';

void main() {
  final root = Directory.current;
  final inventory = buildLspInventory(root);

  _expect(inventory.version == '3.18.0', 'LSP meta-model version drift.');
  _expect(inventory.requestCount == 69, 'LSP request count drift.');
  _expect(inventory.notificationCount == 26, 'LSP notification count drift.');
  _expect(inventory.structureCount == 387, 'LSP structure count drift.');
  _expect(inventory.enumerationCount == 40, 'LSP enumeration count drift.');
  _expect(inventory.typeAliasCount == 23, 'LSP type-alias count drift.');
  _expect(
    inventory.classifiedElementCount == 545,
    'Every LSP top-level element must be classified.',
  );
  _expect(
    inventory.requestMethods.length == inventory.requestCount,
    'LSP request methods must be unique.',
  );
  _expect(
    inventory.notificationMethods.length == inventory.notificationCount,
    'LSP notification methods must be unique.',
  );

  final schema = jsonDecode(
    File(
      'tool/upstream/protocols/lsp/3.18-b7f5132/'
      'metaModel.schema.json',
    ).readAsStringSync(),
  ) as Map<String, Object?>;
  final model = jsonDecode(
    File(
      'tool/upstream/protocols/lsp/3.18-b7f5132/metaModel.json',
    ).readAsStringSync(),
  );
  final validator = Draft07Validator.fromDocument(
    schema,
    entryRef: '#/definitions/MetaModel',
  );
  _expect(validator.isValid(model), 'Pinned LSP meta-model must validate.');
  _expect(
    !validator.isValid(<String, Object?>{}),
    'Empty LSP meta-model must fail the explicit entry root.',
  );
  _expectThrows(
    () => Draft07Validator.fromDocument(schema, entryRef: ''),
    'Draft-07 validator must reject an empty entry ref.',
  );

  stdout.writeln('LSP inventory validation passed.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

void _expectThrows(void Function() body, String message) {
  try {
    body();
  } on FormatException {
    return;
  }
  throw StateError(message);
}
