import 'dart:io';

import 'protocol_sources.dart';

final class DartToolingInventory {
  const DartToolingInventory({
    required this.minimum,
    required this.current,
  });

  final DartSdkToolingInventory minimum;
  final DartSdkToolingInventory current;

  Map<String, Object?> toJson() => <String, Object?>{
        'minimum': minimum.toJson(),
        'current': current.toJson(),
      };
}

final class DartSdkToolingInventory {
  const DartSdkToolingInventory({
    required this.sdkRole,
    required this.sdkRelease,
    required this.sdkRevision,
    required this.analysisServer,
    required this.dtd,
    required this.vmService,
  });

  final ProtocolSdkRole sdkRole;
  final String sdkRelease;
  final String sdkRevision;
  final AnalysisServerInventory analysisServer;
  final DtdInventory dtd;
  final VmServiceInventory vmService;

  Map<String, Object?> toJson() => <String, Object?>{
        'sdkRole': sdkRole.name,
        'sdkRelease': sdkRelease,
        'sdkRevision': sdkRevision,
        'analysisServer': analysisServer.toJson(),
        'dtd': dtd.toJson(),
        'vmService': vmService.toJson(),
      };
}

final class AnalysisServerInventory {
  const AnalysisServerInventory({
    required this.apiVersion,
    required this.requestNames,
    required this.notificationNames,
    required this.typeNames,
    required this.enumCount,
    required this.refactoringKinds,
  });

  final String apiVersion;
  final Set<String> requestNames;
  final Set<String> notificationNames;
  final Set<String> typeNames;
  final int enumCount;
  final Set<String> refactoringKinds;

  int get requestCount => requestNames.length;
  int get notificationCount => notificationNames.length;
  int get typeCount => typeNames.length;
  int get refactoringKindCount => refactoringKinds.length;

  Map<String, Object?> toJson() => <String, Object?>{
        'apiVersion': apiVersion,
        'requestCount': requestCount,
        'requests': _sorted(requestNames),
        'notificationCount': notificationCount,
        'notifications': _sorted(notificationNames),
        'typeCount': typeCount,
        'types': _sorted(typeNames),
        'enumCount': enumCount,
        'refactoringKindCount': refactoringKindCount,
        'refactoringKinds': _sorted(refactoringKinds),
      };
}

final class DtdInventory {
  const DtdInventory({
    required this.fixedMethodNames,
    required this.typeNames,
    required this.errorCodes,
    required this.hasDynamicServiceEnvelope,
  });

  final Set<String> fixedMethodNames;
  final Set<String> typeNames;
  final Set<int> errorCodes;
  final bool hasDynamicServiceEnvelope;

  Map<String, Object?> toJson() => <String, Object?>{
        'wireVersion': null,
        'fixedMethods': _sorted(fixedMethodNames),
        'dynamicServiceEnvelope': hasDynamicServiceEnvelope,
        'types': _sorted(typeNames),
        'errorCodes': errorCodes.toList()..sort(),
      };
}

final class VmServiceInventory {
  const VmServiceInventory({
    required this.authorityVersion,
    required this.documentTitleVersion,
    required this.documentedDescriptionVersion,
    required this.rpcNames,
    required this.typeNames,
  });

  final String authorityVersion;
  final String documentTitleVersion;
  final String documentedDescriptionVersion;
  final Set<String> rpcNames;
  final Set<String> typeNames;

  bool get hasDocumentVersionMismatch =>
      authorityVersion != documentedDescriptionVersion;

  Map<String, Object?> toJson() => <String, Object?>{
        'authorityVersion': authorityVersion,
        'documentTitleVersion': documentTitleVersion,
        'documentedDescriptionVersion': documentedDescriptionVersion,
        'documentVersionMismatch': hasDocumentVersionMismatch,
        'rpcCount': rpcNames.length,
        'rpcs': _sorted(rpcNames),
        'typeCount': typeNames.length,
        'types': _sorted(typeNames),
      };
}

