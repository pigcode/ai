import 'dart:convert';
import 'dart:io';

import 'protocol_sources.dart';

final class AnalysisServerGeneratedArtifacts {
  const AnalysisServerGeneratedArtifacts({
    required this.inventoryDart,
    required this.modelsDart,
  });

  final String inventoryDart;
  final String modelsDart;
}

AnalysisServerGeneratedArtifacts buildAnalysisServerGeneratedArtifacts(
  Directory root,
) {
  final sources = loadProtocolSourceLock(root)
      .sources
      .where((source) => source.protocol == 'dart-tooling')
      .toList(growable: false);
  final minimumSource = sources.singleWhere(
    (source) => source.sdkRole == ProtocolSdkRole.minimum,
  );
  final currentSource = sources.singleWhere(
    (source) => source.sdkRole == ProtocolSdkRole.current,
  );
  final minimum = _parseSnapshot(root, minimumSource);
  final current = _parseSnapshot(root, currentSource);

  _validateOracle(root, minimum);
  _validateOracle(root, current);

  final currentOnlyRequests =
      current.requests.keys.toSet().difference(minimum.requests.keys.toSet());
  final minimumOnlyRequests =
      minimum.requests.keys.toSet().difference(current.requests.keys.toSet());
  final currentOnlyNotifications = current.notifications.keys
      .toSet()
      .difference(minimum.notifications.keys.toSet());
  final minimumOnlyNotifications = minimum.notifications.keys
      .toSet()
      .difference(current.notifications.keys.toSet());
  final currentOnlyTypes =
      current.types.keys.toSet().difference(minimum.types.keys.toSet());
  final minimumOnlyTypes =
      minimum.types.keys.toSet().difference(current.types.keys.toSet());

  if (currentOnlyRequests.isNotEmpty ||
      minimumOnlyRequests.isNotEmpty ||
      currentOnlyNotifications.length != 1 ||
      !currentOnlyNotifications.contains('server.pluginError') ||
      minimumOnlyNotifications.isNotEmpty ||
      currentOnlyTypes.isNotEmpty ||
      minimumOnlyTypes.isNotEmpty) {
    throw StateError(
      'Unclassified Analysis Server name diff: '
      'current requests=$currentOnlyRequests, '
      'minimum requests=$minimumOnlyRequests, '
      'current notifications=$currentOnlyNotifications, '
      'minimum notifications=$minimumOnlyNotifications, '
      'current types=$currentOnlyTypes, minimum types=$minimumOnlyTypes.',
    );
  }

  final changedDefinitions = <String>[];
  for (final method in current.requests.keys) {
    final previous = minimum.requests[method];
    if (previous != null &&
        jsonEncode(previous) != jsonEncode(current.requests[method])) {
      changedDefinitions.add('request:$method');
    }
  }
  for (final notification in current.notifications.keys) {
    final previous = minimum.notifications[notification];
    if (previous != null &&
        jsonEncode(previous) !=
            jsonEncode(current.notifications[notification])) {
      changedDefinitions.add('notification:$notification');
    }
  }
  for (final type in current.types.keys) {
    final previous = minimum.types[type];
    if (previous != null &&
        jsonEncode(previous) != jsonEncode(current.types[type])) {
      changedDefinitions.add('type:$type');
    }
  }
  changedDefinitions.sort();
  const classifiedChangedDefinitions = <String>{
    'request:server.setClientCapabilities',
  };
  final unclassifiedChangedDefinitions = changedDefinitions.toSet()
    ..removeAll(classifiedChangedDefinitions);
  final missingChangedDefinitions =
      classifiedChangedDefinitions.difference(changedDefinitions.toSet());
  if (unclassifiedChangedDefinitions.isNotEmpty ||
      missingChangedDefinitions.isNotEmpty) {
    throw StateError(
      'Unclassified Analysis Server structural diff: '
      'unclassified=$unclassifiedChangedDefinitions, '
      'missing=$missingChangedDefinitions.',
    );
  }

  final requests = <String, Object?>{
    for (final name
        in <String>{...minimum.requests.keys, ...current.requests.keys}.toList()
          ..sort())
      name: <String, Object?>{
        'introduced': minimum.requests.containsKey(name)
            ? minimum.apiVersion
            : current.apiVersion,
        'minimum': minimum.requests.containsKey(name),
        'current': current.requests.containsKey(name),
        ...?current.requests[name] ?? minimum.requests[name],
      },
  };
  final notifications = <String, Object?>{
    for (final name in <String>{
      ...minimum.notifications.keys,
      ...current.notifications.keys,
    }.toList()
      ..sort())
      name: <String, Object?>{
        'introduced': minimum.notifications.containsKey(name)
            ? minimum.apiVersion
            : current.apiVersion,
        'minimum': minimum.notifications.containsKey(name),
        'current': current.notifications.containsKey(name),
        ...?current.notifications[name] ?? minimum.notifications[name],
      },
  };
  final types = <String, Object?>{
    for (final name in current.types.keys.toList()..sort())
      name: current.types[name],
  };
  final enums = <String, Object?>{
    for (final name in current.enums.keys.toList()..sort())
      name: current.enums[name]!.toList()..sort(),
  };
  final document = <String, Object?>{
    'formatVersion': 1,
    'minimum': minimum.identityJson(),
    'current': current.identityJson(),
    'minimumRequestNames': minimum.requests.keys.toList()..sort(),
    'currentRequestNames': current.requests.keys.toList()..sort(),
    'minimumNotificationNames': minimum.notifications.keys.toList()..sort(),
    'currentNotificationNames': current.notifications.keys.toList()..sort(),
    'currentOnlyNotificationNames': currentOnlyNotifications.toList()..sort(),
    'minimumOnlyNames': <String>[
      ...minimumOnlyRequests,
      ...minimumOnlyNotifications,
      ...minimumOnlyTypes,
    ]..sort(),
    'requests': requests,
    'notifications': notifications,
    'types': types,
    'enums': enums,
    'changedDefinitions': changedDefinitions,
    'unclassifiedChangedDefinitions': unclassifiedChangedDefinitions.toList()
      ..sort(),
  };
  final inventoryJson = const JsonEncoder.withIndent('  ').convert(document);

  return AnalysisServerGeneratedArtifacts(
    inventoryDart: <String>[
      '// GENERATED CODE - DO NOT MODIFY BY HAND.',
      '// Source: Dart Analysis Server API 1.38.0/1.40.1, format 1.',
      '',
      "const analysisServerGeneratedInventoryJson = r'''$inventoryJson''';",
      '',
    ].join('\n'),
    modelsDart: _buildModels(current.types.keys),
  );
}

