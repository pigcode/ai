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

final class ProtocolArtifact {
  const ProtocolArtifact({
    required this.artifactId,
    required this.path,
    required this.size,
    required this.sha256,
  });

  final String artifactId;
  final String path;
  final int size;
  final String sha256;
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
    required this.entryRefs,
    required this.artifacts,
  });

  final String sourceId;
  final String protocol;
  final String repository;
  final String release;
  final String revision;
  final String releaseDate;
  final String wireVersion;
  final String? schemaDialect;
  final List<String> entryRefs;
  final List<ProtocolArtifact> artifacts;
}

final class ProtocolSourceLock {
  const ProtocolSourceLock({
    required this.formatVersion,
    required this.generatorIdentity,
    required this.generatorFormatVersion,
    required this.sources,
  });

  final int formatVersion;
  final String generatorIdentity;
  final int generatorFormatVersion;
  final List<ProtocolSource> sources;
}

ProtocolSourceLock loadProtocolSourceLock(Directory root) {
  final lockFile = _containedFile(root, protocolSourceLockPath);
  final document = jsonDecode(lockFile.readAsStringSync());
  final object = _expectObject(document, 'source lock');
  _expectKeys(
    object,
    const <String>{'formatVersion', 'generator', 'sources'},
    'source lock',
  );
  final generator = _expectObject(object['generator'], 'generator');
  _expectKeys(
    generator,
    const <String>{'identity', 'formatVersion'},
    'generator',
  );
  final sources = _expectList(object['sources'], 'sources');

  return ProtocolSourceLock(
    formatVersion: _expectInt(object['formatVersion'], 'formatVersion'),
    generatorIdentity: _expectString(
      generator['identity'],
      'generator.identity',
    ),
    generatorFormatVersion: _expectInt(
      generator['formatVersion'],
      'generator.formatVersion',
    ),
    sources: <ProtocolSource>[
      for (var index = 0; index < sources.length; index += 1)
        _parseSource(sources[index], index),
    ],
  );
}

List<ProtocolSourceViolation> validateProtocolSources(
  Directory root, {
  Map<String, File> artifactOverrides = const <String, File>{},
}) {
  final violations = <ProtocolSourceViolation>[];
  late final ProtocolSourceLock sourceLock;
  try {
    sourceLock = loadProtocolSourceLock(root);
  } on Object catch (error) {
    return <ProtocolSourceViolation>[
      ProtocolSourceViolation('invalid_source_lock', error.toString()),
    ];
  }

  if (sourceLock.formatVersion != 1) {
    violations.add(
      const ProtocolSourceViolation(
        'unsupported_source_lock_version',
        'Protocol source-lock formatVersion must be 1.',
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
    for (final artifact in source.artifacts) {
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
  _expectKeys(
    object,
    const <String>{
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
    location,
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
    wireVersion: _expectString(object['wireVersion'], '$location.wireVersion'),
    schemaDialect: switch (object['schemaDialect']) {
      null => null,
      final String value => value,
      _ => throw FormatException(
          '$location.schemaDialect must be a string or null.',
        ),
    },
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
  _expectKeys(
    object,
    const <String>{'artifactId', 'path', 'size', 'sha256'},
    location,
  );
  return ProtocolArtifact(
    artifactId: _expectString(object['artifactId'], '$location.artifactId'),
    path: _expectString(object['path'], '$location.path'),
    size: _expectInt(object['size'], '$location.size'),
    sha256: _expectString(object['sha256'], '$location.sha256'),
  );
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
