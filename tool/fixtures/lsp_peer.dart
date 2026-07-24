import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('The fixed LSP peer accepts no arguments.');
    exitCode = 64;
    return;
  }
  final framer = ContentLengthFramer();
  try {
    await for (final chunk in stdin) {
      for (final body in framer.add(chunk)) {
        final message = const JsonRpcCodec().decode(utf8.decode(body));
        switch (message) {
          case JsonRpcRequest(:final id, :final method):
            final result = switch (method) {
              'initialize' => const <String, Object?>{
                  'capabilities': <String, Object?>{
                    'hoverProvider': true,
                    'textDocumentSync': 2,
                  },
                  'serverInfo': <String, Object?>{
                    'name': 'pigcode-fixed-lsp-peer',
                    'version': '1.0.0',
                  },
                },
              'shutdown' => null,
              _ => throw StateError('Unexpected LSP request: $method'),
            };
            _send(
              JsonRpcSuccessResponse(id: id, result: result),
            );
          case JsonRpcNotification(:final method):
            if (method == 'exit') {
              return;
            }
          case JsonRpcSuccessResponse() || JsonRpcErrorResponse():
            throw StateError('Fixed LSP peer does not issue requests.');
        }
      }
    }
    framer.close();
  } on Object catch (error, stackTrace) {
    stderr
      ..writeln('Fixed LSP peer failed: ${error.runtimeType}')
      ..writeln(stackTrace);
    exitCode = 1;
  }
}

void _send(JsonRpcMessage message) {
  final body = utf8.encode(const JsonRpcCodec().encode(message));
  stdout.add(<int>[
    ...ascii.encode('Content-Length: ${body.length}\r\n\r\n'),
    ...body,
  ]);
}