final class _AnalysisServerSnapshot {
  const _AnalysisServerSnapshot({
    required this.release,
    required this.revision,
    required this.apiVersion,
    required this.specSha256,
    required this.requests,
    required this.notifications,
    required this.types,
    required this.enums,
  });

  final String release;
  final String revision;
  final String apiVersion;
  final String specSha256;
  final Map<String, Map<String, Object?>> requests;
  final Map<String, Map<String, Object?>> notifications;
  final Map<String, Map<String, Object?>> types;
  final Map<String, Set<String>> enums;

  Map<String, Object?> identityJson() => <String, Object?>{
        'release': release,
        'revision': revision,
        'apiVersion': apiVersion,
        'specSha256': specSha256,
      };
}

_AnalysisServerSnapshot _parseSnapshot(
  Directory root,
  ProtocolSource source,
) {
  final base =
      'tool/upstream/protocols/dart/${source.release}/analysis_server/';
  final specPath = '${base}spec_input.html';
  final document =
      File.fromUri(root.absolute.uri.resolve(specPath)).readAsStringSync();
  final apiVersion = RegExp(r'<version>\s*([^<]+)\s*</version>')
      .firstMatch(document)
      ?.group(1);
  if (apiVersion == null ||
      apiVersion != source.componentVersions['analysisServerApi']) {
    throw StateError('Analysis Server version mismatch for ${source.release}.');
  }
  final artifact = source.artifacts.singleWhere(
    (artifact) => artifact.path == specPath,
  );
  final requests = <String, Map<String, Object?>>{};
  final notifications = <String, Map<String, Object?>>{};
  for (final domain in _elements(document, 'domain')) {
    final domainName = _attribute(domain.attributes, 'name');
    if (domainName == null) {
      continue;
    }
    for (final request in _elements(domain.body, 'request')) {
      final method = _requiredAttribute(request.attributes, 'method');
      requests['$domainName.$method'] = <String, Object?>{
        'params': _containerShape(request.body, 'params'),
        'result': _containerShape(request.body, 'result'),
      };
    }
    for (final notification in _elements(domain.body, 'notification')) {
      final event = _requiredAttribute(notification.attributes, 'event');
      notifications['$domainName.$event'] = <String, Object?>{
        'params': _containerShape(notification.body, 'params'),
      };
    }
  }

  final types = <String, Map<String, Object?>>{};
  final enums = <String, Set<String>>{};
  for (final type in _elements(document, 'type')) {
    final name = _requiredAttribute(type.attributes, 'name');
    final shape = _parseShape(type.body);
    types[name] = shape;
    if (shape['kind'] == 'enum') {
      enums[name] = (shape['values']! as List<Object?>).cast<String>().toSet();
    }
  }
  return _AnalysisServerSnapshot(
    release: source.release,
    revision: source.revision,
    apiVersion: apiVersion,
    specSha256: artifact.sha256,
    requests: _sortedMap(requests),
    notifications: _sortedMap(notifications),
    types: _sortedMap(types),
    enums: _sortedMap(enums),
  );
}

