import 'dart:convert';
import 'dart:io';

import 'protocol_sources.dart';
import 'schema/draft_04.dart';

final class DapInventory {
  const DapInventory({
    required this.definitionNames,
    required this.requestNames,
    required this.eventNames,
    required this.argumentNames,
    required this.closedEnumCount,
    required this.openEnumCount,
    required this.classifications,
  });

  final Set<String> definitionNames;
  final Set<String> requestNames;
  final Set<String> eventNames;
  final Set<String> argumentNames;
  final int closedEnumCount;
  final int openEnumCount;
  final Map<String, String> classifications;

  int get definitionCount => definitionNames.length;
  int get requestCount => requestNames.length;
  int get eventCount => eventNames.length;
  int get argumentCount => argumentNames.length;

  Map<String, Object?> toJson() => <String, Object?>{
        'source': 'dap-v1.71.0',
        'definitionCount': definitionCount,
        'definitions': _sorted(definitionNames),
        'requestCount': requestCount,
        'requests': _sorted(requestNames),
        'eventCount': eventCount,
        'events': _sorted(eventNames),
        'argumentCount': argumentCount,
        'arguments': _sorted(argumentNames),
        'closedEnumCount': closedEnumCount,
        'openEnumCount': openEnumCount,
        'classifications': <String, String>{
          for (final name in classifications.keys.toList()..sort())
            name: classifications[name]!,
        },
      };
}

DapInventory buildDapInventory(Directory root) {
  final schema = _readObject(
    root,
    'tool/upstream/protocols/dap/v1.71.0/debugAdapterProtocol.json',
  );
  final source = loadProtocolSourceLock(root).sources.singleWhere(
        (candidate) => candidate.sourceId == 'dap-v1.71.0',
      );
  if (source.entryRefs.isEmpty) {
    throw const FormatException('DAP source has no concrete entry refs.');
  }
  for (final entryRef in source.entryRefs) {
    Draft04Validator.fromDocument(schema, entryRef: entryRef);
  }

  final definitions = _object(schema['definitions'], 'DAP definitions');
  final definitionNames = definitions.keys.toSet();
  final requestNames = definitionNames
      .where((name) => name != 'Request' && name.endsWith('Request'))
      .toSet();
  final eventNames = definitionNames
      .where((name) => name != 'Event' && name.endsWith('Event'))
      .toSet();
  final argumentNames =
      definitionNames.where((name) => name.endsWith('Arguments')).toSet();
  final classifications = <String, String>{};
  for (final name in definitionNames) {
    classifications[name] = switch (name) {
      'ProtocolMessage' || 'Request' || 'Response' || 'Event' => 'envelope',
      _ when requestNames.contains(name) => 'request',
      _ when eventNames.contains(name) => 'event',
      _ when name.endsWith('Response') => 'response',
      _ when argumentNames.contains(name) => 'arguments',
      _ => 'type',
    };
  }

  var closedEnumCount = 0;
  var openEnumCount = 0;
  void visit(Object? value) {
    switch (value) {
      case final Map<String, Object?> object:
        if (object.containsKey('enum')) {
          closedEnumCount += 1;
        }
        if (object.containsKey('_enum')) {
          openEnumCount += 1;
        }
        for (final child in object.values) {
          visit(child);
        }
      case final List<Object?> list:
        for (final child in list) {
          visit(child);
        }
    }
  }

  visit(definitions);
  return DapInventory(
    definitionNames: Set<String>.unmodifiable(definitionNames),
    requestNames: Set<String>.unmodifiable(requestNames),
    eventNames: Set<String>.unmodifiable(eventNames),
    argumentNames: Set<String>.unmodifiable(argumentNames),
    closedEnumCount: closedEnumCount,
    openEnumCount: openEnumCount,
    classifications: Map<String, String>.unmodifiable(classifications),
  );
}

List<String> _sorted(Iterable<String> values) => values.toList()..sort();

Map<String, Object?> _readObject(Directory root, String relativePath) {
  final file = File.fromUri(root.absolute.uri.resolve(relativePath));
  return _object(jsonDecode(file.readAsStringSync()), relativePath);
}

Map<String, Object?> _object(Object? value, String location) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$location must be an object.');
  }
  return value;
}
