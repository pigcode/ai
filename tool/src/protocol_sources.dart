import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const protocolSourceLockPath = 'tool/upstream/protocols/sources.json';

final class ProtocolSourceViolation {
  const ProtocolSourceViolation(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

enum ProtocolArtifactRole {
  primary,
  schema,
  specification,
  generatedComparison,
  runtimeOracle,
  license,
  peerManifest,
}

enum ProtocolSdkRole {
  minimum,
  current,
}

final class ProtocolArtifact {
  const ProtocolArtifact({
    required this.artifactId,
    required this.path,
    required this.size,
    required this.sha256,
    required this.role,
  });

  final String artifactId;
  final String path;
  final int size;
  final String sha256;
  final ProtocolArtifactRole? role;
}

final class ProtocolSource {
  const ProtocolSource({
    required this.sourceId,
    required this.protocol,
    required this.repository,
    required this.release,
    required this.revision,
    required this.releaseDate,
    required this.wireVersion,
    required this.schemaDialect,
    required this.sdkRole,
    required this.componentVersions,
    required this.componentRevisions,
    required this.entryRefs,
    required this.artifacts,
  });

  final String sourceId;
  final String protocol;
  final String repository;
  final String release;
  final String revision;
  final String releaseDate;
  final String? wireVersion;
  final String? schemaDialect;
  final ProtocolSdkRole? sdkRole;
  final Map<String, String> componentVersions;
  final Map<String, String> componentRevisions;
  final List<String> entryRefs;
  final List<ProtocolArtifact> artifacts;
}

final class ProtocolSourceLock {
  const ProtocolSourceLock({
    required this.formatVersion,
    required this.generatorIdentity,
    required this.generatorFormatVersion,
    required this.peerManifest,
    required this.sources,
  });

  final int formatVersion;
  final String generatorIdentity;
  final int generatorFormatVersion;
  final ProtocolArtifact? peerManifest;
  final List<ProtocolSource> sources;
}

ProtocolSourceLock loadProtocolSourceLock(
  Directory root, {
  File? sourceLockOverride,
}) {
  final lockFile =
      sourceLockOverride ?? _containedFile(root, protocolSourceLockPath);
  return parseProtocolSourceLock(lockFile.readAsStringSync());
}

ProtocolSourceLock parseProtocolSourceLock(String contents) {
  final document = jsonDecode(contents);
  final object = _expectObject(document, 'source lock');
  final formatVersion = _expectInt(
    object['formatVersion'],
    'formatVersion',
  );
  _expectAllowedAndRequiredKeys(
    object,
    allowed: const <String>{
      'formatVersion',
      'generator',
      'peerManifest',
      'sources',
    },
    required: <String>{
      'formatVersion',
      'generator',
      'sources',
      if (formatVersion >= 2) 'peerManifest',
    },
    location: 'source lock',
  );
  final generator = _expectObject(object['generator'], 'generator');
  _expectKeys(
    generator,
    const <String>{'identity', 'formatVersion'},
    'generator',
  );
  final sources = _expectList(object['sources'], 'sources');

  return ProtocolSourceLock(
    formatVersion: formatVersion,
    generatorIdentity: _expectString(
      generator['identity'],
      'generator.identity',
    ),
    generatorFormatVersion: _expectInt(
      generator['formatVersion'],
      'generator.formatVersion',
    ),
    peerManifest: switch (object['peerManifest']) {
      null => null,
      final Object value => _parseArtifact(value, -1, 0),
    },
    sources: <ProtocolSource>[
      for (var index = 0; index < sources.length; index += 1)
        _parseSource(sources[index], index),
    ],
  );
}

List<ProtocolSourceViolation> validateProtocolSources(
  Directory root, {
  Map<String, File> artifactOverrides = const <String, File>{},
  File? sourceLockOverride,
}) {
  final violations = <ProtocolSourceViolation>[];
  late final ProtocolSourceLock sourceLock;
  try {
    sourceLock = loadProtocolSourceLock(
      root,
      sourceLockOverride: sourceLockOverride,
    );
  } on _ProtocolSourceFormatException catch (error) {
    return <ProtocolSourceViolation>[
      ProtocolSourceViolation(error.code, error.message),
    ];
  } on Object catch (error) {
    return <ProtocolSourceViolation>[
      ProtocolSourceViolation('invalid_source_lock', error.toString()),
    ];
  }

  if (sourceLock.formatVersion != 1 && sourceLock.formatVersion != 2) {
    violations.add(
      const ProtocolSourceViolation(
        'unsupported_source_lock_version',
        'Protocol source-lock formatVersion must be 1 or 2.',
      ),
    );
  }
  if (sourceLock.generatorIdentity != 'pigcode-protocol-codegen' ||
      sourceLock.generatorFormatVersion != 1) {
    violations.add(
      const ProtocolSourceViolation(
        'unsupported_generator_identity',
        'Expected pigcode-protocol-codegen format version 1.',
      ),
    );
  }

  final sourceIds = <String>{};
  final artifactIds = <String>{};
  final sdkRoles = <ProtocolSdkRole>{};
  final artifacts = <ProtocolArtifact>[
    if (sourceLock.peerManifest case final ProtocolArtifact artifact) artifact,
  ];
  for (final source in sourceLock.sources) {
    if (!sourceIds.add(source.sourceId)) {
      violations.add(
        ProtocolSourceViolation(
          'duplicate_source_id',
          'Duplicate protocol source ID: ${source.sourceId}',
        ),
      );
    }
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(source.revision)) {
      violations.add(
        ProtocolSourceViolation(
          'invalid_source_revision',
          'Source ${source.sourceId} does not use a full Git commit.',
        ),
      );
    }
    if (!_supportedSchemaDialects.contains(source.schemaDialect)) {
      violations.add(
        ProtocolSourceViolation(
          'unsupported_schema_dialect',
          'Source ${source.sourceId} uses unsupported schema dialect '
              '${source.schemaDialect}.',
        ),
      );
    }
    if (source.protocol == 'dart-tooling') {
      final sdkRole = source.sdkRole;
      if (sdkRole == null) {
        violations.add(
          ProtocolSourceViolation(
            'missing_sdk_role',
            'Dart tooling source ${source.sourceId} has no SDK role.',
          ),
        );
      } else if (!sdkRoles.add(sdkRole)) {
        violations.add(
          ProtocolSourceViolation(
            'duplicate_sdk_role',
            'Dart tooling SDK role ${sdkRole.name} is duplicated.',
          ),
        );
      }
      if (!_dartComponentKeys.every(source.componentVersions.containsKey)) {
        violations.add(
          ProtocolSourceViolation(
            'missing_component_version',
            'Dart tooling source ${source.sourceId} is missing a component '
                'version.',
          ),
        );
      }
    } else if (source.sdkRole != null ||
        source.componentVersions.isNotEmpty ||
        source.componentRevisions.isNotEmpty) {
      violations.add(
        ProtocolSourceViolation(
          'unexpected_sdk_metadata',
          'Non-Dart source ${source.sourceId} declares Dart SDK metadata.',
        ),
      );
    }
    artifacts.addAll(source.artifacts);
  }

  if (sourceLock.formatVersion >= 2 && sourceLock.peerManifest == null) {
    violations.add(
      const ProtocolSourceViolation(
        'missing_peer_manifest',
        'Protocol source-lock format 2 requires a peer manifest.',
      ),
    );
  }

  for (final artifact in artifacts) {
    if (!artifactIds.add(artifact.artifactId)) {
      violations.add(
        ProtocolSourceViolation(
          'duplicate_artifact_id',
          'Duplicate protocol artifact ID: ${artifact.artifactId}',
        ),
      );
    }
    if (!_isCanonicalRelativePath(artifact.path)) {
      violations.add(
        ProtocolSourceViolation(
          'invalid_artifact_path',
          'Artifact ${artifact.artifactId} has a non-canonical path.',
        ),
      );
      continue;
    }
    final file = artifactOverrides[artifact.artifactId] ??
        _containedFile(root, artifact.path);
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      violations.add(
        ProtocolSourceViolation(
          'missing_artifact',
          'Artifact ${artifact.artifactId} is missing or not a regular file.',
        ),
      );
      continue;
    }
    if (artifactOverrides[artifact.artifactId] == null &&
        !_isContainedExistingFile(root, file)) {
      violations.add(
        ProtocolSourceViolation(
          'artifact_path_escape',
          'Artifact ${artifact.artifactId} resolves outside the workspace.',
        ),
      );
      continue;
    }
    final bytes = file.readAsBytesSync();
    if (bytes.length != artifact.size) {
      violations.add(
        ProtocolSourceViolation(
          'artifact_size_mismatch',
          'Artifact ${artifact.artifactId} expected ${artifact.size} bytes '
              'but found ${bytes.length}.',
        ),
      );
    }
    final actualHash = sha256.convert(bytes).toString();
    if (actualHash != artifact.sha256) {
      violations.add(
        ProtocolSourceViolation(
          'artifact_hash_mismatch',
          'Artifact ${artifact.artifactId} expected ${artifact.sha256} '
              'but found $actualHash.',
        ),
      );
    }
    if (artifact.role == ProtocolArtifactRole.peerManifest) {
      _validatePeerManifest(file, violations);
    }
  }

