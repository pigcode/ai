import 'dart:io';

import '../src/workspace_contract.dart';

typedef _TestBody = void Function();

const _packageNames = <String, String>{
  'provider': 'pigcode_ai_provider',
  'provider_utils': 'pigcode_ai_provider_utils',
  'ai': 'pigcode_ai',
  'openai': 'pigcode_ai_openai',
  'openai_compatible': 'pigcode_ai_openai_compatible',
  'anthropic': 'pigcode_ai_anthropic',
};

void main() {
  final tests = <String, _TestBody>{
    'safe fixture passes': () {
      _withFixture((fixture) {
        final violations = validateWorkspace(
          fixture.root,
          fixture.trackedPaths,
        );

        _expect(
          violations.isEmpty,
          'Expected no violations, got ${_describe(violations)}',
        );
      });
    },
    'rejects an unexpected tracked root path': () {
      _withFixture((fixture) {
        fixture.writeTracked('notes.txt', 'private notes\n');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'unexpected_tracked_path',
          messageFragment: 'notes.txt',
        );
      });
    },
    'requires the Phase 1 compatibility tooling': () {
      _withFixture((fixture) {
        fixture.removeTracked('tool/fixtures/ai_core_peer.dart');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_required_path',
          messageFragment: 'tool/fixtures/ai_core_peer.dart',
        );
      });
    },
    'rejects non-canonical tracked paths before applying the allowlist': () {
      _withFixture((fixture) {
        const unsafePaths = <String>{
          '',
          '/packages/ai/pubspec.yaml',
          'packages/ai/',
          r'packages\ai\pubspec.yaml',
          'packages//ai/pubspec.yaml',
          'packages/./ai/pubspec.yaml',
          'packages/../notes.txt',
          '.github/../notes.txt',
        };
        fixture.trackedPaths.addAll(unsafePaths);

        final unexpectedPathViolations = validateWorkspace(
          fixture.root,
          fixture.trackedPaths,
        ).where((violation) => violation.code == 'unexpected_tracked_path');

        _expect(
          unexpectedPathViolations.length == unsafePaths.length,
          'Expected every non-canonical path to be rejected, got '
          '${unexpectedPathViolations.length} of ${unsafePaths.length}: '
          '${unexpectedPathViolations.map((violation) => violation.message).join('; ')}',
        );
      });
    },
    'does not read an absolute tracked pubspec outside the root': () {
      final outsideDirectory = Directory.systemTemp.createTempSync(
        'workspace_contract_outside_',
      );
      try {
        final outsideManifest = File.fromUri(
          outsideDirectory.uri.resolve('pubspec.yaml'),
        )..writeAsStringSync('''
dependencies:
  local_package:
    path: ../local_package
''');

        _withFixture((fixture) {
          fixture.trackedPaths.add(outsideManifest.absolute.path);

          final violations = validateWorkspace(
            fixture.root,
            fixture.trackedPaths,
          );

          _expect(
            violations.length == 1 &&
                violations.single.code == 'unexpected_tracked_path' &&
                violations.single.message.contains(
                  outsideManifest.absolute.path,
                ),
            'Expected only an unexpected path violation, got '
            '${_describe(violations)}',
          );
        });
      } finally {
        outsideDirectory.deleteSync(recursive: true);
      }
    },
    'rejects a required manifest symlink outside the root': () {
      final outsideDirectory = Directory.systemTemp.createTempSync(
        'workspace_contract_outside_',
      );
      try {
        final outsideManifest = File.fromUri(
          outsideDirectory.uri.resolve('pubspec.yaml'),
        )..writeAsStringSync(_packageManifest('pigcode_ai_provider'));

        _withFixture((fixture) {
          const manifestPath = 'packages/provider/pubspec.yaml';
          fixture.replaceWithSymlink(manifestPath, outsideManifest.path);

          _expectViolation(
            validateWorkspace(fixture.root, fixture.trackedPaths),
            code: 'non_regular_tracked_path',
            messageFragment: manifestPath,
          );
        });
      } finally {
        outsideDirectory.deleteSync(recursive: true);
      }
    },
    'fails closed when a tracked manifest is not UTF-8': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/provider/pubspec.yaml';
        fixture.writeTrackedBytes(manifestPath, const <int>[0xff]);

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_yaml',
          messageFragment: manifestPath,
        );
      });
    },
    'rejects credential patterns in ordinary tracked files': () {
      _withFixture((fixture) {
        final credentialSamples = <String, String>{
          'private_key': <String>['-----BEGIN ', 'PRIVATE KEY-----'].join(),
          'github_pat': <String>[
            'github',
            '_pat_',
            'aaaaaaaaaaaaaaaaaaaa',
          ].join(),
          'github_token': <String>[
            'gh',
            'p_',
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234',
          ].join(),
          'anthropic': <String>[
            'sk',
            '-ant-',
            'abcdefghijklmnopqrst',
          ].join(),
          'openai': <String>[
            'sk',
            '-',
            'abcdefghijklmnopqrstuvwx',
          ].join(),
          'aws': <String>['AK', 'IA', 'ABCDEFGHIJKLMNOP'].join(),
        };

        for (final entry in credentialSamples.entries) {
          fixture.writeTracked(
            'packages/ai/lib/src/${entry.key}.dart',
            "const credential = '${entry.value}';\n",
          );
        }

        final violations = validateWorkspace(
          fixture.root,
          fixture.trackedPaths,
        );
        for (final name in credentialSamples.keys) {
          _expectViolation(
            violations,
            code: 'possible_secret',
            messageFragment: 'packages/ai/lib/src/$name.dart',
          );
        }
      });
    },
    'rejects ordinary tracked symlinks without reading targets': () {
      final outsideDirectory = Directory.systemTemp.createTempSync(
        'workspace_contract_outside_',
      );
      try {
        final outsideFile = File.fromUri(
          outsideDirectory.uri.resolve('source.dart'),
        )..writeAsStringSync(
            "const credential = '${<String>[
              'sk',
              '-',
              'abcdefghijklmnopqrstuvwx'
            ].join()}';\n",
          );

        _withFixture((fixture) {
          const sourcePath = 'packages/ai/lib/src/source.dart';
          fixture
            ..writeTracked(sourcePath, 'const safe = true;\n')
            ..replaceWithSymlink(sourcePath, outsideFile.path);

          final violations = validateWorkspace(
            fixture.root,
            fixture.trackedPaths,
          );
          _expectViolation(
            violations,
            code: 'non_regular_tracked_path',
            messageFragment: sourcePath,
          );
          _expect(
            !violations.any(
              (violation) =>
                  violation.code == 'possible_secret' &&
                  violation.message.contains(sourcePath),
            ),
            'Expected the symlink target not to be read, got '
            '${_describe(violations)}',
          );
        });
      } finally {
        outsideDirectory.deleteSync(recursive: true);
      }
    },
    'rejects an ordinary tracked file missing from the worktree': () {
      _withFixture((fixture) {
        const sourcePath = 'packages/ai/lib/src/source.dart';
        fixture
          ..writeTracked(sourcePath, 'const safe = true;\n')
          ..removeFileKeepingTracked(sourcePath);

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_tracked_path',
          messageFragment: sourcePath,
        );
      });
    },
    'reports a missing package directory': () {
      _withFixture((fixture) {
        fixture.removeDirectory('packages/provider');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_package_directory',
          messageFragment: 'packages/provider',
        );
      });
    },
    'reports an extra package directory': () {
      _withFixture((fixture) {
        fixture.writeTracked('packages/extra/README.md', '# Extra\n');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'unexpected_package_directory',
          messageFragment: 'packages/extra',
        );
      });
    },
    'rejects a wrong package name': () {
      _withFixture((fixture) {
        fixture.replaceIn(
          'packages/provider/pubspec.yaml',
          'name: pigcode_ai_provider',
          'name: wrong_name',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_package_name',
          messageFragment: 'packages/provider/pubspec.yaml',
        );
      });
    },
    'reports a missing package README': () {
      _withFixture((fixture) {
        fixture.removeTracked('packages/ai/README.md');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_package_readme',
          messageFragment: 'packages/ai/README.md',
        );
      });
    },
    'reports a missing package changelog': () {
      _withFixture((fixture) {
        fixture.removeTracked('packages/openai/CHANGELOG.md');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_package_changelog',
          messageFragment: 'packages/openai/CHANGELOG.md',
        );
      });
    },
    'reports a missing package barrel': () {
      _withFixture((fixture) {
        fixture.removeTracked(
          'packages/anthropic/lib/pigcode_ai_anthropic.dart',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_package_barrel',
          messageFragment: 'packages/anthropic/lib/pigcode_ai_anthropic.dart',
        );
      });
    },
    'rejects a wrong package repository': () {
      _withFixture((fixture) {
        fixture.replaceIn(
          'packages/openai/pubspec.yaml',
          'repository: https://github.com/pigcode/ai',
          'repository: https://example.invalid/ai',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_package_repository',
          messageFragment: 'packages/openai/pubspec.yaml',
        );
      });
    },
    'rejects a wrong package issue tracker': () {
      _withFixture((fixture) {
        fixture.replaceIn(
          'packages/openai_compatible/pubspec.yaml',
          'issue_tracker: https://github.com/pigcode/ai/issues',
          'issue_tracker: https://example.invalid/issues',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_package_issue_tracker',
          messageFragment: 'packages/openai_compatible/pubspec.yaml',
        );
      });
    },
    'rejects wrong root workspace membership': () {
      _withFixture((fixture) {
        fixture.replaceIn(
          'pubspec.yaml',
          '  - packages/anthropic\n',
          '',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_workspace_membership',
          messageFragment: 'pubspec.yaml',
        );
      });
    },
    'rejects a path dependency in a dependency block': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/ai/pubspec.yaml',
          '''
dependencies:
  local_package:
    path: ../local_package
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'path_dependency',
          messageFragment: 'packages/ai/pubspec.yaml',
        );
      });
    },
    'rejects a git dependency in a dependency block': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/provider_utils/pubspec.yaml',
          '''
