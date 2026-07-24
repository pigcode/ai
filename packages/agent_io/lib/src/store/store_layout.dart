import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'registry_manifest.dart';

enum StoreLayoutErrorCode {
  rootMissing,
  symlinkRejected,
  unexpectedEntity,
  outsideRoot,
  invalidArtifactName,
}

final class StoreLayoutException implements Exception {
  const StoreLayoutException(this.code, this.message, {this.path});

  final StoreLayoutErrorCode code;
  final String message;
  final String? path;

  @override
  String toString() => 'StoreLayoutException(${code.name}): $message';
}

/// Typed, root-confined paths for the Phase 3 file Store.
///
/// This class does not create or mutate files. Writable operations are added
/// by the Store writer only after lock and durability coordination.
final class StoreLayout {
  StoreLayout.open(Directory root) : root = _openCanonicalRoot(root);

  final Directory root;

  File get storeMetadata => File(paths.join(root.path, 'store.meta'));

  File get storeLock => File(paths.join(root.path, 'store.lock'));

  Directory get sessionCatalog =>
      Directory(paths.join(root.path, 'session-catalog'));

  Directory get sessionCatalogChunks =>
      Directory(paths.join(sessionCatalog.path, 'chunks'));

  Directory get sessionCatalogManifests =>
      Directory(paths.join(sessionCatalog.path, 'manifests'));

  Directory get createSessionCommands =>
      Directory(paths.join(root.path, 'create-session-commands'));

  Directory get createSessionCommandChunks =>
      Directory(paths.join(createSessionCommands.path, 'chunks'));

  Directory get createSessionCommandManifests =>
      Directory(paths.join(createSessionCommands.path, 'manifests'));

  Directory get rootManifests => Directory(paths.join(root.path, 'manifests'));

  Directory get sessions => Directory(paths.join(root.path, 'sessions'));

  String sessionShard(SessionId sessionId) => sessionId.value.substring(4, 6);

  Directory sessionDirectory(SessionId sessionId) => Directory(paths.join(
        sessions.path,
        sessionShard(sessionId),
        sessionId.value,
      ));

  Directory segments(SessionId sessionId) =>
      Directory(paths.join(sessionDirectory(sessionId).path, 'segments'));

  Directory snapshots(SessionId sessionId) =>
      Directory(paths.join(sessionDirectory(sessionId).path, 'snapshots'));

  Directory manifests(SessionId sessionId) =>
      Directory(paths.join(sessionDirectory(sessionId).path, 'manifests'));

  Directory identities(SessionId sessionId) =>
      Directory(paths.join(sessionDirectory(sessionId).path, 'identities'));

  Directory identityChunks(SessionId sessionId) =>
      Directory(paths.join(identities(sessionId).path, 'chunks'));

  Directory identityManifests(SessionId sessionId) =>
      Directory(paths.join(identities(sessionId).path, 'manifests'));

  Directory commands(SessionId sessionId) =>
      Directory(paths.join(sessionDirectory(sessionId).path, 'commands'));

  Directory commandChunks(SessionId sessionId) =>
      Directory(paths.join(commands(sessionId).path, 'chunks'));

  Directory commandManifests(SessionId sessionId) =>
      Directory(paths.join(commands(sessionId).path, 'manifests'));

  Directory temporary(SessionId sessionId) =>
      Directory(paths.join(sessionDirectory(sessionId).path, 'tmp'));

  Directory retired(SessionId sessionId) =>
      Directory(paths.join(sessionDirectory(sessionId).path, 'retired'));

  File journalSegmentFile(
    SessionId sessionId, {
    required int startSequence,
    required String digest,
  }) {
    if (startSequence <= 0) {
      throw const StoreLayoutException(
        StoreLayoutErrorCode.invalidArtifactName,
        'Segment start sequence must be positive.',
      );
    }
    _validateDigest(digest);
    return File(paths.join(
      segments(sessionId).path,
      '${startSequence.toString().padLeft(20, '0')}-$digest.pigj',
    ));
  }

  File snapshotFile(
    SessionId sessionId, {
    required SnapshotId snapshotId,
    required String digest,
  }) {
    _validateDigest(digest);
    return File(paths.join(
      snapshots(sessionId).path,
      '${snapshotId.value}-$digest.pigs',
    ));
  }

  File identityChunkFile(SessionId sessionId, String digest) =>
      _contentAddressedFile(identityChunks(sessionId), digest, '.json');

  File commandChunkFile(SessionId sessionId, String digest) =>
      _contentAddressedFile(commandChunks(sessionId), digest, '.json');

  File sessionCatalogChunkFile(String digest) =>
      _contentAddressedFile(sessionCatalogChunks, digest, '.json');

  File createSessionCommandChunkFile(String digest) =>
      _contentAddressedFile(createSessionCommandChunks, digest, '.json');

  File identityManifestFile(
    SessionId sessionId, {
    required int generation,
    required String digest,
  }) =>
      _generationFile(
        identityManifests(sessionId),
        generation,
        digest,
      );

  File commandManifestFile(
    SessionId sessionId, {
    required int generation,
    required String digest,
  }) =>
      _generationFile(
        commandManifests(sessionId),
        generation,
        digest,
      );

