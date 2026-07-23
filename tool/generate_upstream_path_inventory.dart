import 'dart:convert';
import 'dart:io';

const _targetRepository = 'https://github.com/vercel/ai';
const _targetTag = 'ai@7.0.35';
const _targetCommit = '799faf71e05a7d580914ad94d943d28c0400554c';
const _outputPath = 'compatibility/upstream/vercel-ai-7.0.35-paths.json';

const _packages = <_PackagePin>[
  _PackagePin(
    dartPackage: 'pigcode_ai_provider',
    upstreamPackage: '@ai-sdk/provider',
    version: '4.0.3',
    tree: 'e317bb78b50fd0bdd6e0f6968246b3bc20835265',
    root: 'packages/provider',
  ),
  _PackagePin(
    dartPackage: 'pigcode_ai_provider_utils',
    upstreamPackage: '@ai-sdk/provider-utils',
    version: '5.0.12',
    tree: 'b14c493fddd3c9de574e794c5e688f417d55bb9f',
    root: 'packages/provider-utils',
  ),
  _PackagePin(
    dartPackage: 'pigcode_ai',
    upstreamPackage: 'ai',
    version: '7.0.35',
    tree: '4007b95ee6c90a1caa03b5f765886990f8526f38',
    root: 'packages/ai',
  ),
  _PackagePin(
    dartPackage: 'pigcode_ai_openai',
    upstreamPackage: '@ai-sdk/openai',
    version: '4.0.18',
    tree: '2166f24dcc1fc273374bad00c2d8f63910c1a7c7',
    root: 'packages/openai',
  ),
  _PackagePin(
    dartPackage: 'pigcode_ai_openai_compatible',
    upstreamPackage: '@ai-sdk/openai-compatible',
    version: '3.0.14',
    tree: 'daea26741bc9737bd0fe727c48f142b32346c8e8',
    root: 'packages/openai-compatible',
  ),
  _PackagePin(
    dartPackage: 'pigcode_ai_anthropic',
    upstreamPackage: '@ai-sdk/anthropic',
    version: '4.0.18',
    tree: '67d1d5804f178fb74f8ec7b49d9d82f2ce562f5c',
    root: 'packages/anthropic',
  ),
];

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/generate_upstream_path_inventory.dart '
      '/absolute/path/to/vercel-ai-checkout',
    );
    exitCode = 64;
    return;
  }
  final checkout = Directory(arguments.single).absolute;
  if (!checkout.existsSync()) {
    stderr.writeln('Upstream checkout does not exist: ${checkout.path}');
    exitCode = 66;
    return;
  }
  final head = _git(checkout, const <String>['rev-parse', 'HEAD']);
  if (head != _targetCommit) {
    stderr.writeln(
      'Expected upstream checkout HEAD $_targetCommit, found $head.',
    );
    exitCode = 65;
    return;
  }

  final packageRecords = <Map<String, Object?>>[];
  for (final package in _packages) {
    final treeLine = _git(
      checkout,
      <String>['ls-tree', _targetCommit, '--', package.root],
    );
    final match = RegExp(
      '^040000 tree ([a-f0-9]{40})\\t${RegExp.escape(package.root)}\$',
    ).firstMatch(treeLine);
    if (match?.group(1) != package.tree) {
      stderr.writeln(
        'Tree mismatch for ${package.root}: '
        'expected ${package.tree}, found ${match?.group(1) ?? treeLine}.',
      );
      exitCode = 65;
      return;
    }
    final paths = _git(
      checkout,
      <String>[
        'ls-tree',
        '-r',
        '--name-only',
        _targetCommit,
        '--',
        package.root,
      ],
    ).split('\n')
      ..removeWhere((path) => path.isEmpty)
      ..sort();
    if (paths.isEmpty || paths.toSet().length != paths.length) {
      stderr.writeln(
        'Path inventory for ${package.root} is empty or contains duplicates.',
      );
      exitCode = 65;
      return;
    }
    packageRecords.add(<String, Object?>{
      'dartPackage': package.dartPackage,
      'upstreamPackage': package.upstreamPackage,
      'packageVersion': package.version,
      'tree': package.tree,
      'root': package.root,
      'paths': paths,
    });
  }

  final output = File.fromUri(Directory.current.uri.resolve(_outputPath));
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'inventoryVersion': 1,
          'repository': _targetRepository,
          'tag': _targetTag,
          'commit': _targetCommit,
          'packages': packageRecords,
        })}\n',
  );
  stdout.writeln(
    'Wrote ${packageRecords.fold<int>(
      0,
      (count, package) => count + (package['paths'] as List).length,
    )} fixed upstream paths to ${output.path}.',
  );
}

String _git(Directory checkout, List<String> arguments) {
  final result = Process.runSync(
    'git',
    arguments,
    workingDirectory: checkout.path,
  );
  if (result.exitCode != 0) {
    stderr.writeln('git ${arguments.join(' ')} failed.');
    final details = (result.stderr as String).trim();
    if (details.isNotEmpty) {
      stderr.writeln(details);
    }
    exit(result.exitCode);
  }
  return (result.stdout as String).trim();
}

final class _PackagePin {
  const _PackagePin({
    required this.dartPackage,
    required this.upstreamPackage,
    required this.version,
    required this.tree,
    required this.root,
  });

  final String dartPackage;
  final String upstreamPackage;
  final String version;
  final String tree;
  final String root;
}
