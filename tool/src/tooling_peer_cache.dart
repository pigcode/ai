import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

final class ToolingPeerException implements Exception {
  const ToolingPeerException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ToolingPeerException($code): $message';
}

final class DartSdkArchivePin {
  const DartSdkArchivePin({
    required this.peerId,
    required this.sdkRole,
    required this.release,
    required this.revision,
    required this.platform,
    required this.archive,
    required this.url,
    required this.sha256,
  });

  final String peerId;
  final String sdkRole;
  final String release;
  final String revision;
  final String platform;
  final String archive;
  final Uri url;
  final String sha256;
}

final class NpmPeerPin {
  const NpmPeerPin({
    required this.peerId,
    required this.package,
    required this.release,
    required this.revision,
    required this.integrity,
    required this.shasum,
    required this.tarballSize,
    required this.entrypoint,
  });

  final String peerId;
  final String package;
  final String release;
  final String revision;
  final String integrity;
  final String shasum;
  final int tarballSize;
  final String entrypoint;
}

final class ReleaseArchivePin {
  const ReleaseArchivePin({
    required this.peerId,
    required this.release,
    required this.repository,
    required this.revision,
    required this.asset,
    required this.size,
    required this.sha256,
    required this.entrypoint,
  });

  final String peerId;
  final String release;
  final String repository;
  final String revision;
  final String asset;
  final int size;
  final String sha256;
  final String entrypoint;

  Uri get downloadUri => Uri.parse(
        '$repository/releases/download/$release/$asset',
      );
}

final class ToolingPeerManifest {
  const ToolingPeerManifest({
    required this.nodeMajor,
    required this.dartSdkArchives,
    required this.npmPackages,
    required this.releaseArchives,
  });

