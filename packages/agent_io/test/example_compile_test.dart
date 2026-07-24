import 'package:test/test.dart';

import '../example/durable_store.dart' as example;

void main() {
  test('durable Store example writes, snapshots, and reopens', () async {
    await example.main();
  });
}
