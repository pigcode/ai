import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'method.dart';
import 'models.dart';

/// Typed, side-effect-free representation of a privileged reverse request.
sealed class LspProposal {
  const LspProposal({
    required this.method,
    required this.params,
  });

  final String method;
  final JsonObject params;

  JsonObject toJson() => params;
}

final class LspApplyEditProposal extends LspProposal {
  LspApplyEditProposal._(JsonObject params)
      : super(method: 'workspace/applyEdit', params: params);

  factory LspApplyEditProposal.fromParams(Map<String, Object?> params) {
    return LspApplyEditProposal._(
      _validateProposal('workspace/applyEdit', params),
    );
  }

  String? get label => params['label'] as String?;
  JsonObject get workspaceEdit => params['edit']! as JsonObject;
  List<JsonObject> get documentChanges {
    final changes = workspaceEdit['documentChanges'];
    return changes is List<Object?>
        ? List<JsonObject>.unmodifiable(changes.cast<JsonObject>())
        : const <JsonObject>[];
  }

  JsonObject get changeAnnotations =>
      workspaceEdit['changeAnnotations'] as JsonObject? ??
      const <String, Object?>{};
}

final class LspConfigurationProposal extends LspProposal {
  LspConfigurationProposal._(JsonObject params)
      : super(method: 'workspace/configuration', params: params);
}

final class LspShowDocumentProposal extends LspProposal {
  LspShowDocumentProposal._(JsonObject params)
      : super(method: 'window/showDocument', params: params);
}

final class LspShowMessageProposal extends LspProposal {
  LspShowMessageProposal._(JsonObject params)
      : super(method: 'window/showMessageRequest', params: params);
}

final class LspRegistrationProposal extends LspProposal {
  LspRegistrationProposal._(JsonObject params)
      : super(method: 'client/registerCapability', params: params);
}

final class LspUnregistrationProposal extends LspProposal {
  LspUnregistrationProposal._(JsonObject params)
      : super(method: 'client/unregisterCapability', params: params);
}

typedef LspProposalHandler = FutureOr<JsonValue> Function(
  LspProposal proposal,
);

/// Dispatches privileged reverse requests only to explicit caller handlers.
final class LspProposalDispatcher {
  final Map<String, LspProposalHandler> _handlers =
      <String, LspProposalHandler>{};

  void register(String method, LspProposalHandler handler) {
    if (!_proposalMethods.contains(method)) {
      throw LspProposalException(
        'lsp_proposal_method_unknown',
        'Method does not have a typed LSP proposal boundary.',
        method: method,
      );
    }
    if (_handlers.containsKey(method)) {
      throw LspProposalException(
        'lsp_proposal_handler_duplicate',
        'LSP proposal handler is already registered.',
        method: method,
      );
    }
    _handlers[method] = handler;
  }

  FutureOr<JsonValue> dispatch(
    String method,
    Map<String, Object?> params,
  ) {
    final handler = _handlers[method];
    if (handler == null) {
      throw LspProposalException(
        'lsp_proposal_handler_missing',
        'No caller handler accepts this LSP proposal.',
        method: method,
      );
    }
    return handler(_createProposal(method, params));
  }
}

const _proposalMethods = <String>{
  'workspace/applyEdit',
  'workspace/configuration',
  'window/showDocument',
  'window/showMessageRequest',
  'client/registerCapability',
  'client/unregisterCapability',
};

LspProposal _createProposal(
  String method,
  Map<String, Object?> params,
) {
  final validated = _validateProposal(method, params);
  return switch (method) {
    'workspace/applyEdit' => LspApplyEditProposal._(validated),
    'workspace/configuration' => LspConfigurationProposal._(validated),
    'window/showDocument' => LspShowDocumentProposal._(validated),
    'window/showMessageRequest' => LspShowMessageProposal._(validated),
    'client/registerCapability' => LspRegistrationProposal._(validated),
    'client/unregisterCapability' => LspUnregistrationProposal._(validated),
    _ => throw LspProposalException(
        'lsp_proposal_method_unknown',
        'Method does not have a typed LSP proposal boundary.',
        method: method,
      ),
  };
}

JsonObject _validateProposal(
  String method,
  Map<String, Object?> params,
) {
  final descriptor = lspMethodsByName[method];
  if (descriptor == null || descriptor.paramsType == null) {
    throw LspProposalException(
      'lsp_proposal_method_unknown',
      'Method does not declare typed LSP proposal params.',
      method: method,
    );
  }
  try {
    return LspModelRegistry.instance.validateType(
      descriptor.paramsType!,
      params,
      context: '$method proposal',
    )! as JsonObject;
  } on LspSchemaException catch (error) {
    throw LspProposalException(
      'lsp_proposal_schema_invalid',
      'Reverse request does not satisfy its pinned LSP proposal schema.',
      method: method,
      cause: error,
    );
  }
}
