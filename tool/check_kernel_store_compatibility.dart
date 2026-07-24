import 'dart:io';

import 'src/kernel_store_compatibility_manifest.dart';

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln(
      'Usage: dart run tool/check_kernel_store_compatibility.dart',
    );
    exitCode = 64;
    return;
  }
  final root = Directory.current.absolute;
  final violations = <KernelStoreCompatibilityViolation>[
    ...validateKernelStoreCompatibilityManifest(root: root),
    ...validateKernelStoreFixtureCoverage(root: root),
  ]..sort((left, right) {
      final code = left.code.compareTo(right.code);
      return code != 0 ? code : left.message.compareTo(right.message);
    });
  if (violations.isEmpty) {
    stdout.writeln('Phase 3 Kernel/Store compatibility manifest is valid.');
    return;
  }
  for (final violation in violations) {
    stderr.writeln(violation);
  }
  exitCode = 1;
}