dev_dependencies:
  remote_package:
    git:
      url: https://example.invalid/remote.git
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'git_dependency',
          messageFragment: 'packages/provider_utils/pubspec.yaml',
        );
      });
    },
    'rejects an escaped path source key in a dependency block': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/ai/pubspec.yaml',
          r'''
dependencies:
  local_package:
    "pa\u0074h": ../local_package
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'path_dependency',
          messageFragment: 'packages/ai/pubspec.yaml',
        );
      });
    },
    'rejects an escaped git source key in a flow mapping': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          r'''dependencies: {remote_package: {"g\u0069t": https://example.invalid/remote.git}}
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'git_dependency',
          messageFragment: manifestPath,
        );
      });
    },
    'checks inline sources in every tracked pubspec': () {
      _withFixture((fixture) {
        fixture.writeTracked(
          'packages/ai/example/pubspec.yaml',
          'dependencies: {local_package: {path: ../local_package}}\n',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'path_dependency',
          messageFragment: 'packages/ai/example/pubspec.yaml',
        );
      });
    },
    'rejects a path source in a multiline flow mapping': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          '''
dependencies: {
  local_package: {
    path: ../local_package
  }
}
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'path_dependency',
          messageFragment: manifestPath,
        );
      });
    },
    'rejects a git source in a multiline flow mapping': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          '''