  factory ToolingPeerManifest.load(Directory root) {
    final file = File.fromUri(
      root.absolute.uri.resolve(
        'tool/upstream/protocols/peers/phase-2b-peers.json',
      ),
    );
    final document =
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    if (document['formatVersion'] != 1) {
      throw const ToolingPeerException(
        'tooling_peer_manifest_version',
        'Unsupported tooling peer manifest format.',
      );
    }
    return ToolingPeerManifest(
      nodeMajor: document['nodeMajor']! as int,
      dartSdkArchives: List<DartSdkArchivePin>.unmodifiable(
        (document['dartSdkArchives']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(
              (entry) => DartSdkArchivePin(
                peerId: entry['peerId']! as String,
                sdkRole: entry['sdkRole']! as String,
                release: entry['release']! as String,
                revision: entry['revision']! as String,
                platform: entry['platform']! as String,
                archive: entry['archive']! as String,
                url: Uri.parse(entry['url']! as String),
                sha256: entry['sha256']! as String,
              ),
            ),
      ),
      npmPackages: List<NpmPeerPin>.unmodifiable(
        (document['npmPackages']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(
              (entry) => NpmPeerPin(
                peerId: entry['peerId']! as String,
                package: entry['package']! as String,
                release: entry['release']! as String,
                revision: entry['revision']! as String,
                integrity: entry['integrity']! as String,
                shasum: entry['shasum']! as String,
                tarballSize: entry['tarballSize']! as int,
                entrypoint: entry['entrypoint']! as String,
              ),
            ),
      ),
      releaseArchives: List<ReleaseArchivePin>.unmodifiable(
        (document['releaseArchives']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(
              (entry) => ReleaseArchivePin(
                peerId: entry['peerId']! as String,
                release: entry['release']! as String,
                repository: entry['repository']! as String,
                revision: entry['revision']! as String,
                asset: entry['asset']! as String,
                size: entry['size']! as int,
                sha256: entry['sha256']! as String,
                entrypoint: entry['entrypoint']! as String,
              ),
            ),
      ),
    );
  }

  final int nodeMajor;
  final List<DartSdkArchivePin> dartSdkArchives;
  final List<NpmPeerPin> npmPackages;
  final List<ReleaseArchivePin> releaseArchives;

  DartSdkArchivePin dartSdk({
    required String release,
    required String platform,
  }) {
    for (final pin in dartSdkArchives) {
      if (pin.release == release && pin.platform == platform) {
        return pin;
      }
    }
    throw ToolingPeerException(
      'tooling_platform_unsupported',
      'No pinned Dart $release SDK archive exists for $platform.',
    );
  }

  NpmPeerPin npmPackage(String package) {
    for (final pin in npmPackages) {
      if (pin.package == package) {
        return pin;
      }
    }
    throw ToolingPeerException(
      'tooling_npm_peer_unknown',
      'No pinned npm package exists for $package.',
    );
  }

  ReleaseArchivePin releaseArchive(String peerId) {
    for (final pin in releaseArchives) {
      if (pin.peerId == peerId) {
        return pin;
      }
    }
    throw ToolingPeerException(
      'tooling_release_peer_unknown',
      'No pinned release archive exists for $peerId.',
    );
  }
}

/// Digest-checked cache for fixed SDK and npm tooling peers.
final class ToolingPeerCache {
  ToolingPeerCache({
    required this.root,
    Directory? cacheRoot,
  })  : cacheRoot = cacheRoot ??
            Directory.fromUri(
              root.absolute.uri.resolve('.dart_tool/tooling-peer-cache/'),
            ),
        manifest = ToolingPeerManifest.load(root);

  final Directory root;
  final Directory cacheRoot;
  final ToolingPeerManifest manifest;

  static String hostPlatformId() {
    final operatingSystem = switch (Platform.operatingSystem) {
      'linux' => 'linux',
      'macos' => 'macos',
      final value => throw ToolingPeerException(
          'tooling_platform_unsupported',
          'Tooling peer archives do not support $value.',
        ),
    };
    final result = Process.runSync('uname', const <String>['-m']);
    if (result.exitCode != 0) {
      throw const ToolingPeerException(
        'tooling_architecture_unknown',
        'Unable to determine host architecture.',
      );
    }
    final architecture = switch ((result.stdout as String).trim()) {
      'x86_64' => 'x64',
      'arm64' || 'aarch64' => 'arm64',
      final value => throw ToolingPeerException(
          'tooling_platform_unsupported',
          'Tooling peer archives do not support architecture $value.',
        ),
    };
    return '$operatingSystem-$architecture';
  }

  Future<Directory> ensureDartSdk(String release) async {
    final pin = manifest.dartSdk(
      release: release,
      platform: hostPlatformId(),
    );
    final archives = Directory.fromUri(cacheRoot.uri.resolve('archives/'))
      ..createSync(recursive: true);
    final archive = File.fromUri(archives.uri.resolve('${pin.peerId}.zip'));
    if (!archive.existsSync()) {
      await _download(pin.url, archive);
    }
    validateArtifact(archive, expectedSha256: pin.sha256);

    final sdkContainer = Directory.fromUri(
      cacheRoot.uri.resolve('dart/${pin.peerId}/'),
    );
    final sdkRoot = Directory.fromUri(sdkContainer.uri.resolve('dart-sdk/'));
    final marker = File.fromUri(sdkContainer.uri.resolve('.archive.sha256'));
    if (sdkRoot.existsSync() &&
        marker.existsSync() &&
        marker.readAsStringSync().trim() == pin.sha256) {
      dartExecutable(sdkRoot);
      return sdkRoot;
    }
    if (sdkContainer.existsSync()) {
      sdkContainer.deleteSync(recursive: true);
    }
    final parent = Directory.fromUri(cacheRoot.uri.resolve('dart/'))
      ..createSync(recursive: true);
    final temporary = parent.createTempSync('.extract-${pin.peerId}-');
    try {
      final result = await Process.run(
        'unzip',
        <String>['-q', archive.path, '-d', temporary.path],
      );
      if (result.exitCode != 0) {
        throw ToolingPeerException(
          'tooling_sdk_extract_failed',
          'Pinned Dart SDK extraction failed: ${result.stderr}',
        );
      }
      final extracted = Directory.fromUri(
        temporary.uri.resolve('dart-sdk/'),
      );
      dartExecutable(extracted);
      sdkContainer.parent.createSync(recursive: true);
      temporary.renameSync(sdkContainer.path);
      marker.writeAsStringSync('${pin.sha256}\n');
      return sdkRoot;
    } finally {
      if (temporary.existsSync()) {
        temporary.deleteSync(recursive: true);
      }
    }
  }

  void validateArtifact(
    File artifact, {
    required String expectedSha256,
  }) {
    if (!artifact.existsSync()) {
      throw const ToolingPeerException(
        'tooling_artifact_missing',
        'Pinned tooling artifact is missing.',
      );
    }
    final actual = sha256.convert(artifact.readAsBytesSync()).toString();
    if (actual != expectedSha256) {
      throw ToolingPeerException(
        'tooling_artifact_digest_mismatch',
        'Pinned tooling artifact digest mismatch: expected '
            '$expectedSha256, found $actual.',
      );
    }
  }

  Future<Directory> ensureTypeScriptPeer() async {
    final fixture = Directory.fromUri(
      root.absolute.uri.resolve('tool/fixtures/lsp/typescript/'),
    );
    final node = await Process.run('node', const <String>['--version']);
    final version = (node.stdout as String).trim();
    if (node.exitCode != 0 || !version.startsWith('v${manifest.nodeMajor}.')) {
      throw ToolingPeerException(
        'tooling_node_version_mismatch',
        'Pinned TypeScript peer requires Node ${manifest.nodeMajor}; '
            'found $version.',
      );
    }
    final npm = await Process.run(
      'npm',
      const <String>['ci', '--ignore-scripts', '--no-audit', '--no-fund'],
      workingDirectory: fixture.path,
    );
    if (npm.exitCode != 0) {
      throw ToolingPeerException(
        'tooling_npm_install_failed',
        'Pinned TypeScript peer install failed: ${npm.stderr}',
      );
    }
    for (final pin in manifest.npmPackages) {
      final packageJson = File.fromUri(
        fixture.uri.resolve('node_modules/${pin.package}/package.json'),
      );
      final installed =
          jsonDecode(packageJson.readAsStringSync()) as Map<String, Object?>;
      if ('v${installed['version']}' != pin.release) {
        throw ToolingPeerException(
          'tooling_npm_version_mismatch',
          'Installed ${pin.package} does not match ${pin.release}.',
        );
      }
    }
    return fixture;
  }

  Future<Directory> ensureReleaseArchive(String peerId) async {
    final pin = manifest.releaseArchive(peerId);
    final archives = Directory.fromUri(cacheRoot.uri.resolve('archives/'))
      ..createSync(recursive: true);
    final archive = File.fromUri(archives.uri.resolve(pin.asset));
    if (!archive.existsSync()) {
      await _download(pin.downloadUri, archive);
    }
    if (archive.lengthSync() != pin.size) {
      throw ToolingPeerException(
        'tooling_artifact_size_mismatch',
        'Pinned ${pin.asset} size mismatch: expected ${pin.size}, '
            'found ${archive.lengthSync()}.',
      );
    }
    validateArtifact(archive, expectedSha256: pin.sha256);

    final destination = Directory.fromUri(
      cacheRoot.uri.resolve('releases/${pin.peerId}/'),
    );
    final marker = File.fromUri(destination.uri.resolve('.archive.sha256'));
    final entrypoint = File.fromUri(
      destination.uri.resolve(pin.entrypoint),
    );
    if (destination.existsSync() &&
        marker.existsSync() &&
        marker.readAsStringSync().trim() == pin.sha256 &&
        entrypoint.existsSync()) {
      return destination;
    }
    if (destination.existsSync()) {
      destination.deleteSync(recursive: true);
    }
    final parent = Directory.fromUri(cacheRoot.uri.resolve('releases/'))
      ..createSync(recursive: true);
    final temporary = parent.createTempSync('.extract-${pin.peerId}-');
    try {
      final result = await Process.run(
        'tar',
        <String>['-xzf', archive.path, '-C', temporary.path],
      );
      if (result.exitCode != 0) {
        throw ToolingPeerException(
          'tooling_release_extract_failed',
          'Pinned release extraction failed: ${result.stderr}',
        );
      }
      final extractedEntrypoint = File.fromUri(
        temporary.uri.resolve(pin.entrypoint),
      );
      if (!extractedEntrypoint.existsSync()) {
        throw ToolingPeerException(
          'tooling_release_entrypoint_missing',
          'Pinned release is missing ${pin.entrypoint}.',
        );
      }
      temporary.renameSync(destination.path);
      marker.writeAsStringSync('${pin.sha256}\n');
      return destination;
    } finally {
      if (temporary.existsSync()) {
        temporary.deleteSync(recursive: true);
      }
    }
  }

  static File dartExecutable(Directory sdkRoot) {
    final executable = File.fromUri(
      sdkRoot.absolute.uri.resolve(
        Platform.isWindows ? 'bin/dart.exe' : 'bin/dart',
      ),
    );
    if (!executable.existsSync()) {
      throw const ToolingPeerException(
        'tooling_sdk_executable_missing',
        'Verified SDK does not contain its Dart executable.',
      );
    }
    return executable;
  }

  Future<void> _download(Uri url, File destination) async {
    destination.parent.createSync(recursive: true);
    final temporary = File('${destination.path}.partial');
    if (temporary.existsSync()) {
      temporary.deleteSync();
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw ToolingPeerException(
          'tooling_download_failed',
          'Pinned tooling download returned HTTP ${response.statusCode}.',
        );
      }
      final sink = temporary.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }
      temporary.renameSync(destination.path);
    } finally {
      client.close(force: true);
      if (temporary.existsSync()) {
        temporary.deleteSync();
      }
    }
  }
}
