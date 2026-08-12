import 'dart:io';

String resolveTestWorkspacePath({
  required String packageRelative,
  required String workspaceRelative,
}) {
  for (final path in <String>[packageRelative, workspaceRelative]) {
    final file = File(path).absolute;
    if (file.existsSync()) return file.path;
  }
  throw StateError(
    'Test fixture is missing: $packageRelative or $workspaceRelative',
  );
}
