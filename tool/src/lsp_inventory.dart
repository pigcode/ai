import 'dart:convert';
import 'dart:io';

import 'schema/draft_07.dart';

final class LspInventory {
  const LspInventory({
    required this.version,
    required this.requestMethods,
    required this.notificationMethods,
    required this.structureNames,
    required this.enumerationNames,
    required this.typeAliasNames,
    required this.classifications,
  });

  final String version;
  final Set<String> requestMethods;
  final Set<String> notificationMethods;
  final Set<String> structureNames;
  final Set<String> enumerationNames;
  final Set<String> typeAliasNames;
  final Map<String, String> classifications;

  int get requestCount => requestMethods.length;
  int get notificationCount => notificationMethods.length;
  int get structureCount => structureNames.length;
  int get enumerationCount => enumerationNames.length;
  int get typeAliasCount => typeAliasNames.length;
  int get classifiedElementCount => classifications.length;

  Map<String, Object?> toJson() => <String, Object?>{
        'source': 'lsp-3.18-b7f5132',
        'version': version,
        'requests': _categoryJson(requestMethods, 'request'),
        'notifications': _categoryJson(notificationMethods, 'notification'),
        'structures': _categoryJson(structureNames, 'structure'),
        'enumerations': _categoryJson(enumerationNames, 'enumeration'),
        'typeAliases': _categoryJson(typeAliasNames, 'typeAlias'),
      };

  Map<String, Object?> _categoryJson(Set<String> names, String kind) =>
      <String, Object?>{
        'count': names.length,
        'stable': <String>[
          for (final name in names.toList()..sort())
            if (classifications['$kind:$name'] == 'stable') name,
        ],
        'proposed': <String>[
          for (final name in names.toList()..sort())
            if (classifications['$kind:$name'] == 'proposed') name,
        ],
      };
}

LspInventory buildLspInventory(Directory root) {
  final model = _readObject(
    root,
    'tool/upstream/protocols/lsp/3.18-b7f5132/metaModel.json',
  );
  final schema = _readObject(
    root,
    'tool/upstream/protocols/lsp/3.18-b7f5132/metaModel.schema.json',
  );
  final validator = Draft07Validator.fromDocument(
    schema,
    entryRef: '#/definitions/MetaModel',
  );
  if (!validator.isValid(model)) {
    throw const FormatException(
      'Pinned LSP meta-model does not satisfy MetaModel draft-07 root.',
    );
  }

  final metadata = _object(model['metaData'], 'LSP metaData');
  final version = _string(metadata['version'], 'LSP metaData.version');
  final classifications = <String, String>{};
  final requestMethods = _namedElements(
    model['requests'],
    location: 'LSP requests',
    key: 'method',
    kind: 'request',
    classifications: classifications,
  );
  final notificationMethods = _namedElements(
    model['notifications'],
    location: 'LSP notifications',
    key: 'method',
    kind: 'notification',
    classifications: classifications,
  );
  final structureNames = _namedElements(
    model['structures'],
    location: 'LSP structures',
    key: 'name',
    kind: 'structure',
    classifications: classifications,
  );
  final enumerationNames = _namedElements(
    model['enumerations'],
    location: 'LSP enumerations',
    key: 'name',
    kind: 'enumeration',
    classifications: classifications,
  );
  final typeAliasNames = _namedElements(
    model['typeAliases'],
    location: 'LSP type aliases',
    key: 'name',
    kind: 'typeAlias',
    classifications: classifications,
  );

  return LspInventory(
    version: version,
    requestMethods: Set<String>.unmodifiable(requestMethods),
    notificationMethods: Set<String>.unmodifiable(notificationMethods),
    structureNames: Set<String>.unmodifiable(structureNames),
    enumerationNames: Set<String>.unmodifiable(enumerationNames),
    typeAliasNames: Set<String>.unmodifiable(typeAliasNames),
    classifications: Map<String, String>.unmodifiable(classifications),
  );
}

Set<String> _namedElements(
  Object? value, {
  required String location,
  required String key,
  required String kind,
  required Map<String, String> classifications,
}) {
  final values = _list(value, location);
  final names = <String>{};
  for (var index = 0; index < values.length; index += 1) {
    final element = _object(values[index], '$location[$index]');
    final name = _string(element[key], '$location[$index].$key');
    if (!names.add(name)) {
      throw FormatException('Duplicate $kind name: $name.');
    }
    final proposed = switch (element['proposed']) {
      null || false => false,
      true => true,
      _ => throw FormatException('$location[$index].proposed is not boolean.'),
    };
    classifications['$kind:$name'] = proposed ? 'proposed' : 'stable';
  }
  return names;
}

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

List<Object?> _list(Object? value, String location) {
  if (value is! List<Object?>) {
    throw FormatException('$location must be a list.');
  }
  return value;
}

String _string(Object? value, String location) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$location must be a non-empty string.');
  }
  return value;
}
