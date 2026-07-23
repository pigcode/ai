import 'dart:io';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp_io.dart';
import 'package:test/test.dart';

void main() {
  test('IO barrel is an explicit VM-only entrypoint', () {
    expect(mcpIoOperatingSystem, Platform.operatingSystem);
  });
}