void _validateOracle(Directory root, _AnalysisServerSnapshot snapshot) {
  final base =
      'tool/upstream/protocols/dart/${snapshot.release}/analysis_server/';
  final constants = File.fromUri(
    root.absolute.uri.resolve('${base}protocol_constants.dart'),
  ).readAsStringSync();
  final generated = File.fromUri(
    root.absolute.uri.resolve('${base}protocol_generated.dart'),
  ).readAsStringSync();
  final api = File.fromUri(root.absolute.uri.resolve('${base}api.html'))
      .readAsStringSync();
  if (!constants.contains(
    "const String PROTOCOL_VERSION = '${snapshot.apiVersion}';",
  )) {
    throw StateError(
      'Analysis Server constants version mismatch for ${snapshot.release}.',
    );
  }
  if (!api.contains(snapshot.apiVersion)) {
    throw StateError(
      'Analysis Server API HTML version mismatch for ${snapshot.release}.',
    );
  }
  for (final name in <String>{
    ...snapshot.requests.keys,
    ...snapshot.notifications.keys,
  }) {
    if (!constants.contains("'$name'")) {
      throw StateError(
        'Analysis Server constants omit $name for ${snapshot.release}.',
      );
    }
  }
  for (final name in snapshot.types.keys) {
    final kind = snapshot.types[name]!['kind'];
    final declared = switch (kind) {
      'object' => RegExp(
          '^class ${RegExp.escape(name)}\\b',
          multiLine: true,
        ).hasMatch(generated),
      'enum' => RegExp(
          '^(?:class|enum) ${RegExp.escape(name)}\\b',
          multiLine: true,
        ).hasMatch(generated),
      _ => generated.contains(name),
    };
    if (!declared) {
      throw StateError(
        'Analysis Server generated oracle omits $name '
        'for ${snapshot.release}.',
      );
    }
  }
}

Map<String, Object?>? _containerShape(String source, String tag) {
  final element = _elements(source, tag).firstOrNull;
  return element == null ? null : _objectShape(element.body);
}

