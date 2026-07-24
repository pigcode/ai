import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'protocol_sources.dart';

final class DtdGeneratedArtifacts {
  const DtdGeneratedArtifacts({required this.inventoryDart});

  final String inventoryDart;
}

DtdGeneratedArtifacts buildDtdGeneratedArtifacts(Directory root) {
  final inventoryFile = File.fromUri(
    root.absolute.uri.resolve(
      'tool/upstream/protocols/dart/dtd-method-inventory.json',
    ),
  );
  final inventoryBytes = inventoryFile.readAsBytesSync();
  final inventory =
      jsonDecode(utf8.decode(inventoryBytes)) as Map<String, Object?>;
  _validateManualInventory(inventory);

  final dartSources = loadProtocolSourceLock(root)
      .sources
      .where((source) => source.protocol == 'dart-tooling')
      .toList(growable: false);
  final sourceEvidence = <Map<String, Object?>>[];
  for (final source in dartSources) {
    final artifact = source.artifacts.singleWhere(
      (artifact) => artifact.artifactId.endsWith('-dtd-protocol'),
    );
    final document = File.fromUri(
      root.absolute.uri.resolve(artifact.path),
    ).readAsStringSync();
    _validateDocument(inventory, document, release: source.release);
    sourceEvidence.add(<String, Object?>{
      'sdkRole': source.sdkRole!.name,
      'sdkRelease': source.release,
      'sdkRevision': source.revision,
      'dtdPackage': source.componentVersions['dtdPackage'],
      'packageRevision': source.componentRevisions['devtools'],
      'documentSha256': artifact.sha256,
    });
  }
  sourceEvidence.sort(
    (left, right) =>
        (left['sdkRole']! as String).compareTo(right['sdkRole']! as String),
  );

  final generated = <String, Object?>{
    'formatVersion': inventory['formatVersion'],
    'inventoryRevision': inventory['inventoryRevision'],
    'inventorySha256': sha256.convert(inventoryBytes).toString(),
    'sources': sourceEvidence,
    'methods': inventory['methods'],
    'types': inventory['types'],
    'errorCodes': inventory['errorCodes'],
    'dynamicService': inventory['dynamicService'],
  };
  final encoded = jsonEncode(generated);
  final revision = inventory['inventoryRevision']! as String;
  final digest = sha256.convert(inventoryBytes).toString();
  final minimum = sourceEvidence.singleWhere(
    (source) => source['sdkRole'] == 'minimum',
  );
  final current = sourceEvidence.singleWhere(
    (source) => source['sdkRole'] == 'current',
  );
  return DtdGeneratedArtifacts(
    inventoryDart: """
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: pinned DTD documents plus dtd-method-inventory.json.

const dtdGeneratedInventoryRevision = '$revision';
const dtdGeneratedInventorySha256 = '$digest';
const dtdGeneratedMinimumSdkRelease = '${minimum['sdkRelease']}';
const dtdGeneratedMinimumSdkRevision = '${minimum['sdkRevision']}';
const dtdGeneratedMinimumPackageRevision = '${minimum['packageRevision']}';
const dtdGeneratedMinimumDocumentSha256 = '${minimum['documentSha256']}';
const dtdGeneratedCurrentSdkRelease = '${current['sdkRelease']}';
const dtdGeneratedCurrentSdkRevision = '${current['sdkRevision']}';
const dtdGeneratedCurrentPackageRevision = '${current['packageRevision']}';
const dtdGeneratedCurrentDocumentSha256 = '${current['documentSha256']}';
const dtdGeneratedInventoryJson = r'''$encoded''';
""",
  );
}