  final unknownOverrides = artifactOverrides.keys.toSet()
    ..removeAll(artifactIds);
  for (final artifactId in unknownOverrides) {
    violations.add(
      ProtocolSourceViolation(
        'unknown_artifact_override',
        'No source-lock artifact has ID $artifactId.',
      ),
    );
  }
  return violations;
}

ProtocolSource _parseSource(Object? value, int index) {
  final location = 'sources[$index]';
  final object = _expectObject(value, location);
  _expectAllowedAndRequiredKeys(
    object,
    allowed: const <String>{
      'sourceId',
      'protocol',
      'repository',
      'release',
      'revision',
      'releaseDate',
      'wireVersion',
      'schemaDialect',
      'sdkRole',
      'componentVersions',
      'componentRevisions',
      'entryRefs',
      'artifacts',
    },
    required: const <String>{
      'sourceId',
      'protocol',
      'repository',
      'release',
      'revision',
      'releaseDate',
      'wireVersion',
      'schemaDialect',
      'entryRefs',
      'artifacts',
    },
    location: location,
  );
  final refs = _expectList(object['entryRefs'], '$location.entryRefs');
  final artifacts = _expectList(object['artifacts'], '$location.artifacts');
  return ProtocolSource(
    sourceId: _expectString(object['sourceId'], '$location.sourceId'),
    protocol: _expectString(object['protocol'], '$location.protocol'),
    repository: _expectString(object['repository'], '$location.repository'),
    release: _expectString(object['release'], '$location.release'),
    revision: _expectString(object['revision'], '$location.revision'),
    releaseDate: _expectString(object['releaseDate'], '$location.releaseDate'),
    wireVersion: _optionalString(
      object['wireVersion'],
      '$location.wireVersion',
    ),
    schemaDialect: switch (object['schemaDialect']) {
      null => null,
      final String value => value,
      _ => throw FormatException(
          '$location.schemaDialect must be a string or null.',
        ),
    },
    sdkRole: switch (object['sdkRole']) {
      null => null,
      'minimum' => ProtocolSdkRole.minimum,
      'current' => ProtocolSdkRole.current,
      final Object? value => throw _ProtocolSourceFormatException(
          'invalid_sdk_role',
          '$location.sdkRole must be minimum, current, or absent; '
              'found $value.',
        ),
    },
    componentVersions: _parseStringMap(
      object['componentVersions'],
      '$location.componentVersions',
    ),
    componentRevisions: _parseStringMap(
      object['componentRevisions'],
      '$location.componentRevisions',
    ),
    entryRefs: <String>[
      for (var refIndex = 0; refIndex < refs.length; refIndex += 1)
        _expectString(refs[refIndex], '$location.entryRefs[$refIndex]'),
    ],
    artifacts: <ProtocolArtifact>[
      for (var artifactIndex = 0;
          artifactIndex < artifacts.length;
          artifactIndex += 1)
        _parseArtifact(artifacts[artifactIndex], index, artifactIndex),
    ],
  );
}

