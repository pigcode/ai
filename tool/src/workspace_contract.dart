import 'dart:io';

const _expectedPackages = <String, String>{
  'provider': 'pigcode_ai_provider',
  'provider_utils': 'pigcode_ai_provider_utils',
  'ai': 'pigcode_ai',
  'openai': 'pigcode_ai_openai',
  'openai_compatible': 'pigcode_ai_openai_compatible',
  'anthropic': 'pigcode_ai_anthropic',
};

const _requiredRootPaths = <String>{
  '.gitignore',
  'CHANGELOG.md',
  'LICENSE',
  'README.md',
  'THIRD_PARTY_NOTICES.md',
  'pubspec.yaml',
  'third_party/licenses/Apache-2.0.txt',
  'tool/check_workspace.dart',
  'tool/src/workspace_contract.dart',
  'tool/test/workspace_contract_test.dart',
};

const _expectedWorkspaceMembers = <String>{
  'packages/provider',
  'packages/provider_utils',
  'packages/ai',
  'packages/openai',
  'packages/openai_compatible',
  'packages/anthropic',
};

const _expectedRepository = 'https://github.com/pigcode/ai';
const _expectedIssueTracker = 'https://github.com/pigcode/ai/issues';

final class WorkspaceViolation {
  const WorkspaceViolation(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

List<WorkspaceViolation> validateWorkspace(
  Directory root,
  Set<String> trackedPaths,
) {
  final violations = <WorkspaceViolation>[];

  _validateTrackedPaths(root, trackedPaths, violations);
  _validatePackageDirectories(root, violations);
  _validateRootManifest(root, trackedPaths, violations);

  for (final entry in _expectedPackages.entries) {
    _validatePackage(
      root,
      trackedPaths,
      directoryName: entry.key,
      packageName: entry.value,
      violations: violations,
    );
  }
  _validateAllPubspecDependencies(root, trackedPaths, violations);

  return violations;
}

void _validateTrackedPaths(
  Directory root,
  Set<String> trackedPaths,
  List<WorkspaceViolation> violations,
) {
  final sortedPaths = trackedPaths.toList()..sort();
  for (final path in sortedPaths) {
    if (!_isAllowedTrackedPath(path)) {
      violations.add(
        WorkspaceViolation(
          'unexpected_tracked_path',
          'Tracked path is outside the public workspace allowlist: $path',
        ),
      );
    }
  }

  final requiredPaths = _requiredRootPaths.toList()..sort();
  for (final path in requiredPaths) {
    if (!_isTrackedFile(root, trackedPaths, path)) {
      violations.add(
        WorkspaceViolation(
          'missing_required_path',
          'Required tracked workspace file is missing: $path',
        ),
      );
    }
  }
}

bool _isAllowedTrackedPath(String path) =>
    _requiredRootPaths.contains(path) ||
    path.startsWith('.github/') ||
    path.startsWith('packages/');

void _validatePackageDirectories(
  Directory root,
  List<WorkspaceViolation> violations,
) {
  final packagesDirectory = _directory(root, 'packages');
  final actualDirectories = packagesDirectory.existsSync()
      ? packagesDirectory
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map((directory) => directory.uri.pathSegments
              .where((segment) => segment.isNotEmpty)
              .last)
          .toSet()
      : <String>{};
  final expectedDirectories = _expectedPackages.keys.toSet();

  final missing = expectedDirectories.difference(actualDirectories).toList()
    ..sort();
  for (final directoryName in missing) {
    violations.add(
      WorkspaceViolation(
        'missing_package_directory',
        'Required package directory is missing: packages/$directoryName',
      ),
    );
  }

  final unexpected = actualDirectories.difference(expectedDirectories).toList()
    ..sort();
  for (final directoryName in unexpected) {
    violations.add(
      WorkspaceViolation(
        'unexpected_package_directory',
        'Unexpected package directory: packages/$directoryName',
      ),
    );
  }
}

void _validateRootManifest(
  Directory root,
  Set<String> trackedPaths,
  List<WorkspaceViolation> violations,
) {
  const path = 'pubspec.yaml';
  if (!_isTrackedFile(root, trackedPaths, path)) {
    return;
  }

  final contents = _file(root, path).readAsStringSync();
  _expectScalar(
    contents,
    key: 'name',
    expected: 'pigcode_ai_workspace',
    path: path,
    code: 'invalid_root_name',
    violations: violations,
  );
  _expectScalar(
    contents,
    key: 'publish_to',
    expected: 'none',
    path: path,
    code: 'invalid_root_publish_to',
    violations: violations,
  );

  final sdk = _nestedScalar(contents, parentKey: 'environment', key: 'sdk');
  if (sdk != '^3.6.0') {
    violations.add(
      WorkspaceViolation(
        'invalid_root_sdk',
        'Expected environment sdk ^3.6.0 in $path, found ${sdk ?? 'missing'}',
      ),
    );
  }

  final workspaceMembers = _topLevelSequence(contents, 'workspace');
  if (workspaceMembers == null ||
      workspaceMembers.length != _expectedWorkspaceMembers.length ||
      workspaceMembers.toSet().length != workspaceMembers.length ||
      workspaceMembers
          .toSet()
          .difference(_expectedWorkspaceMembers)
          .isNotEmpty ||
      _expectedWorkspaceMembers
          .difference(workspaceMembers.toSet())
          .isNotEmpty) {
    violations.add(
      const WorkspaceViolation(
        'invalid_workspace_membership',
        'Expected exactly the six public package paths in pubspec.yaml workspace',
      ),
    );
  }
}

void _validatePackage(
  Directory root,
  Set<String> trackedPaths, {
  required String directoryName,
  required String packageName,
  required List<WorkspaceViolation> violations,
}) {
  final packagePath = 'packages/$directoryName';
  final manifestPath = '$packagePath/pubspec.yaml';
  if (!_isTrackedFile(root, trackedPaths, manifestPath)) {
    violations.add(
      WorkspaceViolation(
        'missing_package_manifest',
        'Required package manifest is missing: $manifestPath',
      ),
    );
  } else {
    final contents = _file(root, manifestPath).readAsStringSync();
    _expectScalar(
      contents,
      key: 'name',
      expected: packageName,
      path: manifestPath,
      code: 'invalid_package_name',
      violations: violations,
    );
    _expectScalar(
      contents,
      key: 'version',
      expected: '0.0.1',
      path: manifestPath,
      code: 'invalid_package_version',
      violations: violations,
    );
    _expectScalar(
      contents,
      key: 'publish_to',
      expected: 'none',
      path: manifestPath,
      code: 'invalid_package_publish_to',
      violations: violations,
    );
    _expectScalar(
      contents,
      key: 'resolution',
      expected: 'workspace',
      path: manifestPath,
      code: 'invalid_package_resolution',
      violations: violations,
    );
    _expectScalar(
      contents,
      key: 'repository',
      expected: _expectedRepository,
      path: manifestPath,
      code: 'invalid_package_repository',
      violations: violations,
    );
    _expectScalar(
      contents,
      key: 'issue_tracker',
      expected: _expectedIssueTracker,
      path: manifestPath,
      code: 'invalid_package_issue_tracker',
      violations: violations,
    );
  }

  _expectPackageFile(
    root,
    trackedPaths,
    path: '$packagePath/README.md',
    code: 'missing_package_readme',
    violations: violations,
  );
  _expectPackageFile(
    root,
    trackedPaths,
    path: '$packagePath/CHANGELOG.md',
    code: 'missing_package_changelog',
    violations: violations,
  );
  _expectPackageFile(
    root,
    trackedPaths,
    path: '$packagePath/lib/$packageName.dart',
    code: 'missing_package_barrel',
    violations: violations,
  );
}

void _validateAllPubspecDependencies(
  Directory root,
  Set<String> trackedPaths,
  List<WorkspaceViolation> violations,
) {
  final manifestPaths = trackedPaths
      .where((path) => path == 'pubspec.yaml' || path.endsWith('/pubspec.yaml'))
      .toList()
    ..sort();
  for (final path in manifestPaths) {
    final manifest = _file(root, path);
    if (manifest.existsSync()) {
      _validateDependencySources(
        manifest.readAsStringSync(),
        path,
        violations,
      );
    }
  }
}

void _expectPackageFile(
  Directory root,
  Set<String> trackedPaths, {
  required String path,
  required String code,
  required List<WorkspaceViolation> violations,
}) {
  if (!_isTrackedFile(root, trackedPaths, path)) {
    violations.add(
      WorkspaceViolation(
          code, 'Required tracked package file is missing: $path'),
    );
  }
}

void _expectScalar(
  String contents, {
  required String key,
  required String expected,
  required String path,
  required String code,
  required List<WorkspaceViolation> violations,
}) {
  final actual = _topLevelScalar(contents, key);
  if (actual != expected) {
    violations.add(
      WorkspaceViolation(
        code,
        'Expected $key: $expected in $path, found ${actual ?? 'missing'}',
      ),
    );
  }
}

void _validateDependencySources(
  String contents,
  String path,
  List<WorkspaceViolation> violations,
) {
  final sources = _dependencySources(contents);
  if (sources.contains('path')) {
    violations.add(
      WorkspaceViolation(
        'path_dependency',
        'Path dependencies are not allowed in $path',
      ),
    );
  }
  if (sources.contains('git')) {
    violations.add(
      WorkspaceViolation(
        'git_dependency',
        'Git dependencies are not allowed in $path',
      ),
    );
  }
}

Set<String> _dependencySources(String contents) {
  const dependencySections = <String>{
    'dependencies',
    'dev_dependencies',
    'dependency_overrides',
  };
  final sources = <String>{};
  final lines = contents.split('\n');

  for (var index = 0; index < lines.length; index += 1) {
    final header = _parsedLine(lines[index]);
    if (header == null ||
        header.indent != 0 ||
        !dependencySections.contains(header.key)) {
      continue;
    }
    if (header.value.isNotEmpty) {
      sources.addAll(_inlineDependencySources(header.value));
      continue;
    }

    final block = <_YamlLine>[];
    for (index += 1; index < lines.length; index += 1) {
      final line = _parsedLine(lines[index]);
      if (line == null) {
        continue;
      }
      if (line.indent == 0) {
        index -= 1;
        break;
      }
      block.add(line);
    }

    if (block.isEmpty) {
      continue;
    }
    final dependencyIndent = block
        .map((line) => line.indent)
        .reduce((left, right) => left < right ? left : right);

    for (final line in block) {
      if (line.indent > dependencyIndent &&
          (line.key == 'path' || line.key == 'git')) {
        sources.add(line.key);
      }
      sources.addAll(_inlineDependencySources(line.value));
    }
  }

  return sources;
}

Set<String> _inlineDependencySources(String value) {
  final sources = <String>{};
  final matches = RegExp(
    r'''(?:^|[{,])\s*(?:"([^"]+)"|'([^']+)'|([A-Za-z0-9_-]+))\s*:''',
  ).allMatches(value);
  for (final match in matches) {
    final key = match.group(1) ?? match.group(2) ?? match.group(3);
    if (key == 'path' || key == 'git') {
      sources.add(key!);
    }
  }
  return sources;
}

String? _topLevelScalar(String contents, String key) {
  for (final sourceLine in contents.split('\n')) {
    final line = _parsedLine(sourceLine);
    if (line != null && line.indent == 0 && line.key == key) {
      return line.value.isEmpty ? null : _unquote(line.value);
    }
  }
  return null;
}

String? _nestedScalar(
  String contents, {
  required String parentKey,
  required String key,
}) {
  final lines = contents.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final parent = _parsedLine(lines[index]);
    if (parent == null ||
        parent.indent != 0 ||
        parent.key != parentKey ||
        parent.value.isNotEmpty) {
      continue;
    }
    for (index += 1; index < lines.length; index += 1) {
      final line = _parsedLine(lines[index]);
      if (line == null) {
        continue;
      }
      if (line.indent == 0) {
        return null;
      }
      if (line.key == key) {
        return line.value.isEmpty ? null : _unquote(line.value);
      }
    }
  }
  return null;
}

List<String>? _topLevelSequence(String contents, String key) {
  final lines = contents.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final line = _parsedLine(lines[index]);
    if (line == null || line.indent != 0 || line.key != key) {
      continue;
    }

    if (line.value.startsWith('[') && line.value.endsWith(']')) {
      final inner = line.value.substring(1, line.value.length - 1).trim();
      if (inner.isEmpty) {
        return <String>[];
      }
      return inner.split(',').map((value) => _unquote(value.trim())).toList();
    }
    if (line.value.isNotEmpty) {
      return null;
    }

    final values = <String>[];
    for (index += 1; index < lines.length; index += 1) {
      final sourceLine = _stripYamlComment(lines[index]);
      if (sourceLine.trim().isEmpty) {
        continue;
      }
      final indent = _indentOf(sourceLine);
      if (indent == 0) {
        break;
      }
      final trimmed = sourceLine.trim();
      if (!trimmed.startsWith('-')) {
        return null;
      }
      final value = trimmed.substring(1).trim();
      if (value.isEmpty) {
        return null;
      }
      values.add(_unquote(value));
    }
    return values;
  }
  return null;
}