void _validateManualInventory(Map<String, Object?> inventory) {
  if (inventory['formatVersion'] != 1 ||
      inventory['inventoryRevision'] != 'dtd-fixed-inventory-v1') {
    throw const FormatException('Unsupported DTD inventory identity.');
  }
  final methods = _object(inventory['methods'], 'methods');
  final types = _object(inventory['types'], 'types');
  final errors = inventory['errorCodes'];
  final dynamic = _object(inventory['dynamicService'], 'dynamicService');
  final dynamicTokens = inventory['classifiedDynamicDocumentationTokens'];
  final documentDifferences = _object(
    inventory['classifiedDocumentDifferences'],
    'classifiedDocumentDifferences',
  );
  if (methods.length != 11 ||
      types.length != 4 ||
      errors is! List<Object?> ||
      errors.length != 11 ||
      errors.any((code) => code is! int) ||
      dynamic['methodPattern'] != r'^[^.]+\..+$' ||
      dynamic['paramsType'] != 'object' ||
      dynamic['resultType'] != 'json' ||
      dynamicTokens is! List<Object?> ||
      dynamicTokens.length != 2 ||
      dynamicTokens.any((token) => token is! String) ||
      documentDifferences.keys.toSet().difference(
        const <String>{'3.6.0', '3.12.2'},
      ).isNotEmpty ||
      documentDifferences.length != 2) {
    throw const FormatException('DTD fixed inventory is incomplete.');
  }
  for (final entry in methods.entries) {
    final descriptor = _object(entry.value, 'method ${entry.key}');
    if (descriptor['kind'] != 'request' &&
        descriptor['kind'] != 'notification') {
      throw FormatException('DTD method kind is invalid: ${entry.key}.');
    }
    if (descriptor['documentationToken'] is! String ||
        descriptor['params'] is! Map<String, Object?> ||
        descriptor['kind'] == 'request' &&
            descriptor['resultType'] is! String ||
        descriptor['kind'] == 'notification' &&
            descriptor['resultType'] != null) {
      throw FormatException('DTD method descriptor is invalid: ${entry.key}.');
    }
  }
}

void _validateDocument(
  Map<String, Object?> inventory,
  String document, {
  required String release,
}) {
  final methods = _object(inventory['methods'], 'methods');
  for (final entry in methods.entries) {
    final descriptor = _object(entry.value, 'method ${entry.key}');
    final token = descriptor['documentationToken']! as String;
    if (!document.contains(token)) {
      throw FormatException(
        'DTD $release document is missing method ${entry.key}.',
      );
    }
  }
  for (final token
      in (inventory['classifiedDynamicDocumentationTokens']! as List<Object?>)
          .cast<String>()) {
    if (!document.contains(token)) {
      throw FormatException(
        'DTD $release document is missing dynamic token $token.',
      );
    }
  }
  for (final type in const <String>[
    'UriList',
    'FileContent',
    'IDEWorkspaceRoots',
  ]) {
    if (!document.contains('#### `$type`')) {
      throw FormatException('DTD $release document is missing type $type.');
    }
  }
  final expectedSuccessToken =
      release == '3.6.0' ? '\n Success Responses\n' : '### Success Responses';
  if (!document.contains(expectedSuccessToken)) {
    throw FormatException('DTD $release document is missing Success.');
  }
  final documentedErrors = RegExp(
    r'^(-?\d+) \|',
    multiLine: true,
  ).allMatches(document).map((match) => int.parse(match.group(1)!)).toSet();
  final inventoriedErrors =
      (inventory['errorCodes']! as List<Object?>).cast<int>().toSet();
  if (documentedErrors.length != inventoriedErrors.length ||
      !documentedErrors.containsAll(inventoriedErrors)) {
    throw FormatException(
      'DTD $release document has an unclassified error-code diff.',
    );
  }

  final documentedFixed = <String>{
    for (final entry in methods.entries)
      if (document.contains(
        _object(entry.value, 'method ${entry.key}')['documentationToken']!
            as String,
      ))
        entry.key,
  };
  if (documentedFixed.length != methods.length) {
    throw FormatException(
      'DTD $release document has an unclassified fixed-method diff.',
    );
  }
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('DTD inventory $label must be an object.');
  }
  return value;
}
