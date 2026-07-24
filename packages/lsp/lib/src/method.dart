import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'generated/lsp_inventory.g.dart';

/// LSP JSON-RPC method family.
enum LspMethodKind {
  request,
  notification,
}

/// Direction declared by the LSP meta-model.
enum LspMessageDirection {
  clientToServer,
  serverToClient,
  both,
}

/// Participant that sent a decoded LSP message.
enum LspMessageSender {
  client,
  server,
}

/// Exact schema bindings for one pinned LSP method.
final class LspMethodDescriptor {
  const LspMethodDescriptor({
    required this.method,
    required this.kind,
    required this.direction,
    required this.serverCapability,
    required this.paramsType,
    required this.resultType,
  });

  final String method;
  final LspMethodKind kind;
  final LspMessageDirection direction;
  final String? serverCapability;
  final JsonObject? paramsType;
  final JsonObject? resultType;
}

/// Every pinned LSP 3.18 method, sorted by wire method name.
final List<LspMethodDescriptor> lspMethodDescriptors =
    List<LspMethodDescriptor>.unmodifiable(
  lspGeneratedMethodMetadata.map((metadata) {
    final method = metadata['method'];
    final kind = metadata['kind'];
    final direction = metadata['direction'];
    if (method == null || kind == null || direction == null) {
      throw StateError('Generated LSP method metadata is incomplete.');
    }
    JsonObject? decodeType(String key) {
      final source = metadata[key];
      return source == null
          ? null
          : freezeJsonObject(
              jsonDecode(source) as Map<String, Object?>,
            );
    }

    return LspMethodDescriptor(
      method: method,
      kind: LspMethodKind.values.byName(kind),
      direction: LspMessageDirection.values.byName(direction),
      serverCapability: metadata['serverCapability'],
      paramsType: decodeType('params'),
      resultType: decodeType('result'),
    );
  }),
);

/// Exact method lookup by wire name.
final Map<String, LspMethodDescriptor> lspMethodsByName =
    Map<String, LspMethodDescriptor>.unmodifiable(
  <String, LspMethodDescriptor>{
    for (final descriptor in lspMethodDescriptors)
      descriptor.method: descriptor,
  },
);
