import 'package:test/test.dart';

import '../example/portable_client_server.dart' as example;

void main() {
  test('portable MCP client/server example runs without external IO', () async {
    await example.main();
  });
}
