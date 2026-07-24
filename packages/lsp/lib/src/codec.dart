import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'method.dart';
import 'models.dart';

/// One JSON-RPC and pinned LSP method validated wire message.
final class LspDecodedMessage {
  const LspDecodedMessage({
    required this.sender,
    required this.message,
    required this.methodDescriptor,
  });

  final LspMessageSender sender;
  final JsonRpcMessage message;
  final LspMethodDescriptor methodDescriptor;

  JsonObject toJson() => message.toJson();
}

/// Strict common-envelope plus LSP 3.18 method codec.
final class LspCodec {
  const LspCodec._();

  static const LspCodec instance = LspCodec._();
  static const JsonRpcCodec _jsonRpc = JsonRpcCodec();

  LspDecodedMessage decode(
    String source, {
    required LspMessageSender sender,
    String? responseMethod,
  }) {
    late final JsonRpcMessage message;
    try {
      message = _jsonRpc.decode(source);
    } on JsonRpcException catch (error) {
      throw LspCodecException(
        'lsp_json_rpc_invalid',
        'Message is not a supported JSON-RPC 2.0 envelope.',
        cause: error,
      );
    }

    final method = switch (message) {
      JsonRpcRequest(:final method) => method,
      JsonRpcNotification(:final method) => method,
      JsonRpcSuccessResponse() || JsonRpcErrorResponse() => responseMethod,
    };
    if (method == null) {
      throw const LspCodecException(
        'lsp_response_method_required',
        'LSP responses require their correlated request method.',
      );
    }
    final descriptor = lspMethodsByName[method];
    if (descriptor == null) {
      throw LspCodecException(
        'lsp_unknown_method',
        'Method is not part of the pinned LSP 3.18 inventory.',
        method: method,
      );
    }
    _validateKind(message, descriptor);
    _validateDirection(message, descriptor, sender);
    try {
      _validatePayload(message, descriptor);
    } on LspSchemaException catch (error) {
      throw LspCodecException(
        'lsp_schema_invalid',
        'Message does not satisfy the pinned LSP 3.18 meta-model.',
        method: method,
        cause: error,
      );
    }
    return LspDecodedMessage(
      sender: sender,
      message: message,
      methodDescriptor: descriptor,
    );
  }

  String encode(LspDecodedMessage message) => _jsonRpc.encode(message.message);

  void _validateKind(
    JsonRpcMessage message,
    LspMethodDescriptor descriptor,
  ) {
    final valid = switch (message) {
      JsonRpcRequest() ||
      JsonRpcSuccessResponse() ||
      JsonRpcErrorResponse() =>
        descriptor.kind == LspMethodKind.request,
      JsonRpcNotification() => descriptor.kind == LspMethodKind.notification,
    };
    if (!valid) {
      throw LspCodecException(
        'lsp_wrong_message_kind',
        'LSP method is not valid for this JSON-RPC message kind.',
        method: descriptor.method,
      );
    }
  }

  void _validateDirection(
    JsonRpcMessage message,
    LspMethodDescriptor descriptor,
    LspMessageSender sender,
  ) {
    final requestSender = switch (descriptor.direction) {
      LspMessageDirection.clientToServer => LspMessageSender.client,
      LspMessageDirection.serverToClient => LspMessageSender.server,
      LspMessageDirection.both => null,
    };
    final expected = switch (message) {
      JsonRpcRequest() || JsonRpcNotification() => requestSender,
      JsonRpcSuccessResponse() ||
      JsonRpcErrorResponse() =>
        requestSender == null
            ? null
            : requestSender == LspMessageSender.client
                ? LspMessageSender.server
                : LspMessageSender.client,
    };
    if (expected != null && sender != expected) {
      throw LspCodecException(
        'lsp_wrong_direction',
        'LSP method is not valid for this sender direction.',
        method: descriptor.method,
      );
    }
  }

  void _validatePayload(
    JsonRpcMessage message,
    LspMethodDescriptor descriptor,
  ) {
    switch (message) {
      case JsonRpcRequest(:final params) || JsonRpcNotification(:final params):
        final type = descriptor.paramsType;
        if (type != null) {
          LspModelRegistry.instance.validateType(
            type,
            params ?? const <String, Object?>{},
            context: '${descriptor.method} params',
          );
        } else if (params != null) {
          throw LspSchemaException(
            'lsp_unexpected_params',
            'This LSP method does not declare params.',
            definition: descriptor.method,
          );
        }
      case JsonRpcSuccessResponse(:final result):
        LspModelRegistry.instance.validateType(
          descriptor.resultType!,
          result,
          context: '${descriptor.method} result',
        );
      case JsonRpcErrorResponse():
      // JSON-RPC validation is sufficient for correlated error responses.
    }
  }
}
