import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';

typedef LspRequestHandler = FutureOr<JsonValue> Function(JsonValue params);

/// Caller-owned reverse-request handler registry.
final class LspHandlerRegistry {
  final Map<String, LspRequestHandler> _handlers =
      <String, LspRequestHandler>{};

  void register(String method, LspRequestHandler handler) {
    if (_handlers.containsKey(method)) {
      throw LspHandlerException(
        'lsp_handler_duplicate',
        'LSP reverse-request handler is already registered.',
        method: method,
      );
    }
    _handlers[method] = handler;
  }

  void unregister(String method) {
    if (_handlers.remove(method) == null) {
      throw LspHandlerException(
        'lsp_handler_unknown',
        'LSP reverse-request handler is not registered.',
        method: method,
      );
    }
  }

  FutureOr<JsonValue> dispatch(String method, JsonValue params) {
    final handler = _handlers[method];
    if (handler == null) {
      throw LspHandlerException(
        'lsp_handler_missing',
        'No caller handler accepts this LSP reverse request.',
        method: method,
      );
    }
    return handler(freezeJsonValue(params));
  }
}