ProtocolArtifact _parseArtifact(
  Object? value,
  int sourceIndex,
  int artifactIndex,
) {
  final location = 'sources[$sourceIndex].artifacts[$artifactIndex]';
  final object = _expectObject(value, location);
  _expectAllowedAndRequiredKeys(
    object,
    allowed: const <String>{'artifactId', 'role', 'path', 'size', 'sha256'},
    required: const <String>{'artifactId', 'path', 'size', 'sha256'},
    location: location,
  );
  return ProtocolArtifact(
    artifactId: _expectString(object['artifactId'], '$location.artifactId'),
    path: _expectString(object['path'], '$location.path'),
    size: _expectInt(object['size'], '$location.size'),
    sha256: _expectString(object['sha256'], '$location.sha256'),
    role: switch (object['role']) {
      null => null,
      'primary' => ProtocolArtifactRole.primary,
      'schema' => ProtocolArtifactRole.schema,
      'specification' => ProtocolArtifactRole.specification,
      'generatedComparison' => ProtocolArtifactRole.generatedComparison,
      'runtimeOracle' => ProtocolArtifactRole.runtimeOracle,
      'license' => ProtocolArtifactRole.license,
      'peerManifest' => ProtocolArtifactRole.peerManifest,
      final Object? value => throw _ProtocolSourceFormatException(
          'invalid_artifact_role',
          '$location.role is unsupported: $value.',
        ),
    },
  );
}

