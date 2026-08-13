import 'dart:io';

Future<void> main() async {
  stdout.writeln('DART_MAIN_REACHED');
  for (final path in const <String>[
    '/proc/self/status',
    '/proc/cpuinfo',
  ]) {
    try {
      await File(path).readAsBytes();
    } on FileSystemException {
      continue;
    }
    stderr.writeln('unexpected procfs read: $path');
    exit(78);
  }
  stdout.writeln('NON_REQUIRED_PROCFS_DENIED');
}
