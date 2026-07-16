import 'dart:convert';
import 'dart:io';

const expectedPackages = <String, String>{
  'packages/provider/pubspec.yaml': 'pigcode_ai_provider',
  'packages/provider_utils/pubspec.yaml': 'pigcode_ai_provider_utils',
  'packages/ai/pubspec.yaml': 'pigcode_ai',
  'packages/openai/pubspec.yaml': 'pigcode_ai_openai',
  'packages/openai_compatible/pubspec.yaml': 'pigcode_ai_openai_compatible',
  'packages/anthropic/pubspec.yaml': 'pigcode_ai_anthropic',
};

const expectedPublicFiles = <String>[
  'packages/provider/lib/pigcode_ai_provider.dart',
  'packages/provider_utils/lib/pigcode_ai_provider_utils.dart',
  'packages/ai/lib/pigcode_ai.dart',
  'packages/ai/test/pigcode_ai_test.dart',
  'packages/openai/lib/pigcode_ai_openai.dart',
  'packages/openai_compatible/lib/pigcode_ai_openai_compatible.dart',
  'packages/anthropic/lib/pigcode_ai_anthropic.dart',
];

const expectedPackageDirectories = <String>{
  'ai',
  'anthropic',
  'openai',
  'openai_compatible',
  'provider',
  'provider_utils',
};

const ignoredDirectories = <String>{
  '.git',
  '.dart_tool',
  '.melos_tool',
  '.idea',
  '.vscode',
  'build',
};

const forbiddenPathSegments = <String>{
  '.codex',
  '.superpowers',
  '.worktrees',
};

const forbiddenFileNames = <String>{
  'AGENTS.md',
  'CLAUDE.md',
};

void main() {
  final failures = <String>[];

  _expectPackageName(
    path: 'pubspec.yaml',
    expectedName: 'pigcode_ai_workspace',
    failures: failures,
  );

  _expectPackageDirectories(failures);

  for (final entry in expectedPackages.entries) {
    _expectPackageManifest(
      path: entry.key,
      expectedName: entry.value,
      failures: failures,
    );
  }

  for (final path in expectedPublicFiles) {
    if (!File(path).existsSync()) {
      failures.add('Missing expected public file: $path');
    }
  }

  final legacyBrand = String.fromCharCodes(<int>[100, 114, 111, 109, 111, 110]);
  final forbiddenMarkers = <String>[
    <String>['128', '593', '5238'].join(),
    <String>['29f1', '9b83'].join(),
    <String>['48cd', '70cc'].join(),
    <String>['pigcode', 'docs'].join('/'),
    <String>['pigcode', 'workspace'].join('/'),
    String.fromCharCodes(<int>[47, 85, 115, 101, 114, 115, 47]),
  ];
  final secretPatterns = <RegExp>[
    RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    RegExp(r'github_pat_[A-Za-z0-9_]{20,}'),
    RegExp(r'gh[pousr]_[A-Za-z0-9]{30,}'),
    RegExp(r'sk-ant-[A-Za-z0-9_-]{20,}'),
    RegExp(r'sk-[A-Za-z0-9_-]{24,}'),
    RegExp(r'AKIA[0-9A-Z]{16}'),
  ];
  final root = Directory.current.absolute.path;

  for (final entity in Directory.current.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) {
      continue;
    }

    final absolutePath = entity.absolute.path;
    final relativePath = absolutePath.substring(root.length + 1);
    final segments = relativePath.split(Platform.pathSeparator);

    if (segments.any(ignoredDirectories.contains)) {
      continue;
    }

    if (segments.any(forbiddenPathSegments.contains) ||
        forbiddenFileNames.contains(segments.last)) {
      failures.add('Forbidden public path: $relativePath');
    }

    if (relativePath.toLowerCase().contains(legacyBrand)) {
      failures.add('Legacy identity remains in path: $relativePath');
    }

    for (final marker in forbiddenMarkers) {
      if (relativePath.contains(marker)) {
        failures.add('Private migration marker remains in path: $relativePath');
      }
    }

    final contents = utf8.decode(
      entity.readAsBytesSync(),
      allowMalformed: true,
    );
    if (contents.toLowerCase().contains(legacyBrand)) {
      failures.add('Legacy identity remains in file: $relativePath');
    }
    for (final marker in forbiddenMarkers) {
      if (contents.contains(marker)) {
        failures.add('Private migration marker remains in file: $relativePath');
      }
    }
    for (final pattern in secretPatterns) {
      if (pattern.hasMatch(contents)) {
        failures.add('Possible secret remains in file: $relativePath');
      }
    }
  }

  if (failures.isNotEmpty) {
    for (final failure in failures.toSet().toList()..sort()) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Pigcode project identity is consistent.');
}

void _expectPackageDirectories(List<String> failures) {
  final packages = Directory('packages');
  if (!packages.existsSync()) {
    failures.add('Missing packages directory');
    return;
  }

  final actualDirectories = packages
      .listSync(followLinks: false)
      .whereType<Directory>()
      .map((directory) => directory.path.split(Platform.pathSeparator).last)
      .toSet();
  final missing = expectedPackageDirectories.difference(actualDirectories);
  final unexpected = actualDirectories.difference(expectedPackageDirectories);

  for (final directory in missing) {
    failures.add('Missing package directory: packages/$directory');
  }
  for (final directory in unexpected) {
    failures.add('Unexpected package directory: packages/$directory');
  }
}

void _expectPackageName({
  required String path,
  required String expectedName,
  required List<String> failures,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    failures.add('Missing pubspec: $path');
    return;
  }

  final namePattern = RegExp(
    '^name: ${RegExp.escape(expectedName)}\\s*\$',
    multiLine: true,
  );
  if (!namePattern.hasMatch(file.readAsStringSync())) {
    failures.add('Expected package name $expectedName in $path');
  }
}

void _expectPackageManifest({
  required String path,
  required String expectedName,
  required List<String> failures,
}) {
  _expectPackageName(
    path: path,
    expectedName: expectedName,
    failures: failures,
  );

  final file = File(path);
  if (!file.existsSync()) {
    return;
  }

  final contents = file.readAsStringSync();
  if (!RegExp(r'^publish_to:\s*none\s*$', multiLine: true).hasMatch(contents)) {
    failures.add('Expected publish_to: none in $path');
  }
  if (RegExp(r'^\s+path:\s*\S+', multiLine: true).hasMatch(contents)) {
    failures.add('Path dependency is not allowed in $path');
  }
}
