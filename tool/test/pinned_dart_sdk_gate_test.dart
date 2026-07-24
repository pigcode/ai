import 'dart:io';

import '../src/tooling_peer_cache.dart';

void main() {
  final root = Directory.current;
  final manifest = ToolingPeerManifest.load(root);

  _expect(manifest.nodeMajor == 22, 'Expected Node 22 pin.');
  _expect(manifest.dartSdkArchives.length == 4, 'Expected four SDK archives.');
  _expect(
    manifest
            .dartSdk(
              release: '3.6.0',
              platform: 'linux-x64',
            )
            .sha256 ==
        '8e14ff436e1eec72618dabc94f421a97251f2068c9cc9ad2d3bb9d232d6155a3',
    'Wrong 3.6.0 Linux SDK digest.',
  );
  _expect(
    manifest
            .dartSdk(
              release: '3.12.2',
              platform: 'macos-arm64',
            )
            .sha256 ==
        'cd8753928e77b6b665bd70dce0e64b4ec6d2e2fde141d6409bb716c8ac1f1c0a',
    'Wrong 3.12.2 macOS SDK digest.',
  );
  _expectThrows(
    () => manifest.dartSdk(release: '3.6.0', platform: 'windows-x64'),
    'Unsupported platforms must fail explicitly.',
  );
  final languageServer = manifest.npmPackage('typescript-language-server');
  _expect(
    languageServer.release == 'v5.3.0' &&
        languageServer.tarballSize == 501633 &&
        languageServer.shasum == '0f3e8c9d1ea915d4d74c548803346a157ae29856' &&
        languageServer.integrity ==
            'sha512-5puofxZHgFdAYtfNpmwCAvgtaYgg8wrUnH30m7Ze3QuguId5RNRadKASpOpyDxTyUdAF51FjhTdjntLw/EuWcQ==',
    'Wrong TypeScript language server pin.',
  );
  final typescript = manifest.npmPackage('typescript');
  _expect(
    typescript.release == 'v6.0.3' &&
        typescript.tarballSize == 4515854 &&
        typescript.shasum == '90251dc007916e972786cb94d74d15b185577d21' &&
        typescript.integrity ==
            'sha512-y2TvuxSZPDyQakkFRPZHKFm+KKVqIisdg9/CZwm9ftvKXLP8NRWj38/ODjNbr43SsoXqNuAisEf1GdCxqWcdBw==',
    'Wrong TypeScript compiler pin.',
  );

  final temporary = Directory.systemTemp.createTempSync(
    'pigcode_pinned_sdk_gate_',
  );
  try {
    final artifact = File.fromUri(temporary.uri.resolve('sdk.zip'))
      ..writeAsBytesSync(<int>[1, 2, 3]);
    _expectThrows(
      () => ToolingPeerCache(
        root: root,
        cacheRoot: temporary,
      ).validateArtifact(
        artifact,
        expectedSha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
      'One-byte/cache mutation must fail digest validation.',
    );

    final sdkRoot = Directory.fromUri(temporary.uri.resolve('dart-sdk/'))
      ..createSync();
    final executable = File.fromUri(
      sdkRoot.uri.resolve(Platform.isWindows ? 'bin/dart.exe' : 'bin/dart'),
    )..createSync(recursive: true);
    final resolved = ToolingPeerCache.dartExecutable(sdkRoot);
    _expect(
      resolved.absolute.path == executable.absolute.path,
      'Pinned executable must resolve inside the extracted SDK.',
    );
    executable.deleteSync();
    _expectThrows(
      () => ToolingPeerCache.dartExecutable(sdkRoot),
      'Missing pinned executable must not fall back to PATH.',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }

  stdout.writeln('PASS pinned Dart SDK gate');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

void _expectThrows(void Function() callback, String message) {
  try {
    callback();
  } on ToolingPeerException {
    return;
  }
  throw StateError(message);
}
