/// Portable protocol foundations shared by Pigcode ACP, MCP, LSP, and DAP
/// packages.
///
/// The default entrypoint never imports `dart:io` and never owns a process.
library;

export 'src/cancellation.dart';
export 'src/diagnostics.dart';
export 'src/errors.dart';
export 'src/framing/content_length.dart';
export 'src/framing/framer.dart';
export 'src/framing/ndjson.dart';
export 'src/framing/sse.dart';
export 'src/json_rpc/codec.dart';
export 'src/json_rpc/id.dart';
export 'src/json_rpc/message.dart';
export 'src/json_rpc/peer.dart';
export 'src/json_value.dart';
export 'src/limits.dart';
export 'src/transport.dart';
export 'src/version.dart';
