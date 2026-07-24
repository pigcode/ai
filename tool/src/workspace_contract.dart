import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const _expectedPackages = <String, String>{
  'provider': 'pigcode_ai_provider',
  'provider_utils': 'pigcode_ai_provider_utils',
  'ai': 'pigcode_ai',
  'openai': 'pigcode_ai_openai',
  'openai_compatible': 'pigcode_ai_openai_compatible',
  'anthropic': 'pigcode_ai_anthropic',
  'protocol_utils': 'pigcode_ai_protocol_utils',
  'acp': 'pigcode_ai_acp',
  'mcp': 'pigcode_ai_mcp',
  'agent_kernel': 'pigcode_ai_agent_kernel',
  'agent_io': 'pigcode_ai_agent_io',
};

const _requiredRootPaths = <String>{
  '.gitignore',
  'CHANGELOG.md',
  'LICENSE',
  'README.md',
  'THIRD_PARTY_NOTICES.md',
  'compatibility/phase-2a-protocol-foundation.json',
  'compatibility/phase-3-kernel-store.json',
  'compatibility/schema/ai-core-compatibility.schema.json',
  'compatibility/schema/kernel-store-compatibility.schema.json',
  'compatibility/schema/protocol-foundation-compatibility.schema.json',
  'compatibility/upstream/phase-2a-protocol-inventory.json',
  'compatibility/upstream/vercel-ai-7.0.35-paths.json',
  'compatibility/vercel-ai-7.0.35.json',
  'docs/protocol-support.md',
  'docs/kernel-store-support.md',
  'pubspec.yaml',
  'third_party/licenses/Apache-2.0.txt',
  'tool/check_compatibility.dart',
  'tool/check_agent_kernel_schema.dart',
  'tool/check_kernel_store_compatibility.dart',
  'tool/check_protocol_compatibility.dart',
  'tool/check_workspace.dart',
  'tool/conformance/mcp/package-lock.json',
  'tool/conformance/mcp/package.json',
  'tool/protocol_codegen.dart',
  'tool/run_acp_peer_matrix.dart',
  'tool/run_agent_store_crash_matrix.dart',
  'tool/run_mcp_conformance.dart',
  'tool/fixtures/acp_peer.dart',
  'tool/fixtures/acp/rust/README.md',
  'tool/fixtures/acp/typescript/README.md',
  'tool/fixtures/acp/typescript/agent.mjs',
  'tool/fixtures/acp/typescript/package-lock.json',
  'tool/fixtures/acp/typescript/package.json',
  'tool/fixtures/ai_core_peer.dart',
  'tool/fixtures/agent_store_crash_writer.dart',
  'tool/fixtures/agent_store_writer.dart',
  'tool/fixtures/anthropic_peer.dart',
  'tool/fixtures/mcp_conformance_client.dart',
  'tool/fixtures/mcp_conformance_server.dart',
  'tool/fixtures/mcp_stdio_peer.dart',
  'tool/fixtures/openai_compatible_peer.dart',
  'tool/fixtures/openai_peer.dart',
  'tool/generate_upstream_path_inventory.dart',
  'tool/src/acp_peer_harness.dart',
  'tool/src/agent_kernel_schema.dart',
  'tool/src/agent_store_crash_harness.dart',
  'tool/src/agent_store_writer_fixture.dart',
  'tool/src/compatibility_manifest.dart',
  'tool/src/kernel_store_compatibility_manifest.dart',
  'tool/src/protocol_compatibility_manifest.dart',
  'tool/src/protocol_codegen.dart',
  'tool/src/protocol_inventory.dart',
  'tool/src/protocol_sources.dart',
  'tool/src/workspace_contract.dart',
  'tool/test/ai_core_cross_process_test.dart',
  'tool/test/ai_core_cross_scripted_peer_test.dart',
  'tool/test/ai_core_peer_test.dart',
  'tool/test/agent_kernel_schema_test.dart',
  'tool/test/agent_kernel_secret_scan_test.dart',
  'tool/test/agent_store_crash_matrix_test.dart',
  'tool/test/agent_store_multi_process_test.dart',
  'tool/test/acp_cross_process_test.dart',
  'tool/test/compatibility_manifest_test.dart',
  'tool/test/kernel_store_compatibility_manifest_test.dart',
  'tool/test/kernel_store_fixture_coverage_test.dart',
  'tool/test/mcp_conformance_inventory_test.dart',
  'tool/test/mcp_stdio_cross_process_test.dart',
  'tool/test/protocol_codegen_test.dart',
  'tool/test/protocol_compatibility_manifest_test.dart',
  'tool/test/protocol_fixture_coverage_test.dart',
  'tool/test/protocol_inventory_test.dart',
  'tool/test/protocol_sources_test.dart',
  'tool/test/workspace_contract_test.dart',
  'tool/upstream/protocols/acp/LICENSE',
  'tool/upstream/protocols/acp/schema-v1.20.0/meta.json',
  'tool/upstream/protocols/acp/schema-v1.20.0/schema.json',
  'tool/upstream/protocols/mcp-conformance/LICENSE',
  'tool/upstream/protocols/mcp-conformance/v0.1.16/package.json',
  'tool/upstream/protocols/mcp-conformance/v0.1.16/scenarios.json',
  'tool/upstream/protocols/mcp/2025-11-25/schema.json',
  'tool/upstream/protocols/mcp/LICENSE',
  'tool/upstream/protocols/sources.json',
  'tool/schema/agent_kernel/agent-event-v1.schema.json',
  'tool/schema/agent_kernel/store-transaction-v1.schema.json',
  'tool/schema/agent_kernel/snapshot-v1.schema.json',
  'tool/schema/agent_kernel/store-manifest-v1.schema.json',
  'tool/schema/agent_kernel/event-inventory-v1.json',
  'tool/fixtures/agent_kernel/schema/valid-event.json',
  'tool/fixtures/agent_kernel/schema/valid-root-manifest.json',
  'tool/fixtures/agent_kernel/schema/valid-session-manifest.json',
  'tool/fixtures/agent_kernel/schema/invalid-event-missing-id.json',
  'tool/fixtures/agent_kernel/schema/invalid-event-version.json',
  'packages/acp/lib/src/generated/acp_inventory.g.dart',
  'packages/acp/example/client_agent.dart',
  'packages/acp/test/example_compile_test.dart',
  'packages/mcp/lib/src/generated/mcp_inventory.g.dart',
  'packages/mcp/example/portable_client_server.dart',
  'packages/mcp/example/stdio_io.dart',
  'packages/mcp/example/streamable_http_io.dart',
  'packages/mcp/test/example_compile_test.dart',
  'packages/mcp/test/io_example_compile_test.dart',
  'packages/protocol_utils/example/json_rpc_peer.dart',
  'packages/protocol_utils/test/example_compile_test.dart',
  'packages/agent_kernel/example/session_run.dart',
  'packages/agent_kernel/test/example_compile_test.dart',
  'packages/agent_kernel/test/security/approval_principal_test.dart',
  'packages/agent_kernel/test/security/capability_no_escalation_test.dart',
  'packages/agent_kernel/test/security/secret_rejection_test.dart',
  'packages/agent_io/test/security/private_root_test.dart',
  'packages/agent_io/test/security/resource_limit_test.dart',
  'packages/agent_io/test/security/store_path_test.dart',
  'packages/agent_io/test/security/symlink_test.dart',
  'packages/agent_io/example/durable_store.dart',
  'packages/agent_io/test/example_compile_test.dart',
};

