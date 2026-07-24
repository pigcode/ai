import 'dart:io';

void main() {
  final root = Directory.current.absolute;
  final paths = <String>[];
  for (final directoryPath in const <String>['packages', 'tool']) {
    final directory = Directory.fromUri(root.uri.resolve('$directoryPath/'));
    for (final entity
        in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final relative = entity.path.substring(root.path.length + 1);
      if (relative.startsWith('tool/upstream/') ||
          relative.startsWith('tool/conformance/')) {
        continue;
      }
      paths.add(relative);
    }
  }
  paths.sort();
  if (paths.isEmpty) {
    throw StateError('No maintained Dart sources were found.');
  }

  final result = Process.runSync(
    Platform.resolvedExecutable,
    <String>[
      'format',
      '--output=none',
      '--set-exit-if-changed',
      ...paths,
    ],
    workingDirectory: root.path,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    exitCode = result.exitCode;
    return;
  }
  stdout.writeln(
    'Maintained Dart sources are formatted; pinned upstream files were '
    'left byte-exact.',
  );
}
