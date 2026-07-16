import 'dart:io';

import 'package:yaml/yaml.dart';

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

const _dependencySections = <String>{
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
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
  final manifests = _loadTrackedManifests(root, trackedPaths, violations);
  _validateRootManifest(manifests['pubspec.yaml'], violations);

  for (final entry in _expectedPackages.entries) {
    _validatePackage(
      root,
      trackedPaths,
      manifests,
      directoryName: entry.key,
      packageName: entry.value,
      violations: violations,
    );
  }

  _validateDependencySources(manifests, violations);
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
    final state = _trackedFileState(root, trackedPaths, path);
    if (state == _TrackedFileState.missing) {
      violations.add(
        WorkspaceViolation(
          'missing_required_path',
          'Required tracked workspace file is missing: $path',
        ),
      );
    } else if (state == _TrackedFileState.nonRegular) {
      _addNonRegularTrackedPath(path, violations);
    }
  }
}

bool _isAllowedTrackedPath(String path) {
  if (!_isCanonicalTrackedPath(path)) {
    return false;
  }
  return _requiredRootPaths.contains(path) ||
      path.startsWith('.github/') ||
      path.startsWith('packages/');
}

bool _isCanonicalTrackedPath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.endsWith('/') ||
      path.contains(r'\')) {
    return false;
  }
  return path.split('/').every(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      );
}

