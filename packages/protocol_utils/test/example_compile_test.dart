import 'package:test/test.dart';

import '../example/json_rpc_peer.dart' as example;

void main() {
  test('JSON-RPC peer example runs without external IO', () async {
    await example.main();
  });
}
