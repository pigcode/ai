/// VM-only adapters for caller-owned MCP IO resources.
///
/// This entrypoint does not spawn, kill, or restart processes.
library;

export 'src/io/platform.dart';
export 'src/io/http_server_adapter.dart';
export 'src/io/process_adapter.dart';
export 'src/io/stdio_transport.dart';