DartToolingInventory buildDartToolingInventory(Directory root) {
  final dartSources = loadProtocolSourceLock(root)
      .sources
      .where((source) => source.protocol == 'dart-tooling')
      .toList();
  final minimum = dartSources.singleWhere(
    (source) => source.sdkRole == ProtocolSdkRole.minimum,
  );
  final current = dartSources.singleWhere(
    (source) => source.sdkRole == ProtocolSdkRole.current,
  );
  return DartToolingInventory(
    minimum: _buildSdkInventory(root, minimum),
    current: _buildSdkInventory(root, current),
  );
}

DartSdkToolingInventory _buildSdkInventory(
  Directory root,
  ProtocolSource source,
) {
  final release = source.componentVersions['dartSdk'];
  final role = source.sdkRole;
  if (release == null || role == null || release != source.release) {
    throw FormatException(
      'Invalid Dart SDK source identity for ${source.sourceId}.',
    );
  }
  final base = 'tool/upstream/protocols/dart/$release';
  final analysisSpec = _read(root, '$base/analysis_server/spec_input.html');
  final dtdDocument = _read(root, '$base/dtd/dtd_protocol.md');
  final vmDocument = _read(root, '$base/vm_service/service.md');
  final vmRuntimeHeader = _read(root, '$base/vm_service/service.h');

  final analysisServer = _buildAnalysisServerInventory(analysisSpec);
  if (analysisServer.apiVersion !=
      source.componentVersions['analysisServerApi']) {
    throw FormatException(
      'Analysis Server API version does not match ${source.sourceId}.',
    );
  }
  final vmService = _buildVmServiceInventory(vmDocument, vmRuntimeHeader);
  if (vmService.authorityVersion != source.componentVersions['vmService']) {
    throw FormatException(
      'VM Service authority version does not match ${source.sourceId}.',
    );
  }

  return DartSdkToolingInventory(
    sdkRole: role,
    sdkRelease: release,
    sdkRevision: source.revision,
    analysisServer: analysisServer,
    dtd: _buildDtdInventory(dtdDocument),
    vmService: vmService,
  );
}

AnalysisServerInventory _buildAnalysisServerInventory(String document) {
  final version = _firstGroup(
    RegExp(r'<version>\s*([^<]+)\s*</version>'),
    document,
    'Analysis Server API version',
  );
  final requestNames = <String>{};
  final notificationNames = <String>{};
  final domains = RegExp(
    r'<domain name="([^"]+)"[^>]*>([\s\S]*?)</domain>',
  ).allMatches(document);
  for (final domain in domains) {
    final domainName = domain.group(1)!;
    final body = domain.group(2)!;
    for (final request
        in RegExp(r'<request method="([^"]+)"').allMatches(body)) {
      requestNames.add('$domainName.${request.group(1)!}');
    }
    for (final notification
        in RegExp(r'<notification event="([^"]+)"').allMatches(body)) {
      notificationNames.add('$domainName.${notification.group(1)!}');
    }
  }
  final typeNames = RegExp(
    r'<type name="([^"]+)"',
  ).allMatches(document).map((match) => match.group(1)!).toSet();
  final enumCount = RegExp(r'<enum(?:\s|>)').allMatches(document).length;
  final refactoringKinds = RegExp(
    r'<refactoring kind="([^"]+)"',
  ).allMatches(document).map((match) => match.group(1)!).toSet();
  return AnalysisServerInventory(
    apiVersion: version,
    requestNames: Set<String>.unmodifiable(requestNames),
    notificationNames: Set<String>.unmodifiable(notificationNames),
    typeNames: Set<String>.unmodifiable(typeNames),
    enumCount: enumCount,
    refactoringKinds: Set<String>.unmodifiable(refactoringKinds),
  );
}

