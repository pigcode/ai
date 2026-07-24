import 'dart:io';

import 'package:test/test.dart';

import '../example/durable_store.dart' as example;

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
    skip: Platform.isWindows,
  );

  test('durable Store example writes, snapshots, and reopens', () async {
    await example.main();
  });
}