Map<String, String> _parseStringMap(Object? value, String location) {
  if (value == null) {
    return const <String, String>{};
  }
  final object = _expectObject(value, location);
  final result = <String, String>{};
  for (final entry in object.entries) {
    result[entry.key] = _expectString(entry.value, '$location.${entry.key}');
  }
  return Map<String, String>.unmodifiable(result);
}

Map<String, Object?> _expectObject(Object? value, String location) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$location must be a JSON object.');
  }
  return value;
}

List<Object?> _expectList(Object? value, String location) {
  if (value is! List<Object?>) {
    throw FormatException('$location must be a JSON array.');
  }
  return value;
}

String _expectString(Object? value, String location) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$location must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Object? value, String location) {
  if (value == null) {
    return null;
  }
  return _expectString(value, location);
}

int _expectInt(Object? value, String location) {
  if (value is! int || value < 0) {
    throw FormatException('$location must be a non-negative integer.');
  }
  return value;
}

void _expectKeys(
  Map<String, Object?> object,
  Set<String> expected,
  String location,
) {
  final actual = object.keys.toSet();
  if (actual.length != expected.length ||
      !actual.containsAll(expected) ||
      !expected.containsAll(actual)) {
    throw FormatException(
      '$location keys differ: expected $expected, found $actual.',
    );
  }
}

void _expectAllowedAndRequiredKeys(
  Map<String, Object?> object, {
  required Set<String> allowed,
  required Set<String> required,
  required String location,
}) {
  final actual = object.keys.toSet();
  final unknown = actual.difference(allowed);
  final missing = required.difference(actual);
  if (unknown.isNotEmpty || missing.isNotEmpty) {
    throw FormatException(
      '$location keys differ: missing $missing, unknown $unknown.',
    );
  }
}

const _supportedSchemaDialects = <String?>{
  null,
  'http://json-schema.org/draft-04/schema#',
  'http://json-schema.org/draft-07/schema#',
  'https://json-schema.org/draft/2020-12/schema',
};

const _dartComponentKeys = <String>{
  'dartSdk',
  'analysisServerApi',
  'dtdPackage',
  'vmService',
};