const _expectedWorkspaceMembers = <String>{
  'packages/provider',
  'packages/provider_utils',
  'packages/ai',
  'packages/openai',
  'packages/openai_compatible',
  'packages/anthropic',
  'packages/protocol_utils',
  'packages/acp',
  'packages/mcp',
  'packages/agent_kernel',
  'packages/agent_io',
};

const _allowedInternalDependencies = <String, Set<String>>{
  'pigcode_ai_provider': <String>{},
  'pigcode_ai_provider_utils': <String>{'pigcode_ai_provider'},
  'pigcode_ai': <String>{
    'pigcode_ai_provider',
    'pigcode_ai_provider_utils',
  },
  'pigcode_ai_openai': <String>{
    'pigcode_ai_provider',
    'pigcode_ai_provider_utils',
  },
  'pigcode_ai_openai_compatible': <String>{
    'pigcode_ai_provider',
    'pigcode_ai_provider_utils',
  },
  'pigcode_ai_anthropic': <String>{
    'pigcode_ai_provider',
    'pigcode_ai_provider_utils',
  },
  'pigcode_ai_protocol_utils': <String>{},
  'pigcode_ai_acp': <String>{'pigcode_ai_protocol_utils'},
  'pigcode_ai_mcp': <String>{
    'pigcode_ai_protocol_utils',
    'pigcode_ai_provider',
    'pigcode_ai',
  },
  'pigcode_ai_agent_kernel': <String>{},
  'pigcode_ai_agent_io': <String>{'pigcode_ai_agent_kernel'},
};

const _portableBarrels = <String>{
  'packages/provider/lib/pigcode_ai_provider.dart',
  'packages/provider_utils/lib/pigcode_ai_provider_utils.dart',
  'packages/ai/lib/pigcode_ai.dart',
  'packages/openai/lib/pigcode_ai_openai.dart',
  'packages/openai_compatible/lib/pigcode_ai_openai_compatible.dart',
  'packages/anthropic/lib/pigcode_ai_anthropic.dart',
  'packages/protocol_utils/lib/pigcode_ai_protocol_utils.dart',
  'packages/acp/lib/pigcode_ai_acp.dart',
  'packages/mcp/lib/pigcode_ai_mcp.dart',
  'packages/mcp/lib/pigcode_ai_mcp_http.dart',
  'packages/agent_kernel/lib/pigcode_ai_agent_kernel.dart',
};

const _dependencySections = <String>{
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
};

const _expectedRepository = 'https://github.com/pigcode/ai';
const _expectedIssueTracker = 'https://github.com/pigcode/ai/issues';

