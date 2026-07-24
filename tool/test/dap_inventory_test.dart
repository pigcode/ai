import 'dart:convert';
import 'dart:io';

import '../src/dap_inventory.dart';
import '../src/schema/draft_04.dart';

void main() {
  final root = Directory.current;
  final inventory = buildDapInventory(root);

  _expect(inventory.definitionCount == 192, 'DAP definition count drift.');
  _expect(inventory.requestCount == 45, 'DAP concrete request count drift.');
  _expect(inventory.eventCount == 17, 'DAP concrete event count drift.');
  _expect(inventory.argumentCount == 44, 'DAP argument count drift.');
  _expect(inventory.closedEnumCount == 83, 'DAP closed enum count drift.');
  _expect(inventory.openEnumCount == 14, 'DAP open enum count drift.');
  _expect(
    inventory.classifications.length == inventory.definitionCount,
    'Every DAP definition must be classified.',
  );

  final schema = jsonDecode(
    File(
      'tool/upstream/protocols/dap/v1.71.0/debugAdapterProtocol.json',
    ).readAsStringSync(),
  ) as Map<String, Object?>;
  final validator = Draft04Validator.fromDocument(
    schema,
    entryRef: '#/definitions/Request',
  );
  _expect(
    validator.isValid(<String, Object?>{
      'seq': 1,
      'type': 'request',
      'command': 'initialize',
    }),
    'Pinned DAP request root must validate a concrete envelope.',
  );
  _expect(
    !validator.isValid(<String, Object?>{}),
    'Empty DAP request must fail the explicit concrete root.',
  );
  _expectThrows(
    () => Draft04Validator.fromDocument(schema, entryRef: '#'),
    'Draft-04 validator must reject a document-root entry ref.',
  );

  stdout.writeln('DAP inventory validation passed.');
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
