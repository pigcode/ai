import 'dart:convert';
import 'dart:io';

import 'protocol_sources.dart';

final class VmServiceGeneratedArtifacts {
  const VmServiceGeneratedArtifacts({
    required this.inventoryDart,
    required this.modelsDart,
  });

  final String inventoryDart;
  final String modelsDart;
}

VmServiceGeneratedArtifacts buildVmServiceGeneratedArtifacts(Directory root) {
  final sources = loadProtocolSourceLock(root)
      .sources
      .where((source) => source.protocol == 'dart-tooling')
      .toList(growable: false);
  final minimum = _parseSnapshot(
    root,
    sources.singleWhere(
      (source) => source.sdkRole == ProtocolSdkRole.minimum,
    ),
  );
  final current = _parseSnapshot(
    root,
    sources.singleWhere(
      (source) => source.sdkRole == ProtocolSdkRole.current,
    ),
  );
  _validateOfficialGenerated(minimum);
  _validateOfficialGenerated(current);

  final currentOnlyRpcs = current.rpcNames.difference(minimum.rpcNames);
  final minimumOnlyRpcs = minimum.rpcNames.difference(current.rpcNames);
  final currentOnlyTypes = current.typeNames.difference(minimum.typeNames);
  final minimumOnlyTypes = minimum.typeNames.difference(current.typeNames);
  final currentOnlyEvents = current.eventKinds.difference(minimum.eventKinds);
  final minimumOnlyEvents = minimum.eventKinds.difference(current.eventKinds);
  if (currentOnlyRpcs.toString() != '{getQueuedMicrotasks}' ||
      minimumOnlyRpcs.isNotEmpty ||
      currentOnlyTypes.length != 2 ||
      !currentOnlyTypes.containsAll(
        const <String>{'Microtask', 'QueuedMicrotasks'},
      ) ||
      minimumOnlyTypes.isNotEmpty ||
      currentOnlyEvents.toString() != '{TimerSignificantlyOverdue}' ||
      minimumOnlyEvents.isNotEmpty) {
    throw StateError(
      'Unclassified VM Service diff: current RPCs=$currentOnlyRpcs, '
      'minimum RPCs=$minimumOnlyRpcs, current types=$currentOnlyTypes, '
      'minimum types=$minimumOnlyTypes, current events=$currentOnlyEvents, '
      'minimum events=$minimumOnlyEvents.',
    );
  }
  if (minimum.titleVersion != '4.16' ||
      minimum.descriptionVersion != '4.16' ||
      minimum.runtimeVersion != '4.16' ||
      current.titleVersion != '4.21' ||
      current.descriptionVersion != '4.20' ||
      current.runtimeVersion != '4.21') {
    throw StateError('VM Service version oracle or classified prose drift.');
  }

  final unionRpcs = <String>{...minimum.rpcNames, ...current.rpcNames};
  final unionTypes = <String>{...minimum.typeNames, ...current.typeNames};
  final unionEvents = <String>{...minimum.eventKinds, ...current.eventKinds};
  final inventory = <String, Object?>{
    'formatVersion': 1,
    'minimum': minimum.toJson(),
    'current': current.toJson(),
    'rpcs': <String, Object?>{
      for (final name in unionRpcs.toList()..sort())
        name: <String, Object?>{
          'introduced': currentOnlyRpcs.contains(name) ? '4.21' : '4.16',
          'minimum': minimum.rpcNames.contains(name),
          'current': current.rpcNames.contains(name),
          'resultTypes':
              (current.rpcResultTypes[name] ?? minimum.rpcResultTypes[name])!
                  .toList()
                ..sort(),
        },
    },
    'types': <String, Object?>{
      for (final name in unionTypes.toList()..sort())
        name: <String, Object?>{
          'introduced': currentOnlyTypes.contains(name) ? '4.21' : '4.16',
          'minimum': minimum.typeNames.contains(name),
          'current': current.typeNames.contains(name),
        },
    },
    'eventKinds': <String, Object?>{
      for (final name in unionEvents.toList()..sort())
        name: <String, Object?>{
          'introduced': currentOnlyEvents.contains(name) ? '4.21' : '4.16',
          'minimum': minimum.eventKinds.contains(name),
          'current': current.eventKinds.contains(name),
        },
    },
    'currentOnlyRpcs': currentOnlyRpcs.toList()..sort(),
    'currentOnlyTypes': currentOnlyTypes.toList()..sort(),
    'unclassifiedDifferences': const <Object?>[],
  };
  return VmServiceGeneratedArtifacts(
    inventoryDart: _buildInventoryDart(inventory, minimum, current),
    modelsDart: _buildModelsDart(unionTypes),
  );
}

