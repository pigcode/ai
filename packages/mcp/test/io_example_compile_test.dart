import 'package:test/test.dart';

import '../example/stdio_io.dart' as stdio;
import '../example/streamable_http_io.dart' as http;

void main() {
  test('VM-only examples expose caller-owned adapter functions', () {
    expect(stdio.connectCallerOwnedProcess, isA<Function>());
    expect(http.adaptCallerOwnedServer, isA<Function>());
    expect(http.forwardCallerOwnedRequest, isA<Function>());
  });
}