_YamlLine? _parsedLine(String sourceLine) {
  final withoutComment = _stripYamlComment(sourceLine);
  if (withoutComment.trim().isEmpty) {
    return null;
  }
  final indent = _indentOf(withoutComment);
  final trimmed = withoutComment.trim();
  final match = RegExp(
    r'''^(?:"([^"]+)"|'([^']+)'|([A-Za-z0-9_-]+))\s*:\s*(.*)$''',
  ).firstMatch(trimmed);
  if (match == null) {
    return null;
  }
  return _YamlLine(
    indent,
    match.group(1) ?? match.group(2) ?? match.group(3)!,
    match.group(4)!.trim(),
  );
}

String _stripYamlComment(String line) {
  var inSingleQuote = false;
  var inDoubleQuote = false;
  for (var index = 0; index < line.length; index += 1) {
    final character = line[index];
    if (character == "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
    } else if (character == '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
    } else if (character == '#' && !inSingleQuote && !inDoubleQuote) {
      return line.substring(0, index);
    }
  }
  return line;
}

int _indentOf(String line) {
  var indent = 0;
  while (indent < line.length && line[indent] == ' ') {
    indent += 1;
  }
  return indent;
}

String _unquote(String value) {
  if (value.length >= 2 &&
      ((value.startsWith("'") && value.endsWith("'")) ||
          (value.startsWith('"') && value.endsWith('"')))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

bool _isTrackedFile(
  Directory root,
  Set<String> trackedPaths,
  String path,
) =>
    trackedPaths.contains(path) && _file(root, path).existsSync();

File _file(Directory root, String path) => File.fromUri(root.uri.resolve(path));

Directory _directory(Directory root, String path) =>
    Directory.fromUri(root.uri.resolve('$path/'));

final class _YamlLine {
  const _YamlLine(this.indent, this.key, this.value);

  final int indent;
  final String key;
  final String value;
}