String _buildInventoryDart(
  Map<String, Object?> inventory,
  _VmSnapshot minimum,
  _VmSnapshot current,
) =>
    """
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Sources: pinned service.md, vm_service.dart, and service.h artifacts.

const vmServiceGeneratedMinimumRelease = '${minimum.release}';
const vmServiceGeneratedMinimumRevision = '${minimum.revision}';
const vmServiceGeneratedMinimumDocumentSha256 = '${minimum.documentSha256}';
const vmServiceGeneratedMinimumApiSha256 = '${minimum.generatedSha256}';
const vmServiceGeneratedMinimumOracleSha256 = '${minimum.oracleSha256}';
const vmServiceGeneratedCurrentRelease = '${current.release}';
const vmServiceGeneratedCurrentRevision = '${current.revision}';
const vmServiceGeneratedCurrentDocumentSha256 = '${current.documentSha256}';
const vmServiceGeneratedCurrentApiSha256 = '${current.generatedSha256}';
const vmServiceGeneratedCurrentOracleSha256 = '${current.oracleSha256}';
const vmServiceGeneratedInventoryJson = r'''${jsonEncode(inventory)}''';
""";

String _buildModelsDart(Set<String> types) {
  final buffer = StringBuffer(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// VM Service public type union wrappers.\n\n'
    "import '../models.dart';\n\n",
  );
  for (final type in types.toList()..sort()) {
    final className = 'VmService${_identifier(type)}Value';
    buffer
      ..writeln('final class $className extends VmServiceSchemaValue {')
      ..writeln('  $className._(super.value)')
      ..writeln("      : super(definitionName: '$type');")
      ..writeln()
      ..writeln('  factory $className.fromJson(')
      ..writeln('    Map<String, Object?> value,')
      ..writeln('  ) =>')
      ..writeln('      $className._(')
      ..writeln('        VmServiceModelRegistry.instance.validateType(')
      ..writeln("          '$type',")
      ..writeln('          value,')
      ..writeln('        ),')
      ..writeln('      );')
      ..writeln('}')
      ..writeln();
  }
  return buffer.toString();
}

_VmSnapshot _parseSnapshot(Directory root, ProtocolSource source) {
  ProtocolArtifact artifact(String suffix) => source.artifacts.singleWhere(
        (artifact) => artifact.artifactId.endsWith(suffix),
      );
  final documentArtifact = artifact('-vm-service');
  final generatedArtifact = artifact('-vm-generated');
  final oracleArtifact = artifact('-runtime-version');
  final document = File.fromUri(
    root.absolute.uri.resolve(documentArtifact.path),
  ).readAsStringSync();
  final generated = File.fromUri(
    root.absolute.uri.resolve(generatedArtifact.path),
  ).readAsStringSync();
  final oracle = File.fromUri(
    root.absolute.uri.resolve(oracleArtifact.path),
  ).readAsStringSync();
  final runtimeVersion =
      '${_group(RegExp(r'SERVICE_PROTOCOL_MAJOR_VERSION\s+(\d+)'), oracle)}.'
      '${_group(RegExp(r'SERVICE_PROTOCOL_MINOR_VERSION\s+(\d+)'), oracle)}';
  final titleVersion = _group(
    RegExp(
      r'^# Dart VM Service Protocol ([0-9.]+)$',
      multiLine: true,
    ),
    document,
  );
  final descriptionVersion = _group(
    RegExp(r'describes of _version ([0-9.]+)_'),
    document,
  );
  if (runtimeVersion != source.componentVersions['vmService'] ||
      titleVersion != runtimeVersion) {
    throw StateError('VM Service source lock and runtime oracle disagree.');
  }
  final rpcSection = _section(document, 'Public RPCs', 'Public Types');
  final typeSection = _section(document, 'Public Types', 'Revision History');
  final rpcNames = _headings(rpcSection);
  final rpcResultTypes = <String, Set<String>>{
    for (final rpc in rpcNames) rpc: _parseRpcResultTypes(rpcSection, rpc),
  };
  final typeNames = _headings(typeSection);
  final eventKindSection = _subsection(typeSection, 'EventKind');
  final eventKinds = RegExp(
    r'^  ([A-Z][A-Za-z0-9]*),$',
    multiLine: true,
  ).allMatches(eventKindSection).map((match) => match.group(1)!).toSet();
  return _VmSnapshot(
    release: source.release,
    revision: source.revision,
    runtimeVersion: runtimeVersion,
    titleVersion: titleVersion,
    descriptionVersion: descriptionVersion,
    documentSha256: documentArtifact.sha256,
    generatedSha256: generatedArtifact.sha256,
    oracleSha256: oracleArtifact.sha256,
    rpcNames: Set<String>.unmodifiable(rpcNames),
    rpcResultTypes: Map<String, Set<String>>.unmodifiable(rpcResultTypes),
    typeNames: Set<String>.unmodifiable(typeNames),
    eventKinds: Set<String>.unmodifiable(eventKinds),
    generatedSource: generated,
  );
}