void _validatePeerManifest(
  File file,
  List<ProtocolSourceViolation> violations,
) {
  try {
    final document = _expectObject(
      jsonDecode(file.readAsStringSync()),
      'peer manifest',
    );
    _expectKeys(
      document,
      const <String>{
        'formatVersion',
        'nodeMajor',
        'dartSdkArchives',
        'npmPackages',
        'releaseArchives',
      },
      'peer manifest',
    );
    if (_expectInt(document['formatVersion'], 'peer manifest.formatVersion') !=
            1 ||
        _expectInt(document['nodeMajor'], 'peer manifest.nodeMajor') != 22) {
      violations.add(
        const ProtocolSourceViolation(
          'unsupported_peer_manifest',
          'Expected Phase 2b peer manifest format 1 and Node major 22.',
        ),
      );
    }

    final peerIds = <String>{};
    final sdkRoles = <String>{};
    final sdkArchives = _expectList(
      document['dartSdkArchives'],
      'peer manifest.dartSdkArchives',
    );
    for (var index = 0; index < sdkArchives.length; index += 1) {
      final location = 'peer manifest.dartSdkArchives[$index]';
      final archive = _expectObject(sdkArchives[index], location);
      _expectKeys(
        archive,
        const <String>{
          'peerId',
          'sdkRole',
          'release',
          'revision',
          'platform',
          'archive',
          'url',
          'sha256',
        },
        location,
      );
      _validatePeerId(archive, location, peerIds, violations);
      final role = archive['sdkRole'];
      if (role != 'minimum' && role != 'current') {
        violations.add(
          ProtocolSourceViolation(
            'invalid_sdk_role',
            '$location.sdkRole must be minimum or current.',
          ),
        );
      } else {
        sdkRoles.add(role! as String);
      }
      _validatePeerRevision(archive, location, violations);
      _validatePeerDigest(
        archive['sha256'],
        location: '$location.sha256',
        pattern: RegExp(r'^[a-f0-9]{64}$'),
        violations: violations,
      );
    }
    if (!sdkRoles.containsAll(const <String>{'minimum', 'current'})) {
      violations.add(
        const ProtocolSourceViolation(
          'invalid_sdk_role',
          'Peer manifest must include minimum and current SDK archives.',
        ),
      );
    }

    final npmPackages = _expectList(
      document['npmPackages'],
      'peer manifest.npmPackages',
    );
    for (var index = 0; index < npmPackages.length; index += 1) {
      final location = 'peer manifest.npmPackages[$index]';
      final package = _expectObject(npmPackages[index], location);
      _expectKeys(
        package,
        const <String>{
          'peerId',
          'package',
          'release',
          'repository',
          'revision',
          'integrity',
          'shasum',
          'tarballSize',
          'entrypoint',
        },
        location,
      );
      _validatePeerId(package, location, peerIds, violations);
      _validatePeerRevision(package, location, violations);
      _validatePeerDigest(
        package['integrity'],
        location: '$location.integrity',
        pattern: RegExp(r'^sha512-[A-Za-z0-9+/]+={0,2}$'),
        violations: violations,
      );
      _validatePeerDigest(
        package['shasum'],
        location: '$location.shasum',
        pattern: RegExp(r'^[a-f0-9]{40}$'),
        violations: violations,
      );
      _expectInt(package['tarballSize'], '$location.tarballSize');
    }

    final releaseArchives = _expectList(
      document['releaseArchives'],
      'peer manifest.releaseArchives',
    );
    for (var index = 0; index < releaseArchives.length; index += 1) {
      final location = 'peer manifest.releaseArchives[$index]';
      final archive = _expectObject(releaseArchives[index], location);
      _expectKeys(
        archive,
        const <String>{
          'peerId',
          'release',
          'repository',
          'revision',
          'asset',
          'size',
          'sha256',
          'entrypoint',
        },
        location,
      );
      _validatePeerId(archive, location, peerIds, violations);
      _validatePeerRevision(archive, location, violations);
      _expectInt(archive['size'], '$location.size');
      _validatePeerDigest(
        archive['sha256'],
        location: '$location.sha256',
        pattern: RegExp(r'^[a-f0-9]{64}$'),
        violations: violations,
      );
    }
  } on Object catch (error) {
    violations.add(
      ProtocolSourceViolation(
        'invalid_peer_manifest',
        'Unable to parse Phase 2b peer manifest: $error',
      ),
    );
  }
}

void _validatePeerId(
  Map<String, Object?> peer,
  String location,
  Set<String> peerIds,
  List<ProtocolSourceViolation> violations,
) {
  final peerId = _expectString(peer['peerId'], '$location.peerId');
  if (!peerIds.add(peerId)) {
    violations.add(
      ProtocolSourceViolation(
        'duplicate_peer_id',
        'Duplicate peer ID: $peerId.',
      ),
    );
  }
}

void _validatePeerRevision(
  Map<String, Object?> peer,
  String location,
  List<ProtocolSourceViolation> violations,
) {
  final revision = peer['revision'];
  if (revision is! String || !RegExp(r'^[a-f0-9]{40}$').hasMatch(revision)) {
    violations.add(
      ProtocolSourceViolation(
        'invalid_peer_revision',
        '$location.revision must be a full Git commit.',
      ),
    );
  }
}

void _validatePeerDigest(
  Object? digest, {
  required String location,
  required RegExp pattern,
  required List<ProtocolSourceViolation> violations,
}) {
  if (digest is! String || !pattern.hasMatch(digest)) {
    violations.add(
      ProtocolSourceViolation(
        'missing_peer_digest',
        '$location must contain the pinned digest.',
      ),
    );
  }
}

bool _isContainedExistingFile(Directory root, File file) {
  final canonicalRoot = root.resolveSymbolicLinksSync();
  final canonicalFile = file.resolveSymbolicLinksSync();
  return canonicalFile == canonicalRoot ||
      canonicalFile.startsWith('$canonicalRoot${Platform.pathSeparator}');
}

bool _isCanonicalRelativePath(String path) =>
    path.isNotEmpty &&
    !path.startsWith('/') &&
    !path.endsWith('/') &&
    !path.contains(r'\') &&
    path.split('/').every(
          (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
        );

File _containedFile(Directory root, String relativePath) {
  if (!_isCanonicalRelativePath(relativePath)) {
    throw ArgumentError.value(
      relativePath,
      'relativePath',
      'Expected a canonical relative path.',
    );
  }
  return File.fromUri(root.absolute.uri.resolve(relativePath));
}

final class _ProtocolSourceFormatException implements Exception {
  const _ProtocolSourceFormatException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
