import 'dart:io';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp_io.dart';

/// Adapts a process that the application has already started and still owns.
McpProcessStdioChannel connectCallerOwnedProcess(Process process) =>
    McpProcessStdioChannel(process: process);

void main() {}