void _validateOfficialGenerated(_VmSnapshot snapshot) {
  for (final rpc in snapshot.rpcNames) {
    if (!RegExp('\\b${RegExp.escape(rpc)}\\s*\\(')
        .hasMatch(snapshot.generatedSource)) {
      throw StateError(
        'VM Service ${snapshot.release} generated API is missing RPC $rpc.',
      );
    }
  }
  for (final type in snapshot.typeNames) {
    final generatedName = switch (type) {
      'Function' => 'Func',
      'Null' => 'NullVal',
      'Object' => 'Obj',
      _ => type,
    };
    if (!RegExp(
      '(?:class|abstract class|enum)\\s+${RegExp.escape(generatedName)}\\b',
    ).hasMatch(snapshot.generatedSource)) {
      throw StateError(
        'VM Service ${snapshot.release} generated API is missing type $type.',
      );
    }
  }
}

final class _VmSnapshot {
  const _VmSnapshot({
    required this.release,
    required this.revision,
    required this.runtimeVersion,
    required this.titleVersion,
    required this.descriptionVersion,
    required this.documentSha256,
    required this.generatedSha256,
    required this.oracleSha256,
    required this.rpcNames,
    required this.rpcResultTypes,
    required this.typeNames,
    required this.eventKinds,
    required this.generatedSource,
  });

  final String release;
  final String revision;
  final String runtimeVersion;
  final String titleVersion;
  final String descriptionVersion;
  final String documentSha256;
  final String generatedSha256;
  final String oracleSha256;
  final Set<String> rpcNames;
  final Map<String, Set<String>> rpcResultTypes;
  final Set<String> typeNames;
  final Set<String> eventKinds;
  final String generatedSource;

  Map<String, Object?> toJson() => <String, Object?>{
        'release': release,
        'revision': revision,
        'runtimeVersion': runtimeVersion,
        'titleVersion': titleVersion,
        'descriptionVersion': descriptionVersion,
        'documentSha256': documentSha256,
        'generatedSha256': generatedSha256,
        'oracleSha256': oracleSha256,
        'rpcNames': rpcNames.toList()..sort(),
        'rpcResultTypes': <String, Object?>{
          for (final entry in rpcResultTypes.entries)
            entry.key: entry.value.toList()..sort(),
        },
        'typeNames': typeNames.toList()..sort(),
        'eventKinds': eventKinds.toList()..sort(),
      };
}

Set<String> _headings(String section) => RegExp(
      r'^### ([A-Za-z][A-Za-z0-9]*)\s*$',
      multiLine: true,
    ).allMatches(section).map((match) => match.group(1)!).toSet();

String _section(String document, String start, String end) {
  final startIndex = document.indexOf('## $start');
  final endIndex = document.indexOf('## $end', startIndex + start.length);
  if (startIndex < 0 || endIndex < 0) {
    throw FormatException('VM Service section $start..$end is missing.');
  }
  return document.substring(startIndex, endIndex);
}

String _subsection(String section, String name) {
  final start = section.indexOf('### $name');
  final end = section.indexOf('\n### ', start + name.length + 4);
  if (start < 0) {
    throw FormatException('VM Service subsection $name is missing.');
  }
  return section.substring(start, end < 0 ? section.length : end);
}

Set<String> _parseRpcResultTypes(String rpcSection, String method) {
  final section = _subsection(rpcSection, method);
  final match = RegExp(
    '^([@A-Za-z][@A-Za-z0-9|]*)\\s+${RegExp.escape(method)}\\s*\\(',
    multiLine: true,
  ).firstMatch(section);
  if (match == null) {
    throw FormatException('VM Service RPC signature is missing: $method.');
  }
  return Set<String>.unmodifiable(
    match
        .group(1)!
        .split('|')
        .map((type) => type.startsWith('@') ? type.substring(1) : type),
  );
}

String _group(RegExp pattern, String source) {
  final value = pattern.firstMatch(source)?.group(1);
  if (value == null) {
    throw const FormatException('VM Service version marker is missing.');
  }
  return value;
}

String _identifier(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
