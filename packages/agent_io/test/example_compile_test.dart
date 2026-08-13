import 'dart:io';

import 'package:test/test.dart';

import '../example/durable_store.dart' as example;
import '../example/sandboxed_process.dart' as sandbox_example;

void main() {
  test(
    'durable Store example restricts a permissive temporary root',
    () {
      final root =
          Directory.systemTemp.createTempSync('store-example-permissions-');
      try {
        final permissive = Process.runSync('chmod', <String>['755', root.path]);
        expect(permissive.exitCode, 0);

        example.makeStoreRootPrivate(root);

        expect(FileStat.statSync(root.path).mode & 0x1ff, 0x1c0);
      } finally {
        root.deleteSync(recursive: true);
      }
    },
    skip: Platform.isWindows
        ? 'SKIP-MANIFEST store-permissions platform=windows chmod=unsupported'
        : false,
  );

  test('durable Store example writes, snapshots, and reopens', () async {
    await example.main();
  });

  test('sandbox example probes, executes, and confirms cleanup', () async {
    await sandbox_example.main();
  });
}