DtdInventory _buildDtdInventory(String document) {
  const fixedMethods = <String>{
    'streamListen',
    'streamCancel',
    'postEvent',
    'registerService',
    'streamNotify',
    'FileSystem.readFileAsString',
    'FileSystem.writeFileAsString',
    'FileSystem.listDirectoryContents',
    'FileSystem.setIDEWorkspaceRoots',
    'FileSystem.getIDEWorkspaceRoots',
    'FileSystem.getProjectRoots',
  };
  const types = <String>{'UriList', 'FileContent', 'IDEWorkspaceRoots'};
  const documentTokens = <String, String>{
    'streamListen': '#### `streamListen`',
    'streamCancel': '#### `streamCancel`',
    'postEvent': '#### `postEvent`',
    'registerService': '#### `registerService`',
    'streamNotify': '##### `streamNotify`',
    'FileSystem.readFileAsString': '### readFileAsString',
    'FileSystem.writeFileAsString': '### writeFileAsString',
    'FileSystem.listDirectoryContents': '### listDirectoryContents',
    'FileSystem.setIDEWorkspaceRoots': '#### setIDEWorkspaceRoots',
    'FileSystem.getIDEWorkspaceRoots': '#### getIDEWorkspaceRoots',
    'FileSystem.getProjectRoots': '#### getProjectRoots',
  };
  for (final entry in documentTokens.entries) {
    if (!document.contains(entry.value)) {
      throw FormatException('DTD method is missing: ${entry.key}.');
    }
  }
  for (final type in types) {
    if (!document.contains('#### `$type`')) {
      throw FormatException('DTD type is missing: $type.');
    }
  }
  final errorCodes = RegExp(
    r'^(-?\d+) \|',
    multiLine: true,
  ).allMatches(document).map((match) => int.parse(match.group(1)!)).toSet();
  return DtdInventory(
    fixedMethodNames: fixedMethods,
    typeNames: types,
    errorCodes: Set<int>.unmodifiable(errorCodes),
    hasDynamicServiceEnvelope: document.contains('#### `service`.`method`') &&
        document.contains('##### `service.method`'),
  );
}

VmServiceInventory _buildVmServiceInventory(
  String document,
  String runtimeHeader,
) {
  final major = _firstGroup(
    RegExp(r'SERVICE_PROTOCOL_MAJOR_VERSION\s+(\d+)'),
    runtimeHeader,
    'VM Service runtime major',
  );
  final minor = _firstGroup(
    RegExp(r'SERVICE_PROTOCOL_MINOR_VERSION\s+(\d+)'),
    runtimeHeader,
    'VM Service runtime minor',
  );
  final titleVersion = _firstGroup(
    RegExp(r'^# Dart VM Service Protocol ([0-9.]+)$', multiLine: true),
    document,
    'VM Service document title version',
  );
  final descriptionVersion = _firstGroup(
    RegExp(r'describes of _version ([0-9.]+)_'),
    document,
    'VM Service document description version',
  );
  final authorityVersion = '$major.$minor';
  if (titleVersion != authorityVersion) {
    throw const FormatException(
      'VM Service title and runtime authority versions differ.',
    );
  }
  final rpcSection = _section(document, 'Public RPCs', 'Public Types');
  final typeSection = _section(document, 'Public Types', 'Revision History');
  return VmServiceInventory(
    authorityVersion: authorityVersion,
    documentTitleVersion: titleVersion,
    documentedDescriptionVersion: descriptionVersion,
    rpcNames: Set<String>.unmodifiable(_levelThreeHeadings(rpcSection)),
    typeNames: Set<String>.unmodifiable(_levelThreeHeadings(typeSection)),
  );
}

Set<String> _levelThreeHeadings(String section) => RegExp(
      r'^### ([A-Za-z][A-Za-z0-9]*)\s*$',
      multiLine: true,
    ).allMatches(section).map((match) => match.group(1)!).toSet();

String _section(String document, String start, String end) {
  final startMarker = '## $start';
  final endMarker = '## $end';
  final startIndex = document.indexOf(startMarker);
  final endIndex = document.indexOf(endMarker, startIndex + startMarker.length);
  if (startIndex < 0 || endIndex < 0) {
    throw FormatException('Missing Markdown section $start..$end.');
  }
  return document.substring(startIndex + startMarker.length, endIndex);
}

String _firstGroup(RegExp pattern, String source, String label) {
  final value = pattern.firstMatch(source)?.group(1);
  if (value == null || value.isEmpty) {
    throw FormatException('Missing $label.');
  }
  return value;
}

String _read(Directory root, String relativePath) =>
    File.fromUri(root.absolute.uri.resolve(relativePath)).readAsStringSync();

List<String> _sorted(Iterable<String> values) => values.toList()..sort();
