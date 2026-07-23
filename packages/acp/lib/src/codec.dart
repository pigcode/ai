import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'models.dart';
import 'schema.dart';

/// Strict common-envelope plus ACP stable-v1 role codec.
final class AcpCodec {
  const AcpCodec._();

  static const AcpCodec instance = AcpCodec._();
  static const JsonRpcCodec _jsonRpc = JsonRpcCodec();

  AcpDecodedMessage decodeAgentMessage(
    String source, {
    String? responseMethod,
  }) =>
      _decode(
        source,
        root: AcpMessageRoot.agent,
        responseMethod: responseMethod,
      );

  AcpDecodedMessage decodeClientMessage(
    String source, {
    String? responseMethod,
  }) =>
      _decode(
        source,
        root: AcpMessageRoot.client,
        responseMethod: responseMethod,
      );

  AcpDecodedMessage decodeProtocolMessage(String source) => _decode(
        source,
        root: AcpMessageRoot.protocolLevel,
      );

  String encode(AcpDecodedMessage message) => _jsonRpc.encode(message.message);

  AcpDecodedMessage _decode(
    String source, {
    required AcpMessageRoot root,
    String? responseMethod,
  }) {
    late final JsonRpcMessage message;
    try {
      message = _jsonRpc.decode(source);
    } on JsonRpcException catch (error) {
      throw AcpCodecException(
        'acp_json_rpc_invalid',
        'Message is not a supported JSON-RPC 2.0 envelope.',
        cause: error,
      );
    }

    final descriptor = _validateMethodBinding(
      message,
      root: root,
      responseMethod: responseMethod,
    );
    try {
      AcpSchema.instance.validateRoot(_rootName(root), message.toJson());
      _validateMethodPayload(message, descriptor);
    } on AcpSchemaException catch (error) {
      throw AcpCodecException(
        'acp_schema_invalid',
        'Message does not satisfy the pinned ACP stable-v1 role schema.',
        method: descriptor?.method,
        cause: error,
      );
    }
    return AcpDecodedMessage(
      root: root,
      message: message,
      methodDescriptor: descriptor,
    );
  }

  AcpMethodDescriptor? _validateMethodBinding(
    JsonRpcMessage message, {
    required AcpMessageRoot root,
    String? responseMethod,
  }) {
    final method = switch (message) {
      JsonRpcRequest(:final method) => method,
      JsonRpcNotification(:final method) => method,
      _ => responseMethod,
    };
    if (method == null) {
      return null;
    }
    final descriptor = acpMethodsByName[method];
    if (descriptor == null) {
      throw AcpCodecException(
        'acp_unknown_stable_method',
        'Method is not part of the pinned ACP stable-v1 inventory.',
        method: method,
      );
    }
    final expectedRoot = switch (message) {
      JsonRpcRequest() ||
      JsonRpcNotification() =>
        _requestSenderRoot(descriptor.handlerSide),
      JsonRpcSuccessResponse() ||
      JsonRpcErrorResponse() =>
        _responseSenderRoot(descriptor.handlerSide),
    };
    if (root != expectedRoot) {
      throw AcpCodecException(
        'acp_wrong_role',
        'ACP method is not valid for this sender role.',
        method: method,
      );
    }
    if (message is JsonRpcRequest && descriptor.requestDefinition == null ||
        message is JsonRpcNotification &&
            descriptor.notificationDefinition == null ||
        message is JsonRpcSuccessResponse &&
            descriptor.responseDefinition == null) {
      throw AcpCodecException(
        'acp_wrong_message_kind',
        'ACP method is not valid for this JSON-RPC message kind.',
        method: method,
      );
    }
    return descriptor;
  }

  void _validateMethodPayload(
    JsonRpcMessage message,
    AcpMethodDescriptor? descriptor,
  ) {
    switch (message) {
      case JsonRpcRequest(:final params):
        if (descriptor != null) {
          AcpSchema.instance.validateDefinition(
            descriptor.requestDefinition!,
            params ?? const <String, Object?>{},
          );
        }
      case JsonRpcNotification(:final params):
        if (descriptor != null) {
          AcpSchema.instance.validateDefinition(
            descriptor.notificationDefinition!,
            params ?? const <String, Object?>{},
          );
        }
      case JsonRpcSuccessResponse(:final result):
        if (descriptor != null) {
          AcpSchema.instance.validateDefinition(
            descriptor.responseDefinition!,
            result,
          );
        }
      case JsonRpcErrorResponse(:final error):
        AcpSchema.instance.validateDefinition('Error', error.toJson());
    }
  }
}

String _rootName(AcpMessageRoot root) => switch (root) {
      AcpMessageRoot.agent => 'Agent',
      AcpMessageRoot.client => 'Client',
      AcpMessageRoot.protocolLevel => 'ProtocolLevel',
    };

AcpMessageRoot _requestSenderRoot(AcpMethodHandlerSide side) => switch (side) {
      AcpMethodHandlerSide.agent => AcpMessageRoot.client,
      AcpMethodHandlerSide.client => AcpMessageRoot.agent,
      AcpMethodHandlerSide.protocol => AcpMessageRoot.protocolLevel,
    };

AcpMessageRoot _responseSenderRoot(AcpMethodHandlerSide side) => switch (side) {
      AcpMethodHandlerSide.agent => AcpMessageRoot.agent,
      AcpMethodHandlerSide.client => AcpMessageRoot.client,
      AcpMethodHandlerSide.protocol => AcpMessageRoot.protocolLevel,
    };