Map<String, Object?> _parseShape(String source) {
  final candidates = <({int index, String tag})>[];
  for (final tag in const <String>[
    'ref',
    'list',
    'map',
    'object',
    'union',
    'enum',
  ]) {
    final match = RegExp('<$tag\\b').firstMatch(source);
    if (match != null) {
      candidates.add((index: match.start, tag: tag));
    }
  }
  if (candidates.isEmpty) {
    return const <String, Object?>{'kind': 'any'};
  }
  candidates.sort((left, right) => left.index.compareTo(right.index));
  final tag = candidates.first.tag;
  final element = _elements(source, tag).first;
  switch (tag) {
    case 'ref':
      return <String, Object?>{
        'kind': 'ref',
        'name': _decodeText(element.body.trim()),
      };
    case 'list':
      return <String, Object?>{
        'kind': 'list',
        'item': _parseShape(element.body),
      };
    case 'map':
      final key = _elements(element.body, 'key').firstOrNull;
      final value = _elements(element.body, 'value').firstOrNull;
      return <String, Object?>{
        'kind': 'map',
        'key': key == null
            ? const <String, Object?>{'kind': 'ref', 'name': 'String'}
            : _parseShape(key.body),
        'value': value == null
            ? const <String, Object?>{'kind': 'any'}
            : _parseShape(value.body),
      };
    case 'object':
      return _objectShape(element.body);
    case 'union':
      return <String, Object?>{
        'kind': 'union',
        'discriminator': _attribute(element.attributes, 'field'),
        'options': <Object?>[
          for (final reference in _elements(element.body, 'ref'))
            <String, Object?>{
              'kind': 'ref',
              'name': _decodeText(reference.body.trim()),
            },
        ],
      };
    case 'enum':
      return <String, Object?>{
        'kind': 'enum',
        'values': <String>[
          for (final value in _elements(element.body, 'value'))
            if (_elements(value.body, 'code').firstOrNull
                case final _Element code)
              _decodeText(code.body.trim()),
        ],
      };
  }
  throw StateError('Unsupported Analysis Server shape tag: $tag.');
}

Map<String, Object?> _objectShape(String source) {
  final fields = <String, Object?>{};
  for (final field in _elements(source, 'field')) {
    final name = _requiredAttribute(field.attributes, 'name');
    fields[name] = <String, Object?>{
      'required': _attribute(field.attributes, 'optional') != 'true',
      'shape': _parseShape(field.body),
    };
  }
  return <String, Object?>{
    'kind': 'object',
    'fields': _sortedMap(fields),
  };
}

final class _Element {
  const _Element({
    required this.attributes,
    required this.body,
  });

  final String attributes;
  final String body;
}

List<_Element> _elements(String source, String tag) {
  final results = <_Element>[];
  final opening = RegExp('<$tag\\b([^>]*)>');
  var offset = 0;
  while (true) {
    final start = opening.matchAsPrefix(source, offset) ??
        opening.allMatches(source, offset).firstOrNull;
    if (start == null) {
      break;
    }
    final token = RegExp('</?$tag\\b[^>]*>');
    var depth = 1;
    var cursor = start.end;
    Match? closing;
    for (final match in token.allMatches(source, cursor)) {
      if (source.startsWith('</', match.start)) {
        depth -= 1;
        if (depth == 0) {
          closing = match;
          break;
        }
      } else {
        depth += 1;
      }
    }
    if (closing == null) {
      throw FormatException('Unclosed <$tag> element.');
    }
    results.add(
      _Element(
        attributes: start.group(1) ?? '',
        body: source.substring(start.end, closing.start),
      ),
    );
    offset = closing.end;
  }
  return results;
}

String? _attribute(String attributes, String name) =>
    RegExp('$name="([^"]*)"').firstMatch(attributes)?.group(1);

String _requiredAttribute(String attributes, String name) {
  final value = _attribute(attributes, name);
  if (value == null || value.isEmpty) {
    throw FormatException('Missing $name attribute.');
  }
  return value;
}

String _decodeText(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

Map<String, T> _sortedMap<T>(Map<String, T> source) => <String, T>{
      for (final key in source.keys.toList()..sort()) key: source[key] as T,
    };

String _buildModels(Iterable<String> names) {
  final buffer = StringBuffer(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// Source: Dart Analysis Server API 1.38.0/1.40.1, format 1.\n\n'
    "import 'package:pigcode_ai_protocol_utils/"
    "pigcode_ai_protocol_utils.dart';\n\n"
    "import '../models.dart';\n\n",
  );
  for (final name in names.toList()..sort()) {
    buffer
      ..writeln('/// Validated Analysis Server `$name` value.')
      ..writeln(
        'final class AnalysisServer$name extends AnalysisServerSchemaValue {',
      )
      ..writeln('  factory AnalysisServer$name.fromJson(JsonValue value) {')
      ..writeln('    return AnalysisServer$name._(')
      ..writeln(
        "      AnalysisServerModelRegistry.instance.validateType('$name', value),",
      )
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  AnalysisServer$name._(super.value)')
      ..writeln("      : super(definitionName: '$name');")
      ..writeln('}')
      ..writeln();
  }
  return buffer.toString();
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
