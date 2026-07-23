import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'models.dart';
import 'schema.dart';
import 'version.dart';

final class McpCodec {
  const McpCodec._();

  static const McpCodec instance = McpCodec._();
  static const JsonRpcCodec _jsonRpc = JsonRpcCodec();

  McpDecodedMessage decodeClientRequest(String source) => _decodeCall(
        source,
        role: McpMessageRole.clientRequest,
        sender: McpParticipant.client,
        notification: false,
      );

  McpDecodedMessage decodeServerRequest(String source) => _decodeCall(
        source,
        role: McpMessageRole.serverRequest,
        sender: McpParticipant.server,
        notification: false,
      );

  McpDecodedMessage decodeClientNotification(String source) => _decodeCall(
        source,
        role: McpMessageRole.clientNotification,
        sender: McpParticipant.client,
        notification: true,
      );

  McpDecodedMessage decodeServerNotification(String source) => _decodeCall(
        source,
        role: McpMessageRole.serverNotification,
        sender: McpParticipant.server,
        notification: true,
      );

  McpDecodedMessage decodeClientResult(
    String source, {
    required String responseMethod,
  }) =>
      _decodeResult(
        source,
        role: McpMessageRole.clientResult,
        requestSender: McpParticipant.server,
        responseMethod: responseMethod,
      );

  McpDecodedMessage decodeServerResult(
    String source, {
    required String responseMethod,
  }) =>
      _decodeResult(
        source,
        role: McpMessageRole.serverResult,
        requestSender: McpParticipant.client,
        responseMethod: responseMethod,
      );

  String encode(McpDecodedMessage message) => _jsonRpc.encode(message.message);

  McpDecodedMessage _decodeCall(
    String source, {
    required McpMessageRole role,
    required McpParticipant sender,
    required bool notification,
  }) {
    final message = _decodeEnvelope(source);
    final method = switch (message) {
      JsonRpcRequest(:final method) when !notification => method,
      JsonRpcNotification(:final method) when notification => method,
      _ => throw const McpCodecException(
          'mcp_wrong_message_kind',
          'MCP message does not match the requested role kind.',
        ),
    };
    final binding = _binding(
      method,
      sender: sender,
      notification: notification,
    );
    try {
      McpSchema.instance.validateDefinition(
        'JSONRPCMessage',
        message.toJson(),
      );
      McpSchema.instance.validateRole(
        _roleName(role),
        message.toJson(),
      );
    } on McpSchemaException catch (error) {
      throw McpCodecException(
        'mcp_schema_invalid',
        'Message does not satisfy the pinned MCP role schema.',
        method: method,
        cause: error,
      );
    }
    if (method == 'initialize') {
      final params = (message as JsonRpcRequest).params! as JsonObject;
      if (params['protocolVersion'] != mcpProtocolVersion) {
        throw McpCodecException(
          'mcp_protocol_version_mismatch',
          'MCP initialize must request exact version $mcpProtocolVersion.',
          method: method,
        );
      }
    }
    return McpDecodedMessage(
      role: role,
      message: message,
      methodBinding: binding,
    );
  }

  McpDecodedMessage _decodeResult(
    String source, {
    required McpMessageRole role,
    required McpParticipant requestSender,
    required String responseMethod,
  }) {
    final message = _decodeEnvelope(source);
    if (message is! JsonRpcSuccessResponse &&
        message is! JsonRpcErrorResponse) {
      throw const McpCodecException(
        'mcp_wrong_message_kind',
        'MCP result role requires a JSON-RPC response.',
      );
    }
    final binding = _binding(
      responseMethod,
      sender: requestSender,
      notification: false,
    );
    try {
      McpSchema.instance.validateDefinition(
        'JSONRPCMessage',
        message.toJson(),
      );
      if (message case JsonRpcSuccessResponse(:final result)) {
        McpSchema.instance.validateRole(_roleName(role), result);
        McpSchema.instance.validateDefinition(
          binding.resultDefinition!,
          result,
        );
      }
    } on McpSchemaException catch (error) {
      throw McpCodecException(
        'mcp_schema_invalid',
        'Response does not satisfy the pinned MCP result schema.',
        method: responseMethod,
        cause: error,
      );
    }
    return McpDecodedMessage(
      role: role,
      message: message,
      methodBinding: binding,
    );
  }

  JsonRpcMessage _decodeEnvelope(String source) {
    try {
      return _jsonRpc.decode(source);
    } on JsonRpcException catch (error) {
      throw McpCodecException(
        'mcp_json_rpc_invalid',
        'Message is not a supported JSON-RPC 2.0 envelope.',
        cause: error,
      );
    }
  }

  McpMethodBinding _binding(
    String method, {
    required McpParticipant sender,
    required bool notification,
  }) {
    final candidates = mcpMethodBindingsByName[method];
    if (candidates == null) {
      throw McpCodecException(
        'mcp_unknown_stable_method',
        'Method is not part of MCP 2025-11-25.',
        method: method,
      );
    }
    for (final candidate in candidates) {
      if (candidate.sender == sender &&
          candidate.isNotification == notification) {
        return candidate;
      }
    }
    throw McpCodecException(
      'mcp_wrong_role',
      'MCP method is not valid for this sender role.',
      method: method,
    );
  }
}

String _roleName(McpMessageRole role) => switch (role) {
      McpMessageRole.clientRequest => 'ClientRequest',
      McpMessageRole.serverRequest => 'ServerRequest',
      McpMessageRole.clientNotification => 'ClientNotification',
      McpMessageRole.serverNotification => 'ServerNotification',
      McpMessageRole.clientResult => 'ClientResult',
      McpMessageRole.serverResult => 'ServerResult',
    };