void _validatePackageDirectories(
  Directory root,
  List<WorkspaceViolation> violations,
) {
  final packagesPath = _appendPathComponent(root.absolute.path, 'packages');
  final packagesType = FileSystemEntity.typeSync(
    packagesPath,
    followLinks: false,
  );
  final actualDirectories = packagesType == FileSystemEntityType.directory
      ? Directory(packagesPath)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map(
            (directory) => directory.path.split(Platform.pathSeparator).last,
          )
          .toSet()
      : <String>{};
  if (packagesType != FileSystemEntityType.directory &&
      packagesType != FileSystemEntityType.notFound) {
    _addNonRegularTrackedPath('packages', violations);
  }

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

Map<String, YamlMap> _loadTrackedManifests(
  Directory root,
  Set<String> trackedPaths,
  List<WorkspaceViolation> violations,
) {
  final manifests = <String, YamlMap>{};
  final manifestPaths = trackedPaths
      .where(
        (path) =>
            _isAllowedTrackedPath(path) &&
            (path == 'pubspec.yaml' || path.endsWith('/pubspec.yaml')),
      )
      .toList()
    ..sort();

  for (final path in manifestPaths) {
    final state = _trackedFileState(root, trackedPaths, path);
    if (state == _TrackedFileState.nonRegular) {
      _addNonRegularTrackedPath(path, violations);
      continue;
    }
    if (state == _TrackedFileState.missing) {
      continue;
    }

    final contents = _containedFile(root, path).readAsStringSync();
    try {
      final Object? document = loadYaml(contents);
      if (document is YamlMap) {
        manifests[path] = document;
      } else {
        _addInvalidYaml(path, violations);
      }
    } on YamlException {
      _addInvalidYaml(path, violations);
    }
  }

  return manifests;
}

void _addInvalidYaml(
  String path,
  List<WorkspaceViolation> violations,
) {
  _addViolationOnce(
    violations,
    WorkspaceViolation(
      'invalid_yaml',
      'Expected a valid YAML mapping in $path',
    ),
  );
}

void _validateRootManifest(
  YamlMap? manifest,
  List<WorkspaceViolation> violations,
) {
  if (manifest == null) {
    return;
  }

  _expectScalar(
    manifest,
    key: 'name',
    expected: 'pigcode_ai_workspace',
    path: 'pubspec.yaml',
    code: 'invalid_root_name',
    violations: violations,
  );
  _expectScalar(
    manifest,
    key: 'publish_to',
    expected: 'none',
    path: 'pubspec.yaml',
    code: 'invalid_root_publish_to',
    violations: violations,
  );

  final environment = manifest['environment'];
  final Object? sdk = environment is YamlMap ? environment['sdk'] : null;
  if (sdk != '^3.6.0') {
    violations.add(
      WorkspaceViolation(
        'invalid_root_sdk',
        'Expected environment sdk ^3.6.0 in pubspec.yaml, '
            'found ${sdk ?? 'missing'}',
      ),
    );
  }

  final workspaceMembers = _stringList(manifest['workspace']);
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

List<String>? _stringList(Object? value) {
  if (value is! YamlList) {
    return null;
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String) {
      return null;
    }
    result.add(item);
  }
  return result;
}

void _validatePackage(
  Directory root,
  Set<String> trackedPaths,
  Map<String, YamlMap> manifests, {
  required String directoryName,
  required String packageName,
  required List<WorkspaceViolation> violations,
}) {
  final packagePath = 'packages/$directoryName';
  final manifestPath = '$packagePath/pubspec.yaml';
  final manifestState = _trackedFileState(root, trackedPaths, manifestPath);
  if (manifestState == _TrackedFileState.missing) {
    violations.add(
      WorkspaceViolation(
        'missing_package_manifest',
        'Required package manifest is missing: $manifestPath',
      ),
    );
  } else if (manifestState == _TrackedFileState.nonRegular) {
    _addNonRegularTrackedPath(manifestPath, violations);
  } else {
    final manifest = manifests[manifestPath];
    if (manifest != null) {
      _validatePackageScalars(
        manifest,
        manifestPath,
        packageName,
        violations,
      );
    }
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

void _validatePackageScalars(
  YamlMap manifest,
  String manifestPath,
  String packageName,
  List<WorkspaceViolation> violations,
) {
  _expectScalar(
    manifest,
    key: 'name',
    expected: packageName,
    path: manifestPath,
    code: 'invalid_package_name',
    violations: violations,
  );
  _expectScalar(
    manifest,
    key: 'version',
    expected: '0.0.1',
    path: manifestPath,
    code: 'invalid_package_version',
    violations: violations,
  );
  _expectScalar(
    manifest,
    key: 'publish_to',
    expected: 'none',
    path: manifestPath,
    code: 'invalid_package_publish_to',
    violations: violations,
  );
  _expectScalar(
    manifest,
    key: 'resolution',
    expected: 'workspace',
    path: manifestPath,
    code: 'invalid_package_resolution',
    violations: violations,
  );
  _expectScalar(
    manifest,
    key: 'repository',
    expected: _expectedRepository,
    path: manifestPath,
    code: 'invalid_package_repository',
    violations: violations,
  );
  _expectScalar(
    manifest,
    key: 'issue_tracker',
    expected: _expectedIssueTracker,
    path: manifestPath,
    code: 'invalid_package_issue_tracker',
    violations: violations,
  );
}

void _expectScalar(
  YamlMap manifest, {
  required String key,
  required String expected,
  required String path,
  required String code,
  required List<WorkspaceViolation> violations,
}) {
  final Object? actual = manifest[key];
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
  Map<String, YamlMap> manifests,
  List<WorkspaceViolation> violations,
) {
  for (final manifestEntry in manifests.entries) {
    var hasPathDependency = false;
    var hasGitDependency = false;

    for (final sectionName in _dependencySections) {
      final Object? section = manifestEntry.value[sectionName];
      if (section == null) {
        continue;
      }
      if (section is! YamlMap) {
        _addViolationOnce(
          violations,
          WorkspaceViolation(
            'invalid_dependency_section',
            'Expected $sectionName to be a map in ${manifestEntry.key}',
          ),
        );
        continue;
      }

      for (final dependency in section.values) {
        if (dependency is! YamlMap) {
          continue;
        }
        hasPathDependency = hasPathDependency || dependency.containsKey('path');
        hasGitDependency = hasGitDependency || dependency.containsKey('git');
      }
    }

    if (hasPathDependency) {
      violations.add(
        WorkspaceViolation(
          'path_dependency',
          'Path dependencies are not allowed in ${manifestEntry.key}',
        ),
      );
    }
    if (hasGitDependency) {
      violations.add(
        WorkspaceViolation(
          'git_dependency',
          'Git dependencies are not allowed in ${manifestEntry.key}',
        ),
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
  final state = _trackedFileState(root, trackedPaths, path);
  if (state == _TrackedFileState.missing) {
    violations.add(
      WorkspaceViolation(
        code,
        'Required tracked package file is missing: $path',
      ),
    );
  } else if (state == _TrackedFileState.nonRegular) {
    _addNonRegularTrackedPath(path, violations);
  }
}

void _addNonRegularTrackedPath(
  String path,
  List<WorkspaceViolation> violations,
) {
  _addViolationOnce(
    violations,
    WorkspaceViolation(
      'non_regular_tracked_path',
      'Tracked path is not a regular file within the workspace root: $path',
    ),
  );
}

void _addViolationOnce(
  List<WorkspaceViolation> violations,
  WorkspaceViolation violation,
) {
  if (violations.any(
    (existing) =>
        existing.code == violation.code &&
        existing.message == violation.message,
  )) {
    return;
  }
  violations.add(violation);
}

_TrackedFileState _trackedFileState(
  Directory root,
  Set<String> trackedPaths,
  String path,
) {
  if (!trackedPaths.contains(path)) {
    return _TrackedFileState.missing;
  }
  if (!_isAllowedTrackedPath(path)) {
    return _TrackedFileState.nonRegular;
  }

  var currentPath = root.absolute.path;
  final segments = path.split('/');
  for (var index = 0; index < segments.length; index += 1) {
    currentPath = _appendPathComponent(currentPath, segments[index]);
    final type = FileSystemEntity.typeSync(currentPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return _TrackedFileState.missing;
    }
    final isLast = index == segments.length - 1;
    if (isLast) {
      return type == FileSystemEntityType.file
          ? _TrackedFileState.regular
          : _TrackedFileState.nonRegular;
    }
    if (type != FileSystemEntityType.directory) {
      return _TrackedFileState.nonRegular;
    }
  }
  return _TrackedFileState.nonRegular;
}

File _containedFile(Directory root, String path) {
  if (!_isAllowedTrackedPath(path)) {
    throw ArgumentError.value(path, 'path', 'Path is outside the allowlist');
  }
  var absolutePath = root.absolute.path;
  for (final segment in path.split('/')) {
    absolutePath = _appendPathComponent(absolutePath, segment);
  }
  return File(absolutePath);
}

String _appendPathComponent(String parent, String component) =>
    parent.endsWith(Platform.pathSeparator)
        ? '$parent$component'
        : '$parent${Platform.pathSeparator}$component';

enum _TrackedFileState { regular, missing, nonRegular }
