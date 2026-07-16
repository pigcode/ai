import 'dart:io';

import 'src/workspace_contract.dart';

void main() {
  final root = Directory.current.absolute;
  final gitResult = Process.runSync(
    'git',
    const <String>['ls-files', '-z'],
    workingDirectory: root.path,
  );
  if (gitResult.exitCode != 0) {
    stderr.writeln('Unable to read tracked workspace paths from Git.');
    final details = (gitResult.stderr as String).trim();
    if (details.isNotEmpty) {
      stderr.writeln(details);
    }
    exitCode = 1;
    return;
  }

  final trackedPaths = (gitResult.stdout as String)
      .split('\u0000')
      .where((path) => path.isNotEmpty)
      .toSet();
  final violations = validateWorkspace(root, trackedPaths)
    ..sort((left, right) {
      final codeComparison = left.code.compareTo(right.code);
      return codeComparison != 0
          ? codeComparison
          : left.message.compareTo(right.message);
    });

  if (violations.isNotEmpty) {
    for (final violation in violations) {
      stderr.writeln(violation);
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Workspace contract is satisfied.');
}
