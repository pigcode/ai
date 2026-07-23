import 'package:test/test.dart';

import '../example/client_agent.dart' as example;

void main() {
  test('ACP client/agent example runs without external IO', () async {
    await example.main();
  });
}