final _secretPatterns = <RegExp>[
  RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
  RegExp(r'github_pat_[A-Za-z0-9_]{20,}'),
  RegExp(r'gh[pousr]_[A-Za-z0-9]{30,}'),
  RegExp(r'sk-ant-[A-Za-z0-9_-]{20,}'),
  RegExp(r'sk-[A-Za-z0-9_-]{24,}'),
  RegExp(r'AKIA[0-9A-Z]{16}'),
];

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
  _validateTrackedFileContents(root, trackedPaths, violations);
  _validatePortableBarrels(root, trackedPaths, violations);
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
  _validateInternalDependencyDirection(manifests, violations);
  return violations;
}

void _validatePortableBarrels(
  Directory root,
  Set<String> trackedPaths,
  List<WorkspaceViolation> violations,
) {
  for (final barrelPath in _portableBarrels) {
    if (_trackedFileState(root, trackedPaths, barrelPath) !=
        _TrackedFileState.regular) {
      continue;
    }
    final contents = _containedFile(root, barrelPath).readAsStringSync();
    if (RegExp(r'''(?:import|export)\s+['"]dart:io['"]''').hasMatch(contents)) {
      violations.add(
        WorkspaceViolation(
          'portable_barrel_io_dependency',
          'Portable barrel imports or exports dart:io: $barrelPath',
        ),
      );
    }
    if (RegExp(r'''export\s+['"][^'"]*_io\.dart['"]''').hasMatch(contents)) {
      violations.add(
        WorkspaceViolation(
          'portable_barrel_reexports_io',
          'Portable barrel re-exports a VM-only IO entrypoint: $barrelPath',
        ),
      );
    }
  }
}

void _validateTrackedFileContents(
  Directory root,
  Set<String> trackedPaths,
  List<WorkspaceViolation> violations,
) {
  final paths = trackedPaths.where(_isAllowedTrackedPath).toList()..sort();
  for (final path in paths) {
    final state = _trackedFileState(root, trackedPaths, path);
    if (state == _TrackedFileState.missing) {
      violations.add(
        WorkspaceViolation(
          'missing_tracked_path',
          'Tracked file is missing from the workspace: $path',
        ),
      );
      continue;
    }
    if (state == _TrackedFileState.nonRegular) {
      _addNonRegularTrackedPath(path, violations);
      continue;
    }

    final contents = utf8.decode(
      _containedFile(root, path).readAsBytesSync(),
      allowMalformed: true,
    );
    if (_secretPatterns.any((pattern) => pattern.hasMatch(contents))) {
      violations.add(
        WorkspaceViolation(
          'possible_secret',
          'Possible credential pattern found in tracked file: $path',
        ),
      );
    }
  }
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

    final manifest = _readManifest(root, path, violations);
    if (manifest != null) {
      manifests[path] = manifest;
    }
  }

  return manifests;
}

YamlMap? _readManifest(
  Directory root,
  String path,
  List<WorkspaceViolation> violations,
) {
  try {
    final contents = _containedFile(root, path).readAsStringSync();
    final Object? document = loadYaml(contents);
    if (document is YamlMap) {
      return document;
    }
  } on YamlException {
    _addInvalidYaml(path, violations);
    return null;
  } on FileSystemException {
    _addInvalidYaml(path, violations);
    return null;
  } on FormatException {
    _addInvalidYaml(path, violations);
    return null;
  }

  _addInvalidYaml(path, violations);
  return null;
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
        'Expected exactly the eleven public package paths in pubspec.yaml workspace',
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

      for (final dependencyEntry in section.entries) {
        final dependency = dependencyEntry.value;
        if (dependency is YamlMap) {
          hasPathDependency =
              hasPathDependency || dependency.containsKey('path');
          hasGitDependency = hasGitDependency || dependency.containsKey('git');
          continue;
        }
        if (dependency is YamlList ||
            dependency is Map<Object?, Object?> ||
            dependency is List<Object?>) {
          _addViolationOnce(
            violations,
            WorkspaceViolation(
              'invalid_dependency_entry',
              'Expected dependency ${dependencyEntry.key} to be a scalar, '
                  'null, or map in ${manifestEntry.key}',
            ),
          );
        }
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

void _validateInternalDependencyDirection(
  Map<String, YamlMap> manifests,
  List<WorkspaceViolation> violations,
) {
  for (final manifestEntry in manifests.entries) {
    final packageName = manifestEntry.value['name'];
    if (packageName is! String ||
        !_allowedInternalDependencies.containsKey(packageName)) {
      continue;
    }
    final dependencies = manifestEntry.value['dependencies'];
    if (dependencies is! YamlMap) {
      continue;
    }
    final allowed = _allowedInternalDependencies[packageName]!;
    for (final dependencyName in dependencies.keys.whereType<String>()) {
      if (!_allowedInternalDependencies.containsKey(dependencyName) ||
          allowed.contains(dependencyName)) {
        continue;
      }
      violations.add(
        WorkspaceViolation(
          'forbidden_internal_dependency',
          'Forbidden internal dependency: $packageName -> $dependencyName',
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