  File sessionManifestFile(
    SessionId sessionId, {
    required int generation,
    required String digest,
  }) =>
      _generationFile(manifests(sessionId), generation, digest);

  File rootRegistryManifestFile({
    required RegistryKind kind,
    required int generation,
    required String digest,
  }) {
    final directory = switch (kind) {
      RegistryKind.sessionCatalog => sessionCatalogManifests,
      RegistryKind.createSessionCommand => createSessionCommandManifests,
      RegistryKind.identity ||
      RegistryKind.command =>
        throw const StoreLayoutException(
          StoreLayoutErrorCode.invalidArtifactName,
          'Session registry kind requires a typed SessionId.',
        ),
    };
    return _generationFile(directory, generation, digest);
  }

  File rootManifestFile({
    required int generation,
    required String digest,
  }) =>
      _generationFile(rootManifests, generation, digest);

  /// Rejects links, sockets, devices, and other unexpected entities anywhere
  /// below the Store root. Directories and regular files are the only accepted
  /// types.
  void validateExistingTree() {
    _validateDirectory(root);
  }

  /// Validates an existing artifact and every path component without following
  /// links. The artifact must be a regular file confined to this Store root.
  void validateExistingArtifact(File file) {
    final normalized = paths.normalize(paths.absolute(file.path));
    _requireInsideRoot(normalized);
    _rejectSymlinkComponentsBelowRoot(normalized);
    final type = FileSystemEntity.typeSync(normalized, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw StoreLayoutException(
        StoreLayoutErrorCode.unexpectedEntity,
        'Store artifact is not a regular file.',
        path: normalized,
      );
    }
  }

  File _contentAddressedFile(
    Directory directory,
    String digest,
    String extension,
  ) {
    _validateDigest(digest);
    return File(paths.join(directory.path, '$digest$extension'));
  }

  File _generationFile(
    Directory directory,
    int generation,
    String digest,
  ) {
    if (generation <= 0) {
      throw const StoreLayoutException(
        StoreLayoutErrorCode.invalidArtifactName,
        'Manifest generation must be positive.',
      );
    }
    _validateDigest(digest);
    return File(paths.join(
      directory.path,
      '${generation.toString().padLeft(20, '0')}-$digest.json',
    ));
  }

  void _requireInsideRoot(String candidate) {
    if (candidate != root.path && !paths.isWithin(root.path, candidate)) {
      throw StoreLayoutException(
        StoreLayoutErrorCode.outsideRoot,
        'Store artifact resolves outside the canonical root.',
        path: candidate,
      );
    }
  }

  void _validateDirectory(Directory directory) {
    final type = FileSystemEntity.typeSync(directory.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw StoreLayoutException(
        StoreLayoutErrorCode.symlinkRejected,
        'Store tree contains a symlink.',
        path: directory.path,
      );
    }
    if (type != FileSystemEntityType.directory) {
      throw StoreLayoutException(
        StoreLayoutErrorCode.unexpectedEntity,
        'Expected a Store directory.',
        path: directory.path,
      );
    }
    for (final entity in directory.listSync(followLinks: false)) {
      final childType =
          FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (childType == FileSystemEntityType.link) {
        throw StoreLayoutException(
          StoreLayoutErrorCode.symlinkRejected,
          'Store tree contains a symlink.',
          path: entity.path,
        );
      }
      if (childType == FileSystemEntityType.directory) {
        _validateDirectory(Directory(entity.path));
      } else if (childType != FileSystemEntityType.file) {
        throw StoreLayoutException(
          StoreLayoutErrorCode.unexpectedEntity,
          'Store tree contains a non-regular entity.',
          path: entity.path,
        );
      }
    }
  }

  static Directory _openCanonicalRoot(Directory input) {
    final absolute = paths.normalize(paths.absolute(input.path));
    final type = FileSystemEntity.typeSync(absolute, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw StoreLayoutException(
        StoreLayoutErrorCode.symlinkRejected,
        'Store root cannot be a symlink.',
        path: absolute,
      );
    }
    if (type == FileSystemEntityType.notFound) {
      throw StoreLayoutException(
        StoreLayoutErrorCode.rootMissing,
        'Store root does not exist.',
        path: absolute,
      );
    }
    if (type != FileSystemEntityType.directory) {
      throw StoreLayoutException(
        StoreLayoutErrorCode.unexpectedEntity,
        'Store root is not a directory.',
        path: absolute,
      );
    }
    return Directory(input.resolveSymbolicLinksSync());
  }

  void _rejectSymlinkComponentsBelowRoot(String absolute) {
    var current = root.path;
    final relative = paths.relative(absolute, from: root.path);
    for (final component in paths.split(relative)) {
      current = paths.join(current, component);
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw StoreLayoutException(
          StoreLayoutErrorCode.symlinkRejected,
          'Store path contains a symlink component.',
          path: current,
        );
      }
      if (type == FileSystemEntityType.notFound) break;
    }
  }

  static void _validateDigest(String digest) {
    if (!isStoreDigest(digest)) {
      throw const StoreLayoutException(
        StoreLayoutErrorCode.invalidArtifactName,
        'Artifact digest must be lowercase SHA-256 hex.',
      );
    }
  }
}