dependencies: {
  remote_package: {
    git: https://example.invalid/remote.git
  }
}
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'git_dependency',
          messageFragment: manifestPath,
        );
      });
    },
    'fails closed on an unclosed flow dependency mapping': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          '''
dependencies: {
  local_package: {
    hosted: https://example.invalid
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_yaml',
          messageFragment: manifestPath,
        );
      });
    },
    'fails closed when a dependency section is not a map': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          'dependencies: [local_package]\n',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_dependency_section',
          messageFragment: manifestPath,
        );
      });
    },
    'fails closed when a dependency entry is a collection': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          '''
dependencies:
  foo:
    - path: ../local
''',
        );

        final violations = validateWorkspace(
          fixture.root,
          fixture.trackedPaths,
        );
        _expectViolation(
          violations,
          code: 'invalid_dependency_entry',
          messageFragment: manifestPath,
        );
        _expectViolation(
          violations,
          code: 'invalid_dependency_entry',
          messageFragment: 'foo',
        );
      });
    },
    'allows path and git as inline dependency package names': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          'dependencies: {path: ^1.9.0, git: ^2.3.0}\n',
        );

        final sourceViolations = validateWorkspace(
          fixture.root,
          fixture.trackedPaths,
        ).where(
          (violation) =>
              (violation.code == 'path_dependency' ||
                  violation.code == 'git_dependency') &&
              violation.message.contains(manifestPath),
        );

        _expect(
          sourceViolations.isEmpty,
          'Expected legal dependency package names, got '
          '${sourceViolations.map((violation) => violation.message).join('; ')}',
        );
      });
    },
  };

  var failures = 0;
  for (final entry in tests.entries) {
    try {
      entry.value();
      stdout.writeln('PASS ${entry.key}');
    } on Object catch (error, stackTrace) {
      failures += 1;
      stderr.writeln('FAIL ${entry.key}: $error');
      stderr.writeln(stackTrace);
    }
  }

  if (failures > 0) {
    stderr.writeln('$failures test(s) failed.');
    exitCode = 1;
  }
}

void _withFixture(void Function(_WorkspaceFixture fixture) body) {
  final fixture = _WorkspaceFixture.create();
  try {
    body(fixture);
  } finally {
    fixture.dispose();
  }
}

void _expectViolation(
  List<WorkspaceViolation> violations, {
  required String code,
  required String messageFragment,
}) {
  final found = violations.any(
    (violation) =>
        violation.code == code && violation.message.contains(messageFragment),
  );
  _expect(
    found,
    'Expected $code containing "$messageFragment", got '
    '${_describe(violations)}',
  );
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

String _describe(List<WorkspaceViolation> violations) => violations
    .map((violation) => '${violation.code}: ${violation.message}')
    .join('; ');

final class _WorkspaceFixture {
  _WorkspaceFixture._(this.root);

  final Directory root;
  final Set<String> trackedPaths = <String>{};

  static _WorkspaceFixture create() {
    final fixture = _WorkspaceFixture._(
      Directory.systemTemp.createTempSync('workspace_contract_test_'),
    );

    fixture
      ..writeTracked('.gitignore', '.dart_tool/\n')
      ..writeTracked('CHANGELOG.md', '# Changelog\n')
      ..writeTracked('LICENSE', 'License text\n')
      ..writeTracked('README.md', '# Pigcode AI\n')
      ..writeTracked('THIRD_PARTY_NOTICES.md', '# Third-party notices\n')
      ..writeTracked(
        'compatibility/schema/ai-core-compatibility.schema.json',
        '{}\n',
      )
      ..writeTracked(
        'compatibility/upstream/vercel-ai-7.0.35-paths.json',
        '{}\n',
      )
      ..writeTracked('third_party/licenses/Apache-2.0.txt', 'Apache 2.0\n')
      ..writeTracked(
        'tool/check_compatibility.dart',
        '// Compatibility CLI fixture\n',
      )
      ..writeTracked('tool/check_workspace.dart', '// CLI fixture\n')
      ..writeTracked(
        'tool/fixtures/ai_core_peer.dart',
        '// Peer fixture\n',
      )
      ..writeTracked(
        'tool/generate_upstream_path_inventory.dart',
        '// Inventory generator fixture\n',
      )
      ..writeTracked(
        'tool/src/compatibility_manifest.dart',
        '// Compatibility contract fixture\n',
      )
      ..writeTracked(
        'tool/src/workspace_contract.dart',
        '// Contract fixture\n',
      )
      ..writeTracked(
        'tool/test/ai_core_peer_test.dart',
        '// Peer test fixture\n',
      )
      ..writeTracked(
        'tool/test/compatibility_manifest_test.dart',
        '// Compatibility test fixture\n',
      )
      ..writeTracked(
        'tool/test/workspace_contract_test.dart',
        '// Test fixture\n',
      )
      ..writeTracked('.github/workflows/ci.yaml', 'name: CI\n')
      ..writeTracked('pubspec.yaml', _rootManifest());

    for (final entry in _packageNames.entries) {
      final packagePath = 'packages/${entry.key}';
      fixture
        ..writeTracked('$packagePath/README.md', '# ${entry.value}\n')
        ..writeTracked('$packagePath/CHANGELOG.md', '# Changelog\n')
        ..writeTracked(
          '$packagePath/lib/${entry.value}.dart',
          'library;\n',
        )
        ..writeTracked(
          '$packagePath/pubspec.yaml',
          _packageManifest(entry.value),
        );
    }

    return fixture;
  }

  void writeTracked(String path, String contents) {
    final file = _file(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    trackedPaths.add(path);
  }

  void writeTrackedBytes(String path, List<int> bytes) {
    final file = _file(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    trackedPaths.add(path);
  }

  void appendTo(String path, String contents) {
    _file(path).writeAsStringSync(contents, mode: FileMode.append);
  }

  void replaceIn(String path, String from, String to) {
    final file = _file(path);
    final contents = file.readAsStringSync();
    _expect(contents.contains(from), 'Fixture text not found in $path: $from');
    file.writeAsStringSync(contents.replaceFirst(from, to));
  }

  void replaceWithSymlink(String path, String target) {
    final file = _file(path);
    file.deleteSync();
    Link(file.path).createSync(target);
  }

  void removeTracked(String path) {
    final file = _file(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
    trackedPaths.remove(path);
  }

  void removeFileKeepingTracked(String path) {
    _file(path).deleteSync();
  }

  void removeDirectory(String path) {
    final directory = _directory(path);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
    trackedPaths.removeWhere(
      (trackedPath) => trackedPath == path || trackedPath.startsWith('$path/'),
    );
  }

  void dispose() {
    root.deleteSync(recursive: true);
  }

  File _file(String path) => File.fromUri(root.uri.resolve(path));

  Directory _directory(String path) =>
      Directory.fromUri(root.uri.resolve('$path/'));
}

String _rootManifest() => '''
name: pigcode_ai_workspace
publish_to: none

environment:
  sdk: ^3.6.0

workspace:
  - packages/provider
  - packages/provider_utils
  - packages/ai
  - packages/openai
  - packages/openai_compatible
  - packages/anthropic
''';

String _packageManifest(String name) => '''
name: $name
version: 0.0.1
publish_to: none

environment:
  sdk: ^3.6.0

resolution: workspace
repository: https://github.com/pigcode/ai
issue_tracker: https://github.com/pigcode/ai/issues
''';
