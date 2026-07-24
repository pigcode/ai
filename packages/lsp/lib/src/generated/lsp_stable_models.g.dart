// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: LSP 3.18 audit snapshot b7f5132, generator format 1.

// ignore_for_file: camel_case_types

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../models.dart';

/// Validated LSP `AnnotatedTextEdit` value.
final class LspAnnotatedTextEdit extends LspSchemaValue {
  factory LspAnnotatedTextEdit.fromJson(JsonValue value) {
    return LspAnnotatedTextEdit._(
      LspModelRegistry.instance.validateNamed('AnnotatedTextEdit', value),
    );
  }

  LspAnnotatedTextEdit._(super.value)
      : super(definitionName: 'AnnotatedTextEdit');
}

/// Validated LSP `ApplyKind` value.
final class LspApplyKind extends LspSchemaValue {
  factory LspApplyKind.fromJson(JsonValue value) {
    return LspApplyKind._(
      LspModelRegistry.instance.validateNamed('ApplyKind', value),
    );
  }

  LspApplyKind._(super.value) : super(definitionName: 'ApplyKind');
}

/// Validated LSP `ApplyWorkspaceEditParams` value.
final class LspApplyWorkspaceEditParams extends LspSchemaValue {
  factory LspApplyWorkspaceEditParams.fromJson(JsonValue value) {
    return LspApplyWorkspaceEditParams._(
      LspModelRegistry.instance
          .validateNamed('ApplyWorkspaceEditParams', value),
    );
  }

  LspApplyWorkspaceEditParams._(super.value)
      : super(definitionName: 'ApplyWorkspaceEditParams');
}

/// Validated LSP `ApplyWorkspaceEditResult` value.
final class LspApplyWorkspaceEditResult extends LspSchemaValue {
  factory LspApplyWorkspaceEditResult.fromJson(JsonValue value) {
    return LspApplyWorkspaceEditResult._(
      LspModelRegistry.instance
          .validateNamed('ApplyWorkspaceEditResult', value),
    );
  }

  LspApplyWorkspaceEditResult._(super.value)
      : super(definitionName: 'ApplyWorkspaceEditResult');
}

/// Validated LSP `BaseSymbolInformation` value.
final class LspBaseSymbolInformation extends LspSchemaValue {
  factory LspBaseSymbolInformation.fromJson(JsonValue value) {
    return LspBaseSymbolInformation._(
      LspModelRegistry.instance.validateNamed('BaseSymbolInformation', value),
    );
  }

  LspBaseSymbolInformation._(super.value)
      : super(definitionName: 'BaseSymbolInformation');
}

/// Validated LSP `CallHierarchyClientCapabilities` value.
final class LspCallHierarchyClientCapabilities extends LspSchemaValue {
  factory LspCallHierarchyClientCapabilities.fromJson(JsonValue value) {
    return LspCallHierarchyClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('CallHierarchyClientCapabilities', value),
    );
  }

  LspCallHierarchyClientCapabilities._(super.value)
      : super(definitionName: 'CallHierarchyClientCapabilities');
}

/// Validated LSP `CallHierarchyIncomingCall` value.
final class LspCallHierarchyIncomingCall extends LspSchemaValue {
  factory LspCallHierarchyIncomingCall.fromJson(JsonValue value) {
    return LspCallHierarchyIncomingCall._(
      LspModelRegistry.instance
          .validateNamed('CallHierarchyIncomingCall', value),
    );
  }

  LspCallHierarchyIncomingCall._(super.value)
      : super(definitionName: 'CallHierarchyIncomingCall');
}

/// Validated LSP `CallHierarchyIncomingCallsParams` value.
final class LspCallHierarchyIncomingCallsParams extends LspSchemaValue {
  factory LspCallHierarchyIncomingCallsParams.fromJson(JsonValue value) {
    return LspCallHierarchyIncomingCallsParams._(
      LspModelRegistry.instance
          .validateNamed('CallHierarchyIncomingCallsParams', value),
    );
  }

  LspCallHierarchyIncomingCallsParams._(super.value)
      : super(definitionName: 'CallHierarchyIncomingCallsParams');
}

/// Validated LSP `CallHierarchyItem` value.
final class LspCallHierarchyItem extends LspSchemaValue {
  factory LspCallHierarchyItem.fromJson(JsonValue value) {
    return LspCallHierarchyItem._(
      LspModelRegistry.instance.validateNamed('CallHierarchyItem', value),
    );
  }

  LspCallHierarchyItem._(super.value)
      : super(definitionName: 'CallHierarchyItem');
}

/// Validated LSP `CallHierarchyOptions` value.
final class LspCallHierarchyOptions extends LspSchemaValue {
  factory LspCallHierarchyOptions.fromJson(JsonValue value) {
    return LspCallHierarchyOptions._(
      LspModelRegistry.instance.validateNamed('CallHierarchyOptions', value),
    );
  }

  LspCallHierarchyOptions._(super.value)
      : super(definitionName: 'CallHierarchyOptions');
}

/// Validated LSP `CallHierarchyOutgoingCall` value.
final class LspCallHierarchyOutgoingCall extends LspSchemaValue {
  factory LspCallHierarchyOutgoingCall.fromJson(JsonValue value) {
    return LspCallHierarchyOutgoingCall._(
      LspModelRegistry.instance
          .validateNamed('CallHierarchyOutgoingCall', value),
    );
  }

  LspCallHierarchyOutgoingCall._(super.value)
      : super(definitionName: 'CallHierarchyOutgoingCall');
}

/// Validated LSP `CallHierarchyOutgoingCallsParams` value.
final class LspCallHierarchyOutgoingCallsParams extends LspSchemaValue {
  factory LspCallHierarchyOutgoingCallsParams.fromJson(JsonValue value) {
    return LspCallHierarchyOutgoingCallsParams._(
      LspModelRegistry.instance
          .validateNamed('CallHierarchyOutgoingCallsParams', value),
    );
  }

  LspCallHierarchyOutgoingCallsParams._(super.value)
      : super(definitionName: 'CallHierarchyOutgoingCallsParams');
}

/// Validated LSP `CallHierarchyPrepareParams` value.
final class LspCallHierarchyPrepareParams extends LspSchemaValue {
  factory LspCallHierarchyPrepareParams.fromJson(JsonValue value) {
    return LspCallHierarchyPrepareParams._(
      LspModelRegistry.instance
          .validateNamed('CallHierarchyPrepareParams', value),
    );
  }

  LspCallHierarchyPrepareParams._(super.value)
      : super(definitionName: 'CallHierarchyPrepareParams');
}

/// Validated LSP `CallHierarchyRegistrationOptions` value.
final class LspCallHierarchyRegistrationOptions extends LspSchemaValue {
  factory LspCallHierarchyRegistrationOptions.fromJson(JsonValue value) {
    return LspCallHierarchyRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('CallHierarchyRegistrationOptions', value),
    );
  }

  LspCallHierarchyRegistrationOptions._(super.value)
      : super(definitionName: 'CallHierarchyRegistrationOptions');
}

/// Validated LSP `CancelParams` value.
final class LspCancelParams extends LspSchemaValue {
  factory LspCancelParams.fromJson(JsonValue value) {
    return LspCancelParams._(
      LspModelRegistry.instance.validateNamed('CancelParams', value),
    );
  }

  LspCancelParams._(super.value) : super(definitionName: 'CancelParams');
}

/// Validated LSP `ChangeAnnotation` value.
final class LspChangeAnnotation extends LspSchemaValue {
  factory LspChangeAnnotation.fromJson(JsonValue value) {
    return LspChangeAnnotation._(
      LspModelRegistry.instance.validateNamed('ChangeAnnotation', value),
    );
  }

  LspChangeAnnotation._(super.value)
      : super(definitionName: 'ChangeAnnotation');
}

/// Validated LSP `ChangeAnnotationIdentifier` value.
final class LspChangeAnnotationIdentifier extends LspSchemaValue {
  factory LspChangeAnnotationIdentifier.fromJson(JsonValue value) {
    return LspChangeAnnotationIdentifier._(
      LspModelRegistry.instance
          .validateNamed('ChangeAnnotationIdentifier', value),
    );
  }

  LspChangeAnnotationIdentifier._(super.value)
      : super(definitionName: 'ChangeAnnotationIdentifier');
}

/// Validated LSP `ChangeAnnotationsSupportOptions` value.
final class LspChangeAnnotationsSupportOptions extends LspSchemaValue {
  factory LspChangeAnnotationsSupportOptions.fromJson(JsonValue value) {
    return LspChangeAnnotationsSupportOptions._(
      LspModelRegistry.instance
          .validateNamed('ChangeAnnotationsSupportOptions', value),
    );
  }

  LspChangeAnnotationsSupportOptions._(super.value)
      : super(definitionName: 'ChangeAnnotationsSupportOptions');
}

/// Validated LSP `ClientCapabilities` value.
final class LspClientCapabilities extends LspSchemaValue {
  factory LspClientCapabilities.fromJson(JsonValue value) {
    return LspClientCapabilities._(
      LspModelRegistry.instance.validateNamed('ClientCapabilities', value),
    );
  }

  LspClientCapabilities._(super.value)
      : super(definitionName: 'ClientCapabilities');
}

/// Validated LSP `ClientCodeActionKindOptions` value.
final class LspClientCodeActionKindOptions extends LspSchemaValue {
  factory LspClientCodeActionKindOptions.fromJson(JsonValue value) {
    return LspClientCodeActionKindOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientCodeActionKindOptions', value),
    );
  }

  LspClientCodeActionKindOptions._(super.value)
      : super(definitionName: 'ClientCodeActionKindOptions');
}

/// Validated LSP `ClientCodeActionLiteralOptions` value.
final class LspClientCodeActionLiteralOptions extends LspSchemaValue {
  factory LspClientCodeActionLiteralOptions.fromJson(JsonValue value) {
    return LspClientCodeActionLiteralOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientCodeActionLiteralOptions', value),
    );
  }

  LspClientCodeActionLiteralOptions._(super.value)
      : super(definitionName: 'ClientCodeActionLiteralOptions');
}

/// Validated LSP `ClientCodeActionResolveOptions` value.
final class LspClientCodeActionResolveOptions extends LspSchemaValue {
  factory LspClientCodeActionResolveOptions.fromJson(JsonValue value) {
    return LspClientCodeActionResolveOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientCodeActionResolveOptions', value),
    );
  }

  LspClientCodeActionResolveOptions._(super.value)
      : super(definitionName: 'ClientCodeActionResolveOptions');
}

/// Validated LSP `ClientCodeLensResolveOptions` value.
final class LspClientCodeLensResolveOptions extends LspSchemaValue {
  factory LspClientCodeLensResolveOptions.fromJson(JsonValue value) {
    return LspClientCodeLensResolveOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientCodeLensResolveOptions', value),
    );
  }

  LspClientCodeLensResolveOptions._(super.value)
      : super(definitionName: 'ClientCodeLensResolveOptions');
}

/// Validated LSP `ClientCompletionItemInsertTextModeOptions` value.
final class LspClientCompletionItemInsertTextModeOptions
    extends LspSchemaValue {
  factory LspClientCompletionItemInsertTextModeOptions.fromJson(
      JsonValue value) {
    return LspClientCompletionItemInsertTextModeOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientCompletionItemInsertTextModeOptions', value),
    );
  }

  LspClientCompletionItemInsertTextModeOptions._(super.value)
      : super(definitionName: 'ClientCompletionItemInsertTextModeOptions');
}

/// Validated LSP `ClientCompletionItemOptions` value.
final class LspClientCompletionItemOptions extends LspSchemaValue {
  factory LspClientCompletionItemOptions.fromJson(JsonValue value) {
    return LspClientCompletionItemOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientCompletionItemOptions', value),
    );
  }

  LspClientCompletionItemOptions._(super.value)
      : super(definitionName: 'ClientCompletionItemOptions');
}

/// Validated LSP `ClientCompletionItemOptionsKind` value.
final class LspClientCompletionItemOptionsKind extends LspSchemaValue {
  factory LspClientCompletionItemOptionsKind.fromJson(JsonValue value) {
    return LspClientCompletionItemOptionsKind._(
      LspModelRegistry.instance
          .validateNamed('ClientCompletionItemOptionsKind', value),
    );
  }

  LspClientCompletionItemOptionsKind._(super.value)
      : super(definitionName: 'ClientCompletionItemOptionsKind');
}

/// Validated LSP `ClientCompletionItemResolveOptions` value.
final class LspClientCompletionItemResolveOptions extends LspSchemaValue {
  factory LspClientCompletionItemResolveOptions.fromJson(JsonValue value) {
    return LspClientCompletionItemResolveOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientCompletionItemResolveOptions', value),
    );
  }

  LspClientCompletionItemResolveOptions._(super.value)
      : super(definitionName: 'ClientCompletionItemResolveOptions');
}

/// Validated LSP `ClientDiagnosticsTagOptions` value.
final class LspClientDiagnosticsTagOptions extends LspSchemaValue {
  factory LspClientDiagnosticsTagOptions.fromJson(JsonValue value) {
    return LspClientDiagnosticsTagOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientDiagnosticsTagOptions', value),
    );
  }

  LspClientDiagnosticsTagOptions._(super.value)
      : super(definitionName: 'ClientDiagnosticsTagOptions');
}

/// Validated LSP `ClientFoldingRangeKindOptions` value.
final class LspClientFoldingRangeKindOptions extends LspSchemaValue {
  factory LspClientFoldingRangeKindOptions.fromJson(JsonValue value) {
    return LspClientFoldingRangeKindOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientFoldingRangeKindOptions', value),
    );
  }

  LspClientFoldingRangeKindOptions._(super.value)
      : super(definitionName: 'ClientFoldingRangeKindOptions');
}

/// Validated LSP `ClientFoldingRangeOptions` value.
final class LspClientFoldingRangeOptions extends LspSchemaValue {
  factory LspClientFoldingRangeOptions.fromJson(JsonValue value) {
    return LspClientFoldingRangeOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientFoldingRangeOptions', value),
    );
  }

  LspClientFoldingRangeOptions._(super.value)
      : super(definitionName: 'ClientFoldingRangeOptions');
}

/// Validated LSP `ClientInfo` value.
final class LspClientInfo extends LspSchemaValue {
  factory LspClientInfo.fromJson(JsonValue value) {
    return LspClientInfo._(
      LspModelRegistry.instance.validateNamed('ClientInfo', value),
    );
  }

  LspClientInfo._(super.value) : super(definitionName: 'ClientInfo');
}

/// Validated LSP `ClientInlayHintResolveOptions` value.
final class LspClientInlayHintResolveOptions extends LspSchemaValue {
  factory LspClientInlayHintResolveOptions.fromJson(JsonValue value) {
    return LspClientInlayHintResolveOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientInlayHintResolveOptions', value),
    );
  }

  LspClientInlayHintResolveOptions._(super.value)
      : super(definitionName: 'ClientInlayHintResolveOptions');
}

/// Validated LSP `ClientSemanticTokensRequestFullDelta` value.
final class LspClientSemanticTokensRequestFullDelta extends LspSchemaValue {
  factory LspClientSemanticTokensRequestFullDelta.fromJson(JsonValue value) {
    return LspClientSemanticTokensRequestFullDelta._(
      LspModelRegistry.instance
          .validateNamed('ClientSemanticTokensRequestFullDelta', value),
    );
  }

  LspClientSemanticTokensRequestFullDelta._(super.value)
      : super(definitionName: 'ClientSemanticTokensRequestFullDelta');
}

/// Validated LSP `ClientSemanticTokensRequestOptions` value.
final class LspClientSemanticTokensRequestOptions extends LspSchemaValue {
  factory LspClientSemanticTokensRequestOptions.fromJson(JsonValue value) {
    return LspClientSemanticTokensRequestOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientSemanticTokensRequestOptions', value),
    );
  }

  LspClientSemanticTokensRequestOptions._(super.value)
      : super(definitionName: 'ClientSemanticTokensRequestOptions');
}

/// Validated LSP `ClientShowMessageActionItemOptions` value.
final class LspClientShowMessageActionItemOptions extends LspSchemaValue {
  factory LspClientShowMessageActionItemOptions.fromJson(JsonValue value) {
    return LspClientShowMessageActionItemOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientShowMessageActionItemOptions', value),
    );
  }

  LspClientShowMessageActionItemOptions._(super.value)
      : super(definitionName: 'ClientShowMessageActionItemOptions');
}

/// Validated LSP `ClientSignatureInformationOptions` value.
final class LspClientSignatureInformationOptions extends LspSchemaValue {
  factory LspClientSignatureInformationOptions.fromJson(JsonValue value) {
    return LspClientSignatureInformationOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientSignatureInformationOptions', value),
    );
  }

  LspClientSignatureInformationOptions._(super.value)
      : super(definitionName: 'ClientSignatureInformationOptions');
}

/// Validated LSP `ClientSignatureParameterInformationOptions` value.
final class LspClientSignatureParameterInformationOptions
    extends LspSchemaValue {
  factory LspClientSignatureParameterInformationOptions.fromJson(
      JsonValue value) {
    return LspClientSignatureParameterInformationOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientSignatureParameterInformationOptions', value),
    );
  }

  LspClientSignatureParameterInformationOptions._(super.value)
      : super(definitionName: 'ClientSignatureParameterInformationOptions');
}

/// Validated LSP `ClientSymbolKindOptions` value.
final class LspClientSymbolKindOptions extends LspSchemaValue {
  factory LspClientSymbolKindOptions.fromJson(JsonValue value) {
    return LspClientSymbolKindOptions._(
      LspModelRegistry.instance.validateNamed('ClientSymbolKindOptions', value),
    );
  }

  LspClientSymbolKindOptions._(super.value)
      : super(definitionName: 'ClientSymbolKindOptions');
}

/// Validated LSP `ClientSymbolResolveOptions` value.
final class LspClientSymbolResolveOptions extends LspSchemaValue {
  factory LspClientSymbolResolveOptions.fromJson(JsonValue value) {
    return LspClientSymbolResolveOptions._(
      LspModelRegistry.instance
          .validateNamed('ClientSymbolResolveOptions', value),
    );
  }

  LspClientSymbolResolveOptions._(super.value)
      : super(definitionName: 'ClientSymbolResolveOptions');
}

/// Validated LSP `ClientSymbolTagOptions` value.
final class LspClientSymbolTagOptions extends LspSchemaValue {
  factory LspClientSymbolTagOptions.fromJson(JsonValue value) {
    return LspClientSymbolTagOptions._(
      LspModelRegistry.instance.validateNamed('ClientSymbolTagOptions', value),
    );
  }

  LspClientSymbolTagOptions._(super.value)
      : super(definitionName: 'ClientSymbolTagOptions');
}

/// Validated LSP `CodeAction` value.
final class LspCodeAction extends LspSchemaValue {
  factory LspCodeAction.fromJson(JsonValue value) {
    return LspCodeAction._(
      LspModelRegistry.instance.validateNamed('CodeAction', value),
    );
  }

  LspCodeAction._(super.value) : super(definitionName: 'CodeAction');
}

/// Validated LSP `CodeActionClientCapabilities` value.
final class LspCodeActionClientCapabilities extends LspSchemaValue {
  factory LspCodeActionClientCapabilities.fromJson(JsonValue value) {
    return LspCodeActionClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('CodeActionClientCapabilities', value),
    );
  }

  LspCodeActionClientCapabilities._(super.value)
      : super(definitionName: 'CodeActionClientCapabilities');
}

/// Validated LSP `CodeActionContext` value.
final class LspCodeActionContext extends LspSchemaValue {
  factory LspCodeActionContext.fromJson(JsonValue value) {
    return LspCodeActionContext._(
      LspModelRegistry.instance.validateNamed('CodeActionContext', value),
    );
  }

  LspCodeActionContext._(super.value)
      : super(definitionName: 'CodeActionContext');
}

/// Validated LSP `CodeActionDisabled` value.
final class LspCodeActionDisabled extends LspSchemaValue {
  factory LspCodeActionDisabled.fromJson(JsonValue value) {
    return LspCodeActionDisabled._(
      LspModelRegistry.instance.validateNamed('CodeActionDisabled', value),
    );
  }

  LspCodeActionDisabled._(super.value)
      : super(definitionName: 'CodeActionDisabled');
}

/// Validated LSP `CodeActionKind` value.
final class LspCodeActionKind extends LspSchemaValue {
  factory LspCodeActionKind.fromJson(JsonValue value) {
    return LspCodeActionKind._(
      LspModelRegistry.instance.validateNamed('CodeActionKind', value),
    );
  }

  LspCodeActionKind._(super.value) : super(definitionName: 'CodeActionKind');
}

/// Validated LSP `CodeActionKindDocumentation` value.
final class LspCodeActionKindDocumentation extends LspSchemaValue {
  factory LspCodeActionKindDocumentation.fromJson(JsonValue value) {
    return LspCodeActionKindDocumentation._(
      LspModelRegistry.instance
          .validateNamed('CodeActionKindDocumentation', value),
    );
  }

  LspCodeActionKindDocumentation._(super.value)
      : super(definitionName: 'CodeActionKindDocumentation');
}

/// Validated LSP `CodeActionOptions` value.
final class LspCodeActionOptions extends LspSchemaValue {
  factory LspCodeActionOptions.fromJson(JsonValue value) {
    return LspCodeActionOptions._(
      LspModelRegistry.instance.validateNamed('CodeActionOptions', value),
    );
  }

  LspCodeActionOptions._(super.value)
      : super(definitionName: 'CodeActionOptions');
}

/// Validated LSP `CodeActionParams` value.
final class LspCodeActionParams extends LspSchemaValue {
  factory LspCodeActionParams.fromJson(JsonValue value) {
    return LspCodeActionParams._(
      LspModelRegistry.instance.validateNamed('CodeActionParams', value),
    );
  }

  LspCodeActionParams._(super.value)
      : super(definitionName: 'CodeActionParams');
}

/// Validated LSP `CodeActionRegistrationOptions` value.
final class LspCodeActionRegistrationOptions extends LspSchemaValue {
  factory LspCodeActionRegistrationOptions.fromJson(JsonValue value) {
    return LspCodeActionRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('CodeActionRegistrationOptions', value),
    );
  }

  LspCodeActionRegistrationOptions._(super.value)
      : super(definitionName: 'CodeActionRegistrationOptions');
}

/// Validated LSP `CodeActionTag` value.
final class LspCodeActionTag extends LspSchemaValue {
  factory LspCodeActionTag.fromJson(JsonValue value) {
    return LspCodeActionTag._(
      LspModelRegistry.instance.validateNamed('CodeActionTag', value),
    );
  }

  LspCodeActionTag._(super.value) : super(definitionName: 'CodeActionTag');
}

/// Validated LSP `CodeActionTagOptions` value.
final class LspCodeActionTagOptions extends LspSchemaValue {
  factory LspCodeActionTagOptions.fromJson(JsonValue value) {
    return LspCodeActionTagOptions._(
      LspModelRegistry.instance.validateNamed('CodeActionTagOptions', value),
    );
  }

  LspCodeActionTagOptions._(super.value)
      : super(definitionName: 'CodeActionTagOptions');
}

/// Validated LSP `CodeActionTriggerKind` value.
final class LspCodeActionTriggerKind extends LspSchemaValue {
  factory LspCodeActionTriggerKind.fromJson(JsonValue value) {
    return LspCodeActionTriggerKind._(
      LspModelRegistry.instance.validateNamed('CodeActionTriggerKind', value),
    );
  }

  LspCodeActionTriggerKind._(super.value)
      : super(definitionName: 'CodeActionTriggerKind');
}

/// Validated LSP `CodeDescription` value.
final class LspCodeDescription extends LspSchemaValue {
  factory LspCodeDescription.fromJson(JsonValue value) {
    return LspCodeDescription._(
      LspModelRegistry.instance.validateNamed('CodeDescription', value),
    );
  }

  LspCodeDescription._(super.value) : super(definitionName: 'CodeDescription');
}

/// Validated LSP `CodeLens` value.
final class LspCodeLens extends LspSchemaValue {
  factory LspCodeLens.fromJson(JsonValue value) {
    return LspCodeLens._(
      LspModelRegistry.instance.validateNamed('CodeLens', value),
    );
  }

  LspCodeLens._(super.value) : super(definitionName: 'CodeLens');
}

/// Validated LSP `CodeLensClientCapabilities` value.
final class LspCodeLensClientCapabilities extends LspSchemaValue {
  factory LspCodeLensClientCapabilities.fromJson(JsonValue value) {
    return LspCodeLensClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('CodeLensClientCapabilities', value),
    );
  }

  LspCodeLensClientCapabilities._(super.value)
      : super(definitionName: 'CodeLensClientCapabilities');
}

/// Validated LSP `CodeLensOptions` value.
final class LspCodeLensOptions extends LspSchemaValue {
  factory LspCodeLensOptions.fromJson(JsonValue value) {
    return LspCodeLensOptions._(
      LspModelRegistry.instance.validateNamed('CodeLensOptions', value),
    );
  }

  LspCodeLensOptions._(super.value) : super(definitionName: 'CodeLensOptions');
}

/// Validated LSP `CodeLensParams` value.
final class LspCodeLensParams extends LspSchemaValue {
  factory LspCodeLensParams.fromJson(JsonValue value) {
    return LspCodeLensParams._(
      LspModelRegistry.instance.validateNamed('CodeLensParams', value),
    );
  }

  LspCodeLensParams._(super.value) : super(definitionName: 'CodeLensParams');
}

/// Validated LSP `CodeLensRegistrationOptions` value.
final class LspCodeLensRegistrationOptions extends LspSchemaValue {
  factory LspCodeLensRegistrationOptions.fromJson(JsonValue value) {
    return LspCodeLensRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('CodeLensRegistrationOptions', value),
    );
  }

  LspCodeLensRegistrationOptions._(super.value)
      : super(definitionName: 'CodeLensRegistrationOptions');
}

/// Validated LSP `CodeLensWorkspaceClientCapabilities` value.
final class LspCodeLensWorkspaceClientCapabilities extends LspSchemaValue {
  factory LspCodeLensWorkspaceClientCapabilities.fromJson(JsonValue value) {
    return LspCodeLensWorkspaceClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('CodeLensWorkspaceClientCapabilities', value),
    );
  }

  LspCodeLensWorkspaceClientCapabilities._(super.value)
      : super(definitionName: 'CodeLensWorkspaceClientCapabilities');
}

/// Validated LSP `Color` value.
final class LspColor extends LspSchemaValue {
  factory LspColor.fromJson(JsonValue value) {
    return LspColor._(
      LspModelRegistry.instance.validateNamed('Color', value),
    );
  }

  LspColor._(super.value) : super(definitionName: 'Color');
}

/// Validated LSP `ColorInformation` value.
final class LspColorInformation extends LspSchemaValue {
  factory LspColorInformation.fromJson(JsonValue value) {
    return LspColorInformation._(
      LspModelRegistry.instance.validateNamed('ColorInformation', value),
    );
  }

  LspColorInformation._(super.value)
      : super(definitionName: 'ColorInformation');
}

/// Validated LSP `ColorPresentation` value.
final class LspColorPresentation extends LspSchemaValue {
  factory LspColorPresentation.fromJson(JsonValue value) {
    return LspColorPresentation._(
      LspModelRegistry.instance.validateNamed('ColorPresentation', value),
    );
  }

  LspColorPresentation._(super.value)
      : super(definitionName: 'ColorPresentation');
}

/// Validated LSP `ColorPresentationParams` value.
final class LspColorPresentationParams extends LspSchemaValue {
  factory LspColorPresentationParams.fromJson(JsonValue value) {
    return LspColorPresentationParams._(
      LspModelRegistry.instance.validateNamed('ColorPresentationParams', value),
    );
  }

  LspColorPresentationParams._(super.value)
      : super(definitionName: 'ColorPresentationParams');
}

/// Validated LSP `Command` value.
final class LspCommand extends LspSchemaValue {
  factory LspCommand.fromJson(JsonValue value) {
    return LspCommand._(
      LspModelRegistry.instance.validateNamed('Command', value),
    );
  }

  LspCommand._(super.value) : super(definitionName: 'Command');
}

/// Validated LSP `CompletionClientCapabilities` value.
final class LspCompletionClientCapabilities extends LspSchemaValue {
  factory LspCompletionClientCapabilities.fromJson(JsonValue value) {
    return LspCompletionClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('CompletionClientCapabilities', value),
    );
  }

  LspCompletionClientCapabilities._(super.value)
      : super(definitionName: 'CompletionClientCapabilities');
}

/// Validated LSP `CompletionContext` value.
final class LspCompletionContext extends LspSchemaValue {
  factory LspCompletionContext.fromJson(JsonValue value) {
    return LspCompletionContext._(
      LspModelRegistry.instance.validateNamed('CompletionContext', value),
    );
  }

  LspCompletionContext._(super.value)
      : super(definitionName: 'CompletionContext');
}

/// Validated LSP `CompletionItem` value.
final class LspCompletionItem extends LspSchemaValue {
  factory LspCompletionItem.fromJson(JsonValue value) {
    return LspCompletionItem._(
      LspModelRegistry.instance.validateNamed('CompletionItem', value),
    );
  }

  LspCompletionItem._(super.value) : super(definitionName: 'CompletionItem');
}

/// Validated LSP `CompletionItemApplyKinds` value.
final class LspCompletionItemApplyKinds extends LspSchemaValue {
  factory LspCompletionItemApplyKinds.fromJson(JsonValue value) {
    return LspCompletionItemApplyKinds._(
      LspModelRegistry.instance
          .validateNamed('CompletionItemApplyKinds', value),
    );
  }

  LspCompletionItemApplyKinds._(super.value)
      : super(definitionName: 'CompletionItemApplyKinds');
}

/// Validated LSP `CompletionItemDefaults` value.
final class LspCompletionItemDefaults extends LspSchemaValue {
  factory LspCompletionItemDefaults.fromJson(JsonValue value) {
    return LspCompletionItemDefaults._(
      LspModelRegistry.instance.validateNamed('CompletionItemDefaults', value),
    );
  }

  LspCompletionItemDefaults._(super.value)
      : super(definitionName: 'CompletionItemDefaults');
}

/// Validated LSP `CompletionItemKind` value.
final class LspCompletionItemKind extends LspSchemaValue {
  factory LspCompletionItemKind.fromJson(JsonValue value) {
    return LspCompletionItemKind._(
      LspModelRegistry.instance.validateNamed('CompletionItemKind', value),
    );
  }

  LspCompletionItemKind._(super.value)
      : super(definitionName: 'CompletionItemKind');
}

/// Validated LSP `CompletionItemLabelDetails` value.
final class LspCompletionItemLabelDetails extends LspSchemaValue {
  factory LspCompletionItemLabelDetails.fromJson(JsonValue value) {
    return LspCompletionItemLabelDetails._(
      LspModelRegistry.instance
          .validateNamed('CompletionItemLabelDetails', value),
    );
  }

  LspCompletionItemLabelDetails._(super.value)
      : super(definitionName: 'CompletionItemLabelDetails');
}

/// Validated LSP `CompletionItemTag` value.
final class LspCompletionItemTag extends LspSchemaValue {
  factory LspCompletionItemTag.fromJson(JsonValue value) {
    return LspCompletionItemTag._(
      LspModelRegistry.instance.validateNamed('CompletionItemTag', value),
    );
  }

  LspCompletionItemTag._(super.value)
      : super(definitionName: 'CompletionItemTag');
}

/// Validated LSP `CompletionItemTagOptions` value.
final class LspCompletionItemTagOptions extends LspSchemaValue {
  factory LspCompletionItemTagOptions.fromJson(JsonValue value) {
    return LspCompletionItemTagOptions._(
      LspModelRegistry.instance
          .validateNamed('CompletionItemTagOptions', value),
    );
  }

  LspCompletionItemTagOptions._(super.value)
      : super(definitionName: 'CompletionItemTagOptions');
}

/// Validated LSP `CompletionList` value.
final class LspCompletionList extends LspSchemaValue {
  factory LspCompletionList.fromJson(JsonValue value) {
    return LspCompletionList._(
      LspModelRegistry.instance.validateNamed('CompletionList', value),
    );
  }

  LspCompletionList._(super.value) : super(definitionName: 'CompletionList');
}

/// Validated LSP `CompletionListCapabilities` value.
final class LspCompletionListCapabilities extends LspSchemaValue {
  factory LspCompletionListCapabilities.fromJson(JsonValue value) {
    return LspCompletionListCapabilities._(
      LspModelRegistry.instance
          .validateNamed('CompletionListCapabilities', value),
    );
  }

  LspCompletionListCapabilities._(super.value)
      : super(definitionName: 'CompletionListCapabilities');
}

/// Validated LSP `CompletionOptions` value.
final class LspCompletionOptions extends LspSchemaValue {
  factory LspCompletionOptions.fromJson(JsonValue value) {
    return LspCompletionOptions._(
      LspModelRegistry.instance.validateNamed('CompletionOptions', value),
    );
  }

  LspCompletionOptions._(super.value)
      : super(definitionName: 'CompletionOptions');
}

/// Validated LSP `CompletionParams` value.
final class LspCompletionParams extends LspSchemaValue {
  factory LspCompletionParams.fromJson(JsonValue value) {
    return LspCompletionParams._(
      LspModelRegistry.instance.validateNamed('CompletionParams', value),
    );
  }

  LspCompletionParams._(super.value)
      : super(definitionName: 'CompletionParams');
}

/// Validated LSP `CompletionRegistrationOptions` value.
final class LspCompletionRegistrationOptions extends LspSchemaValue {
  factory LspCompletionRegistrationOptions.fromJson(JsonValue value) {
    return LspCompletionRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('CompletionRegistrationOptions', value),
    );
  }

  LspCompletionRegistrationOptions._(super.value)
      : super(definitionName: 'CompletionRegistrationOptions');
}

/// Validated LSP `CompletionTriggerKind` value.
final class LspCompletionTriggerKind extends LspSchemaValue {
  factory LspCompletionTriggerKind.fromJson(JsonValue value) {
    return LspCompletionTriggerKind._(
      LspModelRegistry.instance.validateNamed('CompletionTriggerKind', value),
    );
  }

  LspCompletionTriggerKind._(super.value)
      : super(definitionName: 'CompletionTriggerKind');
}

/// Validated LSP `ConfigurationItem` value.
final class LspConfigurationItem extends LspSchemaValue {
  factory LspConfigurationItem.fromJson(JsonValue value) {
    return LspConfigurationItem._(
      LspModelRegistry.instance.validateNamed('ConfigurationItem', value),
    );
  }

  LspConfigurationItem._(super.value)
      : super(definitionName: 'ConfigurationItem');
}

/// Validated LSP `ConfigurationParams` value.
final class LspConfigurationParams extends LspSchemaValue {
  factory LspConfigurationParams.fromJson(JsonValue value) {
    return LspConfigurationParams._(
      LspModelRegistry.instance.validateNamed('ConfigurationParams', value),
    );
  }

  LspConfigurationParams._(super.value)
      : super(definitionName: 'ConfigurationParams');
}

/// Validated LSP `CreateFile` value.
final class LspCreateFile extends LspSchemaValue {
  factory LspCreateFile.fromJson(JsonValue value) {
    return LspCreateFile._(
      LspModelRegistry.instance.validateNamed('CreateFile', value),
    );
  }

  LspCreateFile._(super.value) : super(definitionName: 'CreateFile');
}

/// Validated LSP `CreateFileOptions` value.
final class LspCreateFileOptions extends LspSchemaValue {
  factory LspCreateFileOptions.fromJson(JsonValue value) {
    return LspCreateFileOptions._(
      LspModelRegistry.instance.validateNamed('CreateFileOptions', value),
    );
  }

  LspCreateFileOptions._(super.value)
      : super(definitionName: 'CreateFileOptions');
}

/// Validated LSP `CreateFilesParams` value.
final class LspCreateFilesParams extends LspSchemaValue {
  factory LspCreateFilesParams.fromJson(JsonValue value) {
    return LspCreateFilesParams._(
      LspModelRegistry.instance.validateNamed('CreateFilesParams', value),
    );
  }

  LspCreateFilesParams._(super.value)
      : super(definitionName: 'CreateFilesParams');
}

/// Validated LSP `Declaration` value.
final class LspDeclaration extends LspSchemaValue {
  factory LspDeclaration.fromJson(JsonValue value) {
    return LspDeclaration._(
      LspModelRegistry.instance.validateNamed('Declaration', value),
    );
  }

  LspDeclaration._(super.value) : super(definitionName: 'Declaration');
}

/// Validated LSP `DeclarationClientCapabilities` value.
final class LspDeclarationClientCapabilities extends LspSchemaValue {
  factory LspDeclarationClientCapabilities.fromJson(JsonValue value) {
    return LspDeclarationClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DeclarationClientCapabilities', value),
    );
  }

  LspDeclarationClientCapabilities._(super.value)
      : super(definitionName: 'DeclarationClientCapabilities');
}

/// Validated LSP `DeclarationLink` value.
final class LspDeclarationLink extends LspSchemaValue {
  factory LspDeclarationLink.fromJson(JsonValue value) {
    return LspDeclarationLink._(
      LspModelRegistry.instance.validateNamed('DeclarationLink', value),
    );
  }

  LspDeclarationLink._(super.value) : super(definitionName: 'DeclarationLink');
}

/// Validated LSP `DeclarationOptions` value.
final class LspDeclarationOptions extends LspSchemaValue {
  factory LspDeclarationOptions.fromJson(JsonValue value) {
    return LspDeclarationOptions._(
      LspModelRegistry.instance.validateNamed('DeclarationOptions', value),
    );
  }

  LspDeclarationOptions._(super.value)
      : super(definitionName: 'DeclarationOptions');
}

/// Validated LSP `DeclarationParams` value.
final class LspDeclarationParams extends LspSchemaValue {
  factory LspDeclarationParams.fromJson(JsonValue value) {
    return LspDeclarationParams._(
      LspModelRegistry.instance.validateNamed('DeclarationParams', value),
    );
  }

  LspDeclarationParams._(super.value)
      : super(definitionName: 'DeclarationParams');
}

/// Validated LSP `DeclarationRegistrationOptions` value.
final class LspDeclarationRegistrationOptions extends LspSchemaValue {
  factory LspDeclarationRegistrationOptions.fromJson(JsonValue value) {
    return LspDeclarationRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DeclarationRegistrationOptions', value),
    );
  }

  LspDeclarationRegistrationOptions._(super.value)
      : super(definitionName: 'DeclarationRegistrationOptions');
}

/// Validated LSP `Definition` value.
final class LspDefinition extends LspSchemaValue {
  factory LspDefinition.fromJson(JsonValue value) {
    return LspDefinition._(
      LspModelRegistry.instance.validateNamed('Definition', value),
    );
  }

  LspDefinition._(super.value) : super(definitionName: 'Definition');
}

/// Validated LSP `DefinitionClientCapabilities` value.
final class LspDefinitionClientCapabilities extends LspSchemaValue {
  factory LspDefinitionClientCapabilities.fromJson(JsonValue value) {
    return LspDefinitionClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DefinitionClientCapabilities', value),
    );
  }

  LspDefinitionClientCapabilities._(super.value)
      : super(definitionName: 'DefinitionClientCapabilities');
}

/// Validated LSP `DefinitionLink` value.
final class LspDefinitionLink extends LspSchemaValue {
  factory LspDefinitionLink.fromJson(JsonValue value) {
    return LspDefinitionLink._(
      LspModelRegistry.instance.validateNamed('DefinitionLink', value),
    );
  }

  LspDefinitionLink._(super.value) : super(definitionName: 'DefinitionLink');
}

/// Validated LSP `DefinitionOptions` value.
final class LspDefinitionOptions extends LspSchemaValue {
  factory LspDefinitionOptions.fromJson(JsonValue value) {
    return LspDefinitionOptions._(
      LspModelRegistry.instance.validateNamed('DefinitionOptions', value),
    );
  }

  LspDefinitionOptions._(super.value)
      : super(definitionName: 'DefinitionOptions');
}

/// Validated LSP `DefinitionParams` value.
final class LspDefinitionParams extends LspSchemaValue {
  factory LspDefinitionParams.fromJson(JsonValue value) {
    return LspDefinitionParams._(
      LspModelRegistry.instance.validateNamed('DefinitionParams', value),
    );
  }

  LspDefinitionParams._(super.value)
      : super(definitionName: 'DefinitionParams');
}

/// Validated LSP `DefinitionRegistrationOptions` value.
final class LspDefinitionRegistrationOptions extends LspSchemaValue {
  factory LspDefinitionRegistrationOptions.fromJson(JsonValue value) {
    return LspDefinitionRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DefinitionRegistrationOptions', value),
    );
  }

  LspDefinitionRegistrationOptions._(super.value)
      : super(definitionName: 'DefinitionRegistrationOptions');
}

/// Validated LSP `DeleteFile` value.
final class LspDeleteFile extends LspSchemaValue {
  factory LspDeleteFile.fromJson(JsonValue value) {
    return LspDeleteFile._(
      LspModelRegistry.instance.validateNamed('DeleteFile', value),
    );
  }

  LspDeleteFile._(super.value) : super(definitionName: 'DeleteFile');
}

/// Validated LSP `DeleteFileOptions` value.
final class LspDeleteFileOptions extends LspSchemaValue {
  factory LspDeleteFileOptions.fromJson(JsonValue value) {
    return LspDeleteFileOptions._(
      LspModelRegistry.instance.validateNamed('DeleteFileOptions', value),
    );
  }

  LspDeleteFileOptions._(super.value)
      : super(definitionName: 'DeleteFileOptions');
}

/// Validated LSP `DeleteFilesParams` value.
final class LspDeleteFilesParams extends LspSchemaValue {
  factory LspDeleteFilesParams.fromJson(JsonValue value) {
    return LspDeleteFilesParams._(
      LspModelRegistry.instance.validateNamed('DeleteFilesParams', value),
    );
  }

  LspDeleteFilesParams._(super.value)
      : super(definitionName: 'DeleteFilesParams');
}

/// Validated LSP `Diagnostic` value.
final class LspDiagnostic extends LspSchemaValue {
  factory LspDiagnostic.fromJson(JsonValue value) {
    return LspDiagnostic._(
      LspModelRegistry.instance.validateNamed('Diagnostic', value),
    );
  }

  LspDiagnostic._(super.value) : super(definitionName: 'Diagnostic');
}

/// Validated LSP `DiagnosticClientCapabilities` value.
final class LspDiagnosticClientCapabilities extends LspSchemaValue {
  factory LspDiagnosticClientCapabilities.fromJson(JsonValue value) {
    return LspDiagnosticClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DiagnosticClientCapabilities', value),
    );
  }

  LspDiagnosticClientCapabilities._(super.value)
      : super(definitionName: 'DiagnosticClientCapabilities');
}

/// Validated LSP `DiagnosticOptions` value.
final class LspDiagnosticOptions extends LspSchemaValue {
  factory LspDiagnosticOptions.fromJson(JsonValue value) {
    return LspDiagnosticOptions._(
      LspModelRegistry.instance.validateNamed('DiagnosticOptions', value),
    );
  }

  LspDiagnosticOptions._(super.value)
      : super(definitionName: 'DiagnosticOptions');
}

/// Validated LSP `DiagnosticRegistrationOptions` value.
final class LspDiagnosticRegistrationOptions extends LspSchemaValue {
  factory LspDiagnosticRegistrationOptions.fromJson(JsonValue value) {
    return LspDiagnosticRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DiagnosticRegistrationOptions', value),
    );
  }

  LspDiagnosticRegistrationOptions._(super.value)
      : super(definitionName: 'DiagnosticRegistrationOptions');
}

/// Validated LSP `DiagnosticRelatedInformation` value.
final class LspDiagnosticRelatedInformation extends LspSchemaValue {
  factory LspDiagnosticRelatedInformation.fromJson(JsonValue value) {
    return LspDiagnosticRelatedInformation._(
      LspModelRegistry.instance
          .validateNamed('DiagnosticRelatedInformation', value),
    );
  }

  LspDiagnosticRelatedInformation._(super.value)
      : super(definitionName: 'DiagnosticRelatedInformation');
}

/// Validated LSP `DiagnosticServerCancellationData` value.
final class LspDiagnosticServerCancellationData extends LspSchemaValue {
  factory LspDiagnosticServerCancellationData.fromJson(JsonValue value) {
    return LspDiagnosticServerCancellationData._(
      LspModelRegistry.instance
          .validateNamed('DiagnosticServerCancellationData', value),
    );
  }

  LspDiagnosticServerCancellationData._(super.value)
      : super(definitionName: 'DiagnosticServerCancellationData');
}

/// Validated LSP `DiagnosticSeverity` value.
final class LspDiagnosticSeverity extends LspSchemaValue {
  factory LspDiagnosticSeverity.fromJson(JsonValue value) {
    return LspDiagnosticSeverity._(
      LspModelRegistry.instance.validateNamed('DiagnosticSeverity', value),
    );
  }

  LspDiagnosticSeverity._(super.value)
      : super(definitionName: 'DiagnosticSeverity');
}

/// Validated LSP `DiagnosticTag` value.
final class LspDiagnosticTag extends LspSchemaValue {
  factory LspDiagnosticTag.fromJson(JsonValue value) {
    return LspDiagnosticTag._(
      LspModelRegistry.instance.validateNamed('DiagnosticTag', value),
    );
  }

  LspDiagnosticTag._(super.value) : super(definitionName: 'DiagnosticTag');
}

/// Validated LSP `DiagnosticWorkspaceClientCapabilities` value.
final class LspDiagnosticWorkspaceClientCapabilities extends LspSchemaValue {
  factory LspDiagnosticWorkspaceClientCapabilities.fromJson(JsonValue value) {
    return LspDiagnosticWorkspaceClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DiagnosticWorkspaceClientCapabilities', value),
    );
  }

  LspDiagnosticWorkspaceClientCapabilities._(super.value)
      : super(definitionName: 'DiagnosticWorkspaceClientCapabilities');
}

/// Validated LSP `DiagnosticsCapabilities` value.
final class LspDiagnosticsCapabilities extends LspSchemaValue {
  factory LspDiagnosticsCapabilities.fromJson(JsonValue value) {
    return LspDiagnosticsCapabilities._(
      LspModelRegistry.instance.validateNamed('DiagnosticsCapabilities', value),
    );
  }

  LspDiagnosticsCapabilities._(super.value)
      : super(definitionName: 'DiagnosticsCapabilities');
}

/// Validated LSP `DidChangeConfigurationClientCapabilities` value.
final class LspDidChangeConfigurationClientCapabilities extends LspSchemaValue {
  factory LspDidChangeConfigurationClientCapabilities.fromJson(
      JsonValue value) {
    return LspDidChangeConfigurationClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DidChangeConfigurationClientCapabilities', value),
    );
  }

  LspDidChangeConfigurationClientCapabilities._(super.value)
      : super(definitionName: 'DidChangeConfigurationClientCapabilities');
}

/// Validated LSP `DidChangeConfigurationParams` value.
final class LspDidChangeConfigurationParams extends LspSchemaValue {
  factory LspDidChangeConfigurationParams.fromJson(JsonValue value) {
    return LspDidChangeConfigurationParams._(
      LspModelRegistry.instance
          .validateNamed('DidChangeConfigurationParams', value),
    );
  }

  LspDidChangeConfigurationParams._(super.value)
      : super(definitionName: 'DidChangeConfigurationParams');
}

/// Validated LSP `DidChangeConfigurationRegistrationOptions` value.
final class LspDidChangeConfigurationRegistrationOptions
    extends LspSchemaValue {
  factory LspDidChangeConfigurationRegistrationOptions.fromJson(
      JsonValue value) {
    return LspDidChangeConfigurationRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DidChangeConfigurationRegistrationOptions', value),
    );
  }

  LspDidChangeConfigurationRegistrationOptions._(super.value)
      : super(definitionName: 'DidChangeConfigurationRegistrationOptions');
}

/// Validated LSP `DidChangeNotebookDocumentParams` value.
final class LspDidChangeNotebookDocumentParams extends LspSchemaValue {
  factory LspDidChangeNotebookDocumentParams.fromJson(JsonValue value) {
    return LspDidChangeNotebookDocumentParams._(
      LspModelRegistry.instance
          .validateNamed('DidChangeNotebookDocumentParams', value),
    );
  }

  LspDidChangeNotebookDocumentParams._(super.value)
      : super(definitionName: 'DidChangeNotebookDocumentParams');
}

/// Validated LSP `DidChangeTextDocumentParams` value.
final class LspDidChangeTextDocumentParams extends LspSchemaValue {
  factory LspDidChangeTextDocumentParams.fromJson(JsonValue value) {
    return LspDidChangeTextDocumentParams._(
      LspModelRegistry.instance
          .validateNamed('DidChangeTextDocumentParams', value),
    );
  }

  LspDidChangeTextDocumentParams._(super.value)
      : super(definitionName: 'DidChangeTextDocumentParams');
}

/// Validated LSP `DidChangeWatchedFilesClientCapabilities` value.
final class LspDidChangeWatchedFilesClientCapabilities extends LspSchemaValue {
  factory LspDidChangeWatchedFilesClientCapabilities.fromJson(JsonValue value) {
    return LspDidChangeWatchedFilesClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DidChangeWatchedFilesClientCapabilities', value),
    );
  }

  LspDidChangeWatchedFilesClientCapabilities._(super.value)
      : super(definitionName: 'DidChangeWatchedFilesClientCapabilities');
}

/// Validated LSP `DidChangeWatchedFilesParams` value.
final class LspDidChangeWatchedFilesParams extends LspSchemaValue {
  factory LspDidChangeWatchedFilesParams.fromJson(JsonValue value) {
    return LspDidChangeWatchedFilesParams._(
      LspModelRegistry.instance
          .validateNamed('DidChangeWatchedFilesParams', value),
    );
  }

  LspDidChangeWatchedFilesParams._(super.value)
      : super(definitionName: 'DidChangeWatchedFilesParams');
}

/// Validated LSP `DidChangeWatchedFilesRegistrationOptions` value.
final class LspDidChangeWatchedFilesRegistrationOptions extends LspSchemaValue {
  factory LspDidChangeWatchedFilesRegistrationOptions.fromJson(
      JsonValue value) {
    return LspDidChangeWatchedFilesRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DidChangeWatchedFilesRegistrationOptions', value),
    );
  }

  LspDidChangeWatchedFilesRegistrationOptions._(super.value)
      : super(definitionName: 'DidChangeWatchedFilesRegistrationOptions');
}

/// Validated LSP `DidChangeWorkspaceFoldersParams` value.
final class LspDidChangeWorkspaceFoldersParams extends LspSchemaValue {
  factory LspDidChangeWorkspaceFoldersParams.fromJson(JsonValue value) {
    return LspDidChangeWorkspaceFoldersParams._(
      LspModelRegistry.instance
          .validateNamed('DidChangeWorkspaceFoldersParams', value),
    );
  }

  LspDidChangeWorkspaceFoldersParams._(super.value)
      : super(definitionName: 'DidChangeWorkspaceFoldersParams');
}

/// Validated LSP `DidCloseNotebookDocumentParams` value.
final class LspDidCloseNotebookDocumentParams extends LspSchemaValue {
  factory LspDidCloseNotebookDocumentParams.fromJson(JsonValue value) {
    return LspDidCloseNotebookDocumentParams._(
      LspModelRegistry.instance
          .validateNamed('DidCloseNotebookDocumentParams', value),
    );
  }

  LspDidCloseNotebookDocumentParams._(super.value)
      : super(definitionName: 'DidCloseNotebookDocumentParams');
}

/// Validated LSP `DidCloseTextDocumentParams` value.
final class LspDidCloseTextDocumentParams extends LspSchemaValue {
  factory LspDidCloseTextDocumentParams.fromJson(JsonValue value) {
    return LspDidCloseTextDocumentParams._(
      LspModelRegistry.instance
          .validateNamed('DidCloseTextDocumentParams', value),
    );
  }

  LspDidCloseTextDocumentParams._(super.value)
      : super(definitionName: 'DidCloseTextDocumentParams');
}

/// Validated LSP `DidOpenNotebookDocumentParams` value.
final class LspDidOpenNotebookDocumentParams extends LspSchemaValue {
  factory LspDidOpenNotebookDocumentParams.fromJson(JsonValue value) {
    return LspDidOpenNotebookDocumentParams._(
      LspModelRegistry.instance
          .validateNamed('DidOpenNotebookDocumentParams', value),
    );
  }

  LspDidOpenNotebookDocumentParams._(super.value)
      : super(definitionName: 'DidOpenNotebookDocumentParams');
}

/// Validated LSP `DidOpenTextDocumentParams` value.
final class LspDidOpenTextDocumentParams extends LspSchemaValue {
  factory LspDidOpenTextDocumentParams.fromJson(JsonValue value) {
    return LspDidOpenTextDocumentParams._(
      LspModelRegistry.instance
          .validateNamed('DidOpenTextDocumentParams', value),
    );
  }

  LspDidOpenTextDocumentParams._(super.value)
      : super(definitionName: 'DidOpenTextDocumentParams');
}

/// Validated LSP `DidSaveNotebookDocumentParams` value.
final class LspDidSaveNotebookDocumentParams extends LspSchemaValue {
  factory LspDidSaveNotebookDocumentParams.fromJson(JsonValue value) {
    return LspDidSaveNotebookDocumentParams._(
      LspModelRegistry.instance
          .validateNamed('DidSaveNotebookDocumentParams', value),
    );
  }

  LspDidSaveNotebookDocumentParams._(super.value)
      : super(definitionName: 'DidSaveNotebookDocumentParams');
}

/// Validated LSP `DidSaveTextDocumentParams` value.
final class LspDidSaveTextDocumentParams extends LspSchemaValue {
  factory LspDidSaveTextDocumentParams.fromJson(JsonValue value) {
    return LspDidSaveTextDocumentParams._(
      LspModelRegistry.instance
          .validateNamed('DidSaveTextDocumentParams', value),
    );
  }

  LspDidSaveTextDocumentParams._(super.value)
      : super(definitionName: 'DidSaveTextDocumentParams');
}

/// Validated LSP `DocumentColorClientCapabilities` value.
final class LspDocumentColorClientCapabilities extends LspSchemaValue {
  factory LspDocumentColorClientCapabilities.fromJson(JsonValue value) {
    return LspDocumentColorClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DocumentColorClientCapabilities', value),
    );
  }

  LspDocumentColorClientCapabilities._(super.value)
      : super(definitionName: 'DocumentColorClientCapabilities');
}

/// Validated LSP `DocumentColorOptions` value.
final class LspDocumentColorOptions extends LspSchemaValue {
  factory LspDocumentColorOptions.fromJson(JsonValue value) {
    return LspDocumentColorOptions._(
      LspModelRegistry.instance.validateNamed('DocumentColorOptions', value),
    );
  }

  LspDocumentColorOptions._(super.value)
      : super(definitionName: 'DocumentColorOptions');
}

/// Validated LSP `DocumentColorParams` value.
final class LspDocumentColorParams extends LspSchemaValue {
  factory LspDocumentColorParams.fromJson(JsonValue value) {
    return LspDocumentColorParams._(
      LspModelRegistry.instance.validateNamed('DocumentColorParams', value),
    );
  }

  LspDocumentColorParams._(super.value)
      : super(definitionName: 'DocumentColorParams');
}

/// Validated LSP `DocumentColorRegistrationOptions` value.
final class LspDocumentColorRegistrationOptions extends LspSchemaValue {
  factory LspDocumentColorRegistrationOptions.fromJson(JsonValue value) {
    return LspDocumentColorRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DocumentColorRegistrationOptions', value),
    );
  }

  LspDocumentColorRegistrationOptions._(super.value)
      : super(definitionName: 'DocumentColorRegistrationOptions');
}

/// Validated LSP `DocumentDiagnosticParams` value.
final class LspDocumentDiagnosticParams extends LspSchemaValue {
  factory LspDocumentDiagnosticParams.fromJson(JsonValue value) {
    return LspDocumentDiagnosticParams._(
      LspModelRegistry.instance
          .validateNamed('DocumentDiagnosticParams', value),
    );
  }

  LspDocumentDiagnosticParams._(super.value)
      : super(definitionName: 'DocumentDiagnosticParams');
}

/// Validated LSP `DocumentDiagnosticReport` value.
final class LspDocumentDiagnosticReport extends LspSchemaValue {
  factory LspDocumentDiagnosticReport.fromJson(JsonValue value) {
    return LspDocumentDiagnosticReport._(
      LspModelRegistry.instance
          .validateNamed('DocumentDiagnosticReport', value),
    );
  }

  LspDocumentDiagnosticReport._(super.value)
      : super(definitionName: 'DocumentDiagnosticReport');
}

/// Validated LSP `DocumentDiagnosticReportKind` value.
final class LspDocumentDiagnosticReportKind extends LspSchemaValue {
  factory LspDocumentDiagnosticReportKind.fromJson(JsonValue value) {
    return LspDocumentDiagnosticReportKind._(
      LspModelRegistry.instance
          .validateNamed('DocumentDiagnosticReportKind', value),
    );
  }

  LspDocumentDiagnosticReportKind._(super.value)
      : super(definitionName: 'DocumentDiagnosticReportKind');
}

/// Validated LSP `DocumentDiagnosticReportPartialResult` value.
final class LspDocumentDiagnosticReportPartialResult extends LspSchemaValue {
  factory LspDocumentDiagnosticReportPartialResult.fromJson(JsonValue value) {
    return LspDocumentDiagnosticReportPartialResult._(
      LspModelRegistry.instance
          .validateNamed('DocumentDiagnosticReportPartialResult', value),
    );
  }

  LspDocumentDiagnosticReportPartialResult._(super.value)
      : super(definitionName: 'DocumentDiagnosticReportPartialResult');
}

/// Validated LSP `DocumentDiagnosticReportProgress` value.
final class LspDocumentDiagnosticReportProgress extends LspSchemaValue {
  factory LspDocumentDiagnosticReportProgress.fromJson(JsonValue value) {
    return LspDocumentDiagnosticReportProgress._(
      LspModelRegistry.instance
          .validateNamed('DocumentDiagnosticReportProgress', value),
    );
  }

  LspDocumentDiagnosticReportProgress._(super.value)
      : super(definitionName: 'DocumentDiagnosticReportProgress');
}

/// Validated LSP `DocumentFilter` value.
final class LspDocumentFilter extends LspSchemaValue {
  factory LspDocumentFilter.fromJson(JsonValue value) {
    return LspDocumentFilter._(
      LspModelRegistry.instance.validateNamed('DocumentFilter', value),
    );
  }

  LspDocumentFilter._(super.value) : super(definitionName: 'DocumentFilter');
}

/// Validated LSP `DocumentFormattingClientCapabilities` value.
final class LspDocumentFormattingClientCapabilities extends LspSchemaValue {
  factory LspDocumentFormattingClientCapabilities.fromJson(JsonValue value) {
    return LspDocumentFormattingClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DocumentFormattingClientCapabilities', value),
    );
  }

  LspDocumentFormattingClientCapabilities._(super.value)
      : super(definitionName: 'DocumentFormattingClientCapabilities');
}

/// Validated LSP `DocumentFormattingOptions` value.
final class LspDocumentFormattingOptions extends LspSchemaValue {
  factory LspDocumentFormattingOptions.fromJson(JsonValue value) {
    return LspDocumentFormattingOptions._(
      LspModelRegistry.instance
          .validateNamed('DocumentFormattingOptions', value),
    );
  }

  LspDocumentFormattingOptions._(super.value)
      : super(definitionName: 'DocumentFormattingOptions');
}

/// Validated LSP `DocumentFormattingParams` value.
final class LspDocumentFormattingParams extends LspSchemaValue {
  factory LspDocumentFormattingParams.fromJson(JsonValue value) {
    return LspDocumentFormattingParams._(
      LspModelRegistry.instance
          .validateNamed('DocumentFormattingParams', value),
    );
  }

  LspDocumentFormattingParams._(super.value)
      : super(definitionName: 'DocumentFormattingParams');
}

/// Validated LSP `DocumentFormattingRegistrationOptions` value.
final class LspDocumentFormattingRegistrationOptions extends LspSchemaValue {
  factory LspDocumentFormattingRegistrationOptions.fromJson(JsonValue value) {
    return LspDocumentFormattingRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DocumentFormattingRegistrationOptions', value),
    );
  }

  LspDocumentFormattingRegistrationOptions._(super.value)
      : super(definitionName: 'DocumentFormattingRegistrationOptions');
}

/// Validated LSP `DocumentHighlight` value.
final class LspDocumentHighlight extends LspSchemaValue {
  factory LspDocumentHighlight.fromJson(JsonValue value) {
    return LspDocumentHighlight._(
      LspModelRegistry.instance.validateNamed('DocumentHighlight', value),
    );
  }

  LspDocumentHighlight._(super.value)
      : super(definitionName: 'DocumentHighlight');
}

/// Validated LSP `DocumentHighlightClientCapabilities` value.
final class LspDocumentHighlightClientCapabilities extends LspSchemaValue {
  factory LspDocumentHighlightClientCapabilities.fromJson(JsonValue value) {
    return LspDocumentHighlightClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DocumentHighlightClientCapabilities', value),
    );
  }

  LspDocumentHighlightClientCapabilities._(super.value)
      : super(definitionName: 'DocumentHighlightClientCapabilities');
}

/// Validated LSP `DocumentHighlightKind` value.
final class LspDocumentHighlightKind extends LspSchemaValue {
  factory LspDocumentHighlightKind.fromJson(JsonValue value) {
    return LspDocumentHighlightKind._(
      LspModelRegistry.instance.validateNamed('DocumentHighlightKind', value),
    );
  }

  LspDocumentHighlightKind._(super.value)
      : super(definitionName: 'DocumentHighlightKind');
}

/// Validated LSP `DocumentHighlightOptions` value.
final class LspDocumentHighlightOptions extends LspSchemaValue {
  factory LspDocumentHighlightOptions.fromJson(JsonValue value) {
    return LspDocumentHighlightOptions._(
      LspModelRegistry.instance
          .validateNamed('DocumentHighlightOptions', value),
    );
  }

  LspDocumentHighlightOptions._(super.value)
      : super(definitionName: 'DocumentHighlightOptions');
}

/// Validated LSP `DocumentHighlightParams` value.
final class LspDocumentHighlightParams extends LspSchemaValue {
  factory LspDocumentHighlightParams.fromJson(JsonValue value) {
    return LspDocumentHighlightParams._(
      LspModelRegistry.instance.validateNamed('DocumentHighlightParams', value),
    );
  }

  LspDocumentHighlightParams._(super.value)
      : super(definitionName: 'DocumentHighlightParams');
}

/// Validated LSP `DocumentHighlightRegistrationOptions` value.
final class LspDocumentHighlightRegistrationOptions extends LspSchemaValue {
  factory LspDocumentHighlightRegistrationOptions.fromJson(JsonValue value) {
    return LspDocumentHighlightRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DocumentHighlightRegistrationOptions', value),
    );
  }

  LspDocumentHighlightRegistrationOptions._(super.value)
      : super(definitionName: 'DocumentHighlightRegistrationOptions');
}

/// Validated LSP `DocumentLink` value.
final class LspDocumentLink extends LspSchemaValue {
  factory LspDocumentLink.fromJson(JsonValue value) {
    return LspDocumentLink._(
      LspModelRegistry.instance.validateNamed('DocumentLink', value),
    );
  }

  LspDocumentLink._(super.value) : super(definitionName: 'DocumentLink');
}

/// Validated LSP `DocumentLinkClientCapabilities` value.
final class LspDocumentLinkClientCapabilities extends LspSchemaValue {
  factory LspDocumentLinkClientCapabilities.fromJson(JsonValue value) {
    return LspDocumentLinkClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DocumentLinkClientCapabilities', value),
    );
  }

  LspDocumentLinkClientCapabilities._(super.value)
      : super(definitionName: 'DocumentLinkClientCapabilities');
}

/// Validated LSP `DocumentLinkOptions` value.
final class LspDocumentLinkOptions extends LspSchemaValue {
  factory LspDocumentLinkOptions.fromJson(JsonValue value) {
    return LspDocumentLinkOptions._(
      LspModelRegistry.instance.validateNamed('DocumentLinkOptions', value),
    );
  }

  LspDocumentLinkOptions._(super.value)
      : super(definitionName: 'DocumentLinkOptions');
}

/// Validated LSP `DocumentLinkParams` value.
final class LspDocumentLinkParams extends LspSchemaValue {
  factory LspDocumentLinkParams.fromJson(JsonValue value) {
    return LspDocumentLinkParams._(
      LspModelRegistry.instance.validateNamed('DocumentLinkParams', value),
    );
  }

  LspDocumentLinkParams._(super.value)
      : super(definitionName: 'DocumentLinkParams');
}

/// Validated LSP `DocumentLinkRegistrationOptions` value.
final class LspDocumentLinkRegistrationOptions extends LspSchemaValue {
  factory LspDocumentLinkRegistrationOptions.fromJson(JsonValue value) {
    return LspDocumentLinkRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DocumentLinkRegistrationOptions', value),
    );
  }

  LspDocumentLinkRegistrationOptions._(super.value)
      : super(definitionName: 'DocumentLinkRegistrationOptions');
}

/// Validated LSP `DocumentOnTypeFormattingClientCapabilities` value.
final class LspDocumentOnTypeFormattingClientCapabilities
    extends LspSchemaValue {
  factory LspDocumentOnTypeFormattingClientCapabilities.fromJson(
      JsonValue value) {
    return LspDocumentOnTypeFormattingClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DocumentOnTypeFormattingClientCapabilities', value),
    );
  }

  LspDocumentOnTypeFormattingClientCapabilities._(super.value)
      : super(definitionName: 'DocumentOnTypeFormattingClientCapabilities');
}

/// Validated LSP `DocumentOnTypeFormattingOptions` value.
final class LspDocumentOnTypeFormattingOptions extends LspSchemaValue {
  factory LspDocumentOnTypeFormattingOptions.fromJson(JsonValue value) {
    return LspDocumentOnTypeFormattingOptions._(
      LspModelRegistry.instance
          .validateNamed('DocumentOnTypeFormattingOptions', value),
    );
  }

  LspDocumentOnTypeFormattingOptions._(super.value)
      : super(definitionName: 'DocumentOnTypeFormattingOptions');
}

/// Validated LSP `DocumentOnTypeFormattingParams` value.
final class LspDocumentOnTypeFormattingParams extends LspSchemaValue {
  factory LspDocumentOnTypeFormattingParams.fromJson(JsonValue value) {
    return LspDocumentOnTypeFormattingParams._(
      LspModelRegistry.instance
          .validateNamed('DocumentOnTypeFormattingParams', value),
    );
  }

  LspDocumentOnTypeFormattingParams._(super.value)
      : super(definitionName: 'DocumentOnTypeFormattingParams');
}

/// Validated LSP `DocumentOnTypeFormattingRegistrationOptions` value.
final class LspDocumentOnTypeFormattingRegistrationOptions
    extends LspSchemaValue {
  factory LspDocumentOnTypeFormattingRegistrationOptions.fromJson(
      JsonValue value) {
    return LspDocumentOnTypeFormattingRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DocumentOnTypeFormattingRegistrationOptions', value),
    );
  }

  LspDocumentOnTypeFormattingRegistrationOptions._(super.value)
      : super(definitionName: 'DocumentOnTypeFormattingRegistrationOptions');
}

/// Validated LSP `DocumentRangeFormattingClientCapabilities` value.
final class LspDocumentRangeFormattingClientCapabilities
    extends LspSchemaValue {
  factory LspDocumentRangeFormattingClientCapabilities.fromJson(
      JsonValue value) {
    return LspDocumentRangeFormattingClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DocumentRangeFormattingClientCapabilities', value),
    );
  }

  LspDocumentRangeFormattingClientCapabilities._(super.value)
      : super(definitionName: 'DocumentRangeFormattingClientCapabilities');
}

/// Validated LSP `DocumentRangeFormattingOptions` value.
final class LspDocumentRangeFormattingOptions extends LspSchemaValue {
  factory LspDocumentRangeFormattingOptions.fromJson(JsonValue value) {
    return LspDocumentRangeFormattingOptions._(
      LspModelRegistry.instance
          .validateNamed('DocumentRangeFormattingOptions', value),
    );
  }

  LspDocumentRangeFormattingOptions._(super.value)
      : super(definitionName: 'DocumentRangeFormattingOptions');
}

/// Validated LSP `DocumentRangeFormattingParams` value.
final class LspDocumentRangeFormattingParams extends LspSchemaValue {
  factory LspDocumentRangeFormattingParams.fromJson(JsonValue value) {
    return LspDocumentRangeFormattingParams._(
      LspModelRegistry.instance
          .validateNamed('DocumentRangeFormattingParams', value),
    );
  }

  LspDocumentRangeFormattingParams._(super.value)
      : super(definitionName: 'DocumentRangeFormattingParams');
}

/// Validated LSP `DocumentRangeFormattingRegistrationOptions` value.
final class LspDocumentRangeFormattingRegistrationOptions
    extends LspSchemaValue {
  factory LspDocumentRangeFormattingRegistrationOptions.fromJson(
      JsonValue value) {
    return LspDocumentRangeFormattingRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DocumentRangeFormattingRegistrationOptions', value),
    );
  }

  LspDocumentRangeFormattingRegistrationOptions._(super.value)
      : super(definitionName: 'DocumentRangeFormattingRegistrationOptions');
}

/// Validated LSP `DocumentRangesFormattingParams` value.
final class LspDocumentRangesFormattingParams extends LspSchemaValue {
  factory LspDocumentRangesFormattingParams.fromJson(JsonValue value) {
    return LspDocumentRangesFormattingParams._(
      LspModelRegistry.instance
          .validateNamed('DocumentRangesFormattingParams', value),
    );
  }

  LspDocumentRangesFormattingParams._(super.value)
      : super(definitionName: 'DocumentRangesFormattingParams');
}

/// Validated LSP `DocumentSelector` value.
final class LspDocumentSelector extends LspSchemaValue {
  factory LspDocumentSelector.fromJson(JsonValue value) {
    return LspDocumentSelector._(
      LspModelRegistry.instance.validateNamed('DocumentSelector', value),
    );
  }

  LspDocumentSelector._(super.value)
      : super(definitionName: 'DocumentSelector');
}

/// Validated LSP `DocumentSymbol` value.
final class LspDocumentSymbol extends LspSchemaValue {
  factory LspDocumentSymbol.fromJson(JsonValue value) {
    return LspDocumentSymbol._(
      LspModelRegistry.instance.validateNamed('DocumentSymbol', value),
    );
  }

  LspDocumentSymbol._(super.value) : super(definitionName: 'DocumentSymbol');
}

/// Validated LSP `DocumentSymbolClientCapabilities` value.
final class LspDocumentSymbolClientCapabilities extends LspSchemaValue {
  factory LspDocumentSymbolClientCapabilities.fromJson(JsonValue value) {
    return LspDocumentSymbolClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('DocumentSymbolClientCapabilities', value),
    );
  }

  LspDocumentSymbolClientCapabilities._(super.value)
      : super(definitionName: 'DocumentSymbolClientCapabilities');
}

/// Validated LSP `DocumentSymbolOptions` value.
final class LspDocumentSymbolOptions extends LspSchemaValue {
  factory LspDocumentSymbolOptions.fromJson(JsonValue value) {
    return LspDocumentSymbolOptions._(
      LspModelRegistry.instance.validateNamed('DocumentSymbolOptions', value),
    );
  }

  LspDocumentSymbolOptions._(super.value)
      : super(definitionName: 'DocumentSymbolOptions');
}

/// Validated LSP `DocumentSymbolParams` value.
final class LspDocumentSymbolParams extends LspSchemaValue {
  factory LspDocumentSymbolParams.fromJson(JsonValue value) {
    return LspDocumentSymbolParams._(
      LspModelRegistry.instance.validateNamed('DocumentSymbolParams', value),
    );
  }

  LspDocumentSymbolParams._(super.value)
      : super(definitionName: 'DocumentSymbolParams');
}

/// Validated LSP `DocumentSymbolRegistrationOptions` value.
final class LspDocumentSymbolRegistrationOptions extends LspSchemaValue {
  factory LspDocumentSymbolRegistrationOptions.fromJson(JsonValue value) {
    return LspDocumentSymbolRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('DocumentSymbolRegistrationOptions', value),
    );
  }

  LspDocumentSymbolRegistrationOptions._(super.value)
      : super(definitionName: 'DocumentSymbolRegistrationOptions');
}

/// Validated LSP `EditRangeWithInsertReplace` value.
final class LspEditRangeWithInsertReplace extends LspSchemaValue {
  factory LspEditRangeWithInsertReplace.fromJson(JsonValue value) {
    return LspEditRangeWithInsertReplace._(
      LspModelRegistry.instance
          .validateNamed('EditRangeWithInsertReplace', value),
    );
  }

  LspEditRangeWithInsertReplace._(super.value)
      : super(definitionName: 'EditRangeWithInsertReplace');
}

/// Validated LSP `ErrorCodes` value.
final class LspErrorCodes extends LspSchemaValue {
  factory LspErrorCodes.fromJson(JsonValue value) {
    return LspErrorCodes._(
      LspModelRegistry.instance.validateNamed('ErrorCodes', value),
    );
  }

  LspErrorCodes._(super.value) : super(definitionName: 'ErrorCodes');
}

/// Validated LSP `ExecuteCommandClientCapabilities` value.
final class LspExecuteCommandClientCapabilities extends LspSchemaValue {
  factory LspExecuteCommandClientCapabilities.fromJson(JsonValue value) {
    return LspExecuteCommandClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('ExecuteCommandClientCapabilities', value),
    );
  }

  LspExecuteCommandClientCapabilities._(super.value)
      : super(definitionName: 'ExecuteCommandClientCapabilities');
}

/// Validated LSP `ExecuteCommandOptions` value.
final class LspExecuteCommandOptions extends LspSchemaValue {
  factory LspExecuteCommandOptions.fromJson(JsonValue value) {
    return LspExecuteCommandOptions._(
      LspModelRegistry.instance.validateNamed('ExecuteCommandOptions', value),
    );
  }

  LspExecuteCommandOptions._(super.value)
      : super(definitionName: 'ExecuteCommandOptions');
}

/// Validated LSP `ExecuteCommandParams` value.
final class LspExecuteCommandParams extends LspSchemaValue {
  factory LspExecuteCommandParams.fromJson(JsonValue value) {
    return LspExecuteCommandParams._(
      LspModelRegistry.instance.validateNamed('ExecuteCommandParams', value),
    );
  }

  LspExecuteCommandParams._(super.value)
      : super(definitionName: 'ExecuteCommandParams');
}

/// Validated LSP `ExecuteCommandRegistrationOptions` value.
final class LspExecuteCommandRegistrationOptions extends LspSchemaValue {
  factory LspExecuteCommandRegistrationOptions.fromJson(JsonValue value) {
    return LspExecuteCommandRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('ExecuteCommandRegistrationOptions', value),
    );
  }

  LspExecuteCommandRegistrationOptions._(super.value)
      : super(definitionName: 'ExecuteCommandRegistrationOptions');
}

/// Validated LSP `ExecutionSummary` value.
final class LspExecutionSummary extends LspSchemaValue {
  factory LspExecutionSummary.fromJson(JsonValue value) {
    return LspExecutionSummary._(
      LspModelRegistry.instance.validateNamed('ExecutionSummary', value),
    );
  }

  LspExecutionSummary._(super.value)
      : super(definitionName: 'ExecutionSummary');
}

/// Validated LSP `FailureHandlingKind` value.
final class LspFailureHandlingKind extends LspSchemaValue {
  factory LspFailureHandlingKind.fromJson(JsonValue value) {
    return LspFailureHandlingKind._(
      LspModelRegistry.instance.validateNamed('FailureHandlingKind', value),
    );
  }

  LspFailureHandlingKind._(super.value)
      : super(definitionName: 'FailureHandlingKind');
}

/// Validated LSP `FileChangeType` value.
final class LspFileChangeType extends LspSchemaValue {
  factory LspFileChangeType.fromJson(JsonValue value) {
    return LspFileChangeType._(
      LspModelRegistry.instance.validateNamed('FileChangeType', value),
    );
  }

  LspFileChangeType._(super.value) : super(definitionName: 'FileChangeType');
}

/// Validated LSP `FileCreate` value.
final class LspFileCreate extends LspSchemaValue {
  factory LspFileCreate.fromJson(JsonValue value) {
    return LspFileCreate._(
      LspModelRegistry.instance.validateNamed('FileCreate', value),
    );
  }

  LspFileCreate._(super.value) : super(definitionName: 'FileCreate');
}

/// Validated LSP `FileDelete` value.
final class LspFileDelete extends LspSchemaValue {
  factory LspFileDelete.fromJson(JsonValue value) {
    return LspFileDelete._(
      LspModelRegistry.instance.validateNamed('FileDelete', value),
    );
  }

  LspFileDelete._(super.value) : super(definitionName: 'FileDelete');
}

/// Validated LSP `FileEvent` value.
final class LspFileEvent extends LspSchemaValue {
  factory LspFileEvent.fromJson(JsonValue value) {
    return LspFileEvent._(
      LspModelRegistry.instance.validateNamed('FileEvent', value),
    );
  }

  LspFileEvent._(super.value) : super(definitionName: 'FileEvent');
}

/// Validated LSP `FileOperationClientCapabilities` value.
final class LspFileOperationClientCapabilities extends LspSchemaValue {
  factory LspFileOperationClientCapabilities.fromJson(JsonValue value) {
    return LspFileOperationClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('FileOperationClientCapabilities', value),
    );
  }

  LspFileOperationClientCapabilities._(super.value)
      : super(definitionName: 'FileOperationClientCapabilities');
}

/// Validated LSP `FileOperationFilter` value.
final class LspFileOperationFilter extends LspSchemaValue {
  factory LspFileOperationFilter.fromJson(JsonValue value) {
    return LspFileOperationFilter._(
      LspModelRegistry.instance.validateNamed('FileOperationFilter', value),
    );
  }

  LspFileOperationFilter._(super.value)
      : super(definitionName: 'FileOperationFilter');
}

/// Validated LSP `FileOperationOptions` value.
final class LspFileOperationOptions extends LspSchemaValue {
  factory LspFileOperationOptions.fromJson(JsonValue value) {
    return LspFileOperationOptions._(
      LspModelRegistry.instance.validateNamed('FileOperationOptions', value),
    );
  }

  LspFileOperationOptions._(super.value)
      : super(definitionName: 'FileOperationOptions');
}

/// Validated LSP `FileOperationPattern` value.
final class LspFileOperationPattern extends LspSchemaValue {
  factory LspFileOperationPattern.fromJson(JsonValue value) {
    return LspFileOperationPattern._(
      LspModelRegistry.instance.validateNamed('FileOperationPattern', value),
    );
  }

  LspFileOperationPattern._(super.value)
      : super(definitionName: 'FileOperationPattern');
}

/// Validated LSP `FileOperationPatternKind` value.
final class LspFileOperationPatternKind extends LspSchemaValue {
  factory LspFileOperationPatternKind.fromJson(JsonValue value) {
    return LspFileOperationPatternKind._(
      LspModelRegistry.instance
          .validateNamed('FileOperationPatternKind', value),
    );
  }

  LspFileOperationPatternKind._(super.value)
      : super(definitionName: 'FileOperationPatternKind');
}

/// Validated LSP `FileOperationPatternOptions` value.
final class LspFileOperationPatternOptions extends LspSchemaValue {
  factory LspFileOperationPatternOptions.fromJson(JsonValue value) {
    return LspFileOperationPatternOptions._(
      LspModelRegistry.instance
          .validateNamed('FileOperationPatternOptions', value),
    );
  }

  LspFileOperationPatternOptions._(super.value)
      : super(definitionName: 'FileOperationPatternOptions');
}

/// Validated LSP `FileOperationRegistrationOptions` value.
final class LspFileOperationRegistrationOptions extends LspSchemaValue {
  factory LspFileOperationRegistrationOptions.fromJson(JsonValue value) {
    return LspFileOperationRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('FileOperationRegistrationOptions', value),
    );
  }

  LspFileOperationRegistrationOptions._(super.value)
      : super(definitionName: 'FileOperationRegistrationOptions');
}

/// Validated LSP `FileRename` value.
final class LspFileRename extends LspSchemaValue {
  factory LspFileRename.fromJson(JsonValue value) {
    return LspFileRename._(
      LspModelRegistry.instance.validateNamed('FileRename', value),
    );
  }

  LspFileRename._(super.value) : super(definitionName: 'FileRename');
}

/// Validated LSP `FileSystemWatcher` value.
final class LspFileSystemWatcher extends LspSchemaValue {
  factory LspFileSystemWatcher.fromJson(JsonValue value) {
    return LspFileSystemWatcher._(
      LspModelRegistry.instance.validateNamed('FileSystemWatcher', value),
    );
  }

  LspFileSystemWatcher._(super.value)
      : super(definitionName: 'FileSystemWatcher');
}

/// Validated LSP `FoldingRange` value.
final class LspFoldingRange extends LspSchemaValue {
  factory LspFoldingRange.fromJson(JsonValue value) {
    return LspFoldingRange._(
      LspModelRegistry.instance.validateNamed('FoldingRange', value),
    );
  }

  LspFoldingRange._(super.value) : super(definitionName: 'FoldingRange');
}

/// Validated LSP `FoldingRangeClientCapabilities` value.
final class LspFoldingRangeClientCapabilities extends LspSchemaValue {
  factory LspFoldingRangeClientCapabilities.fromJson(JsonValue value) {
    return LspFoldingRangeClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('FoldingRangeClientCapabilities', value),
    );
  }

  LspFoldingRangeClientCapabilities._(super.value)
      : super(definitionName: 'FoldingRangeClientCapabilities');
}

/// Validated LSP `FoldingRangeKind` value.
final class LspFoldingRangeKind extends LspSchemaValue {
  factory LspFoldingRangeKind.fromJson(JsonValue value) {
    return LspFoldingRangeKind._(
      LspModelRegistry.instance.validateNamed('FoldingRangeKind', value),
    );
  }

  LspFoldingRangeKind._(super.value)
      : super(definitionName: 'FoldingRangeKind');
}

/// Validated LSP `FoldingRangeOptions` value.
final class LspFoldingRangeOptions extends LspSchemaValue {
  factory LspFoldingRangeOptions.fromJson(JsonValue value) {
    return LspFoldingRangeOptions._(
      LspModelRegistry.instance.validateNamed('FoldingRangeOptions', value),
    );
  }

  LspFoldingRangeOptions._(super.value)
      : super(definitionName: 'FoldingRangeOptions');
}

/// Validated LSP `FoldingRangeParams` value.
final class LspFoldingRangeParams extends LspSchemaValue {
  factory LspFoldingRangeParams.fromJson(JsonValue value) {
    return LspFoldingRangeParams._(
      LspModelRegistry.instance.validateNamed('FoldingRangeParams', value),
    );
  }

  LspFoldingRangeParams._(super.value)
      : super(definitionName: 'FoldingRangeParams');
}

/// Validated LSP `FoldingRangeRegistrationOptions` value.
final class LspFoldingRangeRegistrationOptions extends LspSchemaValue {
  factory LspFoldingRangeRegistrationOptions.fromJson(JsonValue value) {
    return LspFoldingRangeRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('FoldingRangeRegistrationOptions', value),
    );
  }

  LspFoldingRangeRegistrationOptions._(super.value)
      : super(definitionName: 'FoldingRangeRegistrationOptions');
}

/// Validated LSP `FoldingRangeWorkspaceClientCapabilities` value.
final class LspFoldingRangeWorkspaceClientCapabilities extends LspSchemaValue {
  factory LspFoldingRangeWorkspaceClientCapabilities.fromJson(JsonValue value) {
    return LspFoldingRangeWorkspaceClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('FoldingRangeWorkspaceClientCapabilities', value),
    );
  }

  LspFoldingRangeWorkspaceClientCapabilities._(super.value)
      : super(definitionName: 'FoldingRangeWorkspaceClientCapabilities');
}

/// Validated LSP `FormattingOptions` value.
final class LspFormattingOptions extends LspSchemaValue {
  factory LspFormattingOptions.fromJson(JsonValue value) {
    return LspFormattingOptions._(
      LspModelRegistry.instance.validateNamed('FormattingOptions', value),
    );
  }

  LspFormattingOptions._(super.value)
      : super(definitionName: 'FormattingOptions');
}

/// Validated LSP `FullDocumentDiagnosticReport` value.
final class LspFullDocumentDiagnosticReport extends LspSchemaValue {
  factory LspFullDocumentDiagnosticReport.fromJson(JsonValue value) {
    return LspFullDocumentDiagnosticReport._(
      LspModelRegistry.instance
          .validateNamed('FullDocumentDiagnosticReport', value),
    );
  }

  LspFullDocumentDiagnosticReport._(super.value)
      : super(definitionName: 'FullDocumentDiagnosticReport');
}

/// Validated LSP `GeneralClientCapabilities` value.
final class LspGeneralClientCapabilities extends LspSchemaValue {
  factory LspGeneralClientCapabilities.fromJson(JsonValue value) {
    return LspGeneralClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('GeneralClientCapabilities', value),
    );
  }

  LspGeneralClientCapabilities._(super.value)
      : super(definitionName: 'GeneralClientCapabilities');
}

/// Validated LSP `GlobPattern` value.
final class LspGlobPattern extends LspSchemaValue {
  factory LspGlobPattern.fromJson(JsonValue value) {
    return LspGlobPattern._(
      LspModelRegistry.instance.validateNamed('GlobPattern', value),
    );
  }

  LspGlobPattern._(super.value) : super(definitionName: 'GlobPattern');
}

/// Validated LSP `Hover` value.
final class LspHover extends LspSchemaValue {
  factory LspHover.fromJson(JsonValue value) {
    return LspHover._(
      LspModelRegistry.instance.validateNamed('Hover', value),
    );
  }

  LspHover._(super.value) : super(definitionName: 'Hover');
}

/// Validated LSP `HoverClientCapabilities` value.
final class LspHoverClientCapabilities extends LspSchemaValue {
  factory LspHoverClientCapabilities.fromJson(JsonValue value) {
    return LspHoverClientCapabilities._(
      LspModelRegistry.instance.validateNamed('HoverClientCapabilities', value),
    );
  }

  LspHoverClientCapabilities._(super.value)
      : super(definitionName: 'HoverClientCapabilities');
}

/// Validated LSP `HoverOptions` value.
final class LspHoverOptions extends LspSchemaValue {
  factory LspHoverOptions.fromJson(JsonValue value) {
    return LspHoverOptions._(
      LspModelRegistry.instance.validateNamed('HoverOptions', value),
    );
  }

  LspHoverOptions._(super.value) : super(definitionName: 'HoverOptions');
}

/// Validated LSP `HoverParams` value.
final class LspHoverParams extends LspSchemaValue {
  factory LspHoverParams.fromJson(JsonValue value) {
    return LspHoverParams._(
      LspModelRegistry.instance.validateNamed('HoverParams', value),
    );
  }

  LspHoverParams._(super.value) : super(definitionName: 'HoverParams');
}

/// Validated LSP `HoverRegistrationOptions` value.
final class LspHoverRegistrationOptions extends LspSchemaValue {
  factory LspHoverRegistrationOptions.fromJson(JsonValue value) {
    return LspHoverRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('HoverRegistrationOptions', value),
    );
  }

  LspHoverRegistrationOptions._(super.value)
      : super(definitionName: 'HoverRegistrationOptions');
}

/// Validated LSP `ImplementationClientCapabilities` value.
final class LspImplementationClientCapabilities extends LspSchemaValue {
  factory LspImplementationClientCapabilities.fromJson(JsonValue value) {
    return LspImplementationClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('ImplementationClientCapabilities', value),
    );
  }

  LspImplementationClientCapabilities._(super.value)
      : super(definitionName: 'ImplementationClientCapabilities');
}

/// Validated LSP `ImplementationOptions` value.
final class LspImplementationOptions extends LspSchemaValue {
  factory LspImplementationOptions.fromJson(JsonValue value) {
    return LspImplementationOptions._(
      LspModelRegistry.instance.validateNamed('ImplementationOptions', value),
    );
  }

  LspImplementationOptions._(super.value)
      : super(definitionName: 'ImplementationOptions');
}

/// Validated LSP `ImplementationParams` value.
final class LspImplementationParams extends LspSchemaValue {
  factory LspImplementationParams.fromJson(JsonValue value) {
    return LspImplementationParams._(
      LspModelRegistry.instance.validateNamed('ImplementationParams', value),
    );
  }

  LspImplementationParams._(super.value)
      : super(definitionName: 'ImplementationParams');
}

/// Validated LSP `ImplementationRegistrationOptions` value.
final class LspImplementationRegistrationOptions extends LspSchemaValue {
  factory LspImplementationRegistrationOptions.fromJson(JsonValue value) {
    return LspImplementationRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('ImplementationRegistrationOptions', value),
    );
  }

  LspImplementationRegistrationOptions._(super.value)
      : super(definitionName: 'ImplementationRegistrationOptions');
}

/// Validated LSP `InitializeError` value.
final class LspInitializeError extends LspSchemaValue {
  factory LspInitializeError.fromJson(JsonValue value) {
    return LspInitializeError._(
      LspModelRegistry.instance.validateNamed('InitializeError', value),
    );
  }

  LspInitializeError._(super.value) : super(definitionName: 'InitializeError');
}

/// Validated LSP `InitializeParams` value.
final class LspInitializeParams extends LspSchemaValue {
  factory LspInitializeParams.fromJson(JsonValue value) {
    return LspInitializeParams._(
      LspModelRegistry.instance.validateNamed('InitializeParams', value),
    );
  }

  LspInitializeParams._(super.value)
      : super(definitionName: 'InitializeParams');
}

/// Validated LSP `InitializeResult` value.
final class LspInitializeResult extends LspSchemaValue {
  factory LspInitializeResult.fromJson(JsonValue value) {
    return LspInitializeResult._(
      LspModelRegistry.instance.validateNamed('InitializeResult', value),
    );
  }

  LspInitializeResult._(super.value)
      : super(definitionName: 'InitializeResult');
}

/// Validated LSP `InitializedParams` value.
final class LspInitializedParams extends LspSchemaValue {
  factory LspInitializedParams.fromJson(JsonValue value) {
    return LspInitializedParams._(
      LspModelRegistry.instance.validateNamed('InitializedParams', value),
    );
  }

  LspInitializedParams._(super.value)
      : super(definitionName: 'InitializedParams');
}

/// Validated LSP `InlayHint` value.
final class LspInlayHint extends LspSchemaValue {
  factory LspInlayHint.fromJson(JsonValue value) {
    return LspInlayHint._(
      LspModelRegistry.instance.validateNamed('InlayHint', value),
    );
  }

  LspInlayHint._(super.value) : super(definitionName: 'InlayHint');
}

/// Validated LSP `InlayHintClientCapabilities` value.
final class LspInlayHintClientCapabilities extends LspSchemaValue {
  factory LspInlayHintClientCapabilities.fromJson(JsonValue value) {
    return LspInlayHintClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('InlayHintClientCapabilities', value),
    );
  }

  LspInlayHintClientCapabilities._(super.value)
      : super(definitionName: 'InlayHintClientCapabilities');
}

/// Validated LSP `InlayHintKind` value.
final class LspInlayHintKind extends LspSchemaValue {
  factory LspInlayHintKind.fromJson(JsonValue value) {
    return LspInlayHintKind._(
      LspModelRegistry.instance.validateNamed('InlayHintKind', value),
    );
  }

  LspInlayHintKind._(super.value) : super(definitionName: 'InlayHintKind');
}

/// Validated LSP `InlayHintLabelPart` value.
final class LspInlayHintLabelPart extends LspSchemaValue {
  factory LspInlayHintLabelPart.fromJson(JsonValue value) {
    return LspInlayHintLabelPart._(
      LspModelRegistry.instance.validateNamed('InlayHintLabelPart', value),
    );
  }

  LspInlayHintLabelPart._(super.value)
      : super(definitionName: 'InlayHintLabelPart');
}

/// Validated LSP `InlayHintOptions` value.
final class LspInlayHintOptions extends LspSchemaValue {
  factory LspInlayHintOptions.fromJson(JsonValue value) {
    return LspInlayHintOptions._(
      LspModelRegistry.instance.validateNamed('InlayHintOptions', value),
    );
  }

  LspInlayHintOptions._(super.value)
      : super(definitionName: 'InlayHintOptions');
}

/// Validated LSP `InlayHintParams` value.
final class LspInlayHintParams extends LspSchemaValue {
  factory LspInlayHintParams.fromJson(JsonValue value) {
    return LspInlayHintParams._(
      LspModelRegistry.instance.validateNamed('InlayHintParams', value),
    );
  }

  LspInlayHintParams._(super.value) : super(definitionName: 'InlayHintParams');
}

/// Validated LSP `InlayHintRegistrationOptions` value.
final class LspInlayHintRegistrationOptions extends LspSchemaValue {
  factory LspInlayHintRegistrationOptions.fromJson(JsonValue value) {
    return LspInlayHintRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('InlayHintRegistrationOptions', value),
    );
  }

  LspInlayHintRegistrationOptions._(super.value)
      : super(definitionName: 'InlayHintRegistrationOptions');
}

/// Validated LSP `InlayHintWorkspaceClientCapabilities` value.
final class LspInlayHintWorkspaceClientCapabilities extends LspSchemaValue {
  factory LspInlayHintWorkspaceClientCapabilities.fromJson(JsonValue value) {
    return LspInlayHintWorkspaceClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('InlayHintWorkspaceClientCapabilities', value),
    );
  }

  LspInlayHintWorkspaceClientCapabilities._(super.value)
      : super(definitionName: 'InlayHintWorkspaceClientCapabilities');
}

/// Validated LSP `InlineCompletionClientCapabilities` value.
final class LspInlineCompletionClientCapabilities extends LspSchemaValue {
  factory LspInlineCompletionClientCapabilities.fromJson(JsonValue value) {
    return LspInlineCompletionClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('InlineCompletionClientCapabilities', value),
    );
  }

  LspInlineCompletionClientCapabilities._(super.value)
      : super(definitionName: 'InlineCompletionClientCapabilities');
}

/// Validated LSP `InlineCompletionContext` value.
final class LspInlineCompletionContext extends LspSchemaValue {
  factory LspInlineCompletionContext.fromJson(JsonValue value) {
    return LspInlineCompletionContext._(
      LspModelRegistry.instance.validateNamed('InlineCompletionContext', value),
    );
  }

  LspInlineCompletionContext._(super.value)
      : super(definitionName: 'InlineCompletionContext');
}

/// Validated LSP `InlineCompletionItem` value.
final class LspInlineCompletionItem extends LspSchemaValue {
  factory LspInlineCompletionItem.fromJson(JsonValue value) {
    return LspInlineCompletionItem._(
      LspModelRegistry.instance.validateNamed('InlineCompletionItem', value),
    );
  }

  LspInlineCompletionItem._(super.value)
      : super(definitionName: 'InlineCompletionItem');
}

/// Validated LSP `InlineCompletionList` value.
final class LspInlineCompletionList extends LspSchemaValue {
  factory LspInlineCompletionList.fromJson(JsonValue value) {
    return LspInlineCompletionList._(
      LspModelRegistry.instance.validateNamed('InlineCompletionList', value),
    );
  }

  LspInlineCompletionList._(super.value)
      : super(definitionName: 'InlineCompletionList');
}

/// Validated LSP `InlineCompletionOptions` value.
final class LspInlineCompletionOptions extends LspSchemaValue {
  factory LspInlineCompletionOptions.fromJson(JsonValue value) {
    return LspInlineCompletionOptions._(
      LspModelRegistry.instance.validateNamed('InlineCompletionOptions', value),
    );
  }

  LspInlineCompletionOptions._(super.value)
      : super(definitionName: 'InlineCompletionOptions');
}

/// Validated LSP `InlineCompletionParams` value.
final class LspInlineCompletionParams extends LspSchemaValue {
  factory LspInlineCompletionParams.fromJson(JsonValue value) {
    return LspInlineCompletionParams._(
      LspModelRegistry.instance.validateNamed('InlineCompletionParams', value),
    );
  }

  LspInlineCompletionParams._(super.value)
      : super(definitionName: 'InlineCompletionParams');
}

/// Validated LSP `InlineCompletionRegistrationOptions` value.
final class LspInlineCompletionRegistrationOptions extends LspSchemaValue {
  factory LspInlineCompletionRegistrationOptions.fromJson(JsonValue value) {
    return LspInlineCompletionRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('InlineCompletionRegistrationOptions', value),
    );
  }

  LspInlineCompletionRegistrationOptions._(super.value)
      : super(definitionName: 'InlineCompletionRegistrationOptions');
}

/// Validated LSP `InlineCompletionTriggerKind` value.
final class LspInlineCompletionTriggerKind extends LspSchemaValue {
  factory LspInlineCompletionTriggerKind.fromJson(JsonValue value) {
    return LspInlineCompletionTriggerKind._(
      LspModelRegistry.instance
          .validateNamed('InlineCompletionTriggerKind', value),
    );
  }

  LspInlineCompletionTriggerKind._(super.value)
      : super(definitionName: 'InlineCompletionTriggerKind');
}

/// Validated LSP `InlineValue` value.
final class LspInlineValue extends LspSchemaValue {
  factory LspInlineValue.fromJson(JsonValue value) {
    return LspInlineValue._(
      LspModelRegistry.instance.validateNamed('InlineValue', value),
    );
  }

  LspInlineValue._(super.value) : super(definitionName: 'InlineValue');
}

/// Validated LSP `InlineValueClientCapabilities` value.
final class LspInlineValueClientCapabilities extends LspSchemaValue {
  factory LspInlineValueClientCapabilities.fromJson(JsonValue value) {
    return LspInlineValueClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('InlineValueClientCapabilities', value),
    );
  }

  LspInlineValueClientCapabilities._(super.value)
      : super(definitionName: 'InlineValueClientCapabilities');
}

/// Validated LSP `InlineValueContext` value.
final class LspInlineValueContext extends LspSchemaValue {
  factory LspInlineValueContext.fromJson(JsonValue value) {
    return LspInlineValueContext._(
      LspModelRegistry.instance.validateNamed('InlineValueContext', value),
    );
  }

  LspInlineValueContext._(super.value)
      : super(definitionName: 'InlineValueContext');
}

/// Validated LSP `InlineValueEvaluatableExpression` value.
final class LspInlineValueEvaluatableExpression extends LspSchemaValue {
  factory LspInlineValueEvaluatableExpression.fromJson(JsonValue value) {
    return LspInlineValueEvaluatableExpression._(
      LspModelRegistry.instance
          .validateNamed('InlineValueEvaluatableExpression', value),
    );
  }

  LspInlineValueEvaluatableExpression._(super.value)
      : super(definitionName: 'InlineValueEvaluatableExpression');
}

/// Validated LSP `InlineValueOptions` value.
final class LspInlineValueOptions extends LspSchemaValue {
  factory LspInlineValueOptions.fromJson(JsonValue value) {
    return LspInlineValueOptions._(
      LspModelRegistry.instance.validateNamed('InlineValueOptions', value),
    );
  }

  LspInlineValueOptions._(super.value)
      : super(definitionName: 'InlineValueOptions');
}

/// Validated LSP `InlineValueParams` value.
final class LspInlineValueParams extends LspSchemaValue {
  factory LspInlineValueParams.fromJson(JsonValue value) {
    return LspInlineValueParams._(
      LspModelRegistry.instance.validateNamed('InlineValueParams', value),
    );
  }

  LspInlineValueParams._(super.value)
      : super(definitionName: 'InlineValueParams');
}

/// Validated LSP `InlineValueRegistrationOptions` value.
final class LspInlineValueRegistrationOptions extends LspSchemaValue {
  factory LspInlineValueRegistrationOptions.fromJson(JsonValue value) {
    return LspInlineValueRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('InlineValueRegistrationOptions', value),
    );
  }

  LspInlineValueRegistrationOptions._(super.value)
      : super(definitionName: 'InlineValueRegistrationOptions');
}

/// Validated LSP `InlineValueText` value.
final class LspInlineValueText extends LspSchemaValue {
  factory LspInlineValueText.fromJson(JsonValue value) {
    return LspInlineValueText._(
      LspModelRegistry.instance.validateNamed('InlineValueText', value),
    );
  }

  LspInlineValueText._(super.value) : super(definitionName: 'InlineValueText');
}

/// Validated LSP `InlineValueVariableLookup` value.
final class LspInlineValueVariableLookup extends LspSchemaValue {
  factory LspInlineValueVariableLookup.fromJson(JsonValue value) {
    return LspInlineValueVariableLookup._(
      LspModelRegistry.instance
          .validateNamed('InlineValueVariableLookup', value),
    );
  }

  LspInlineValueVariableLookup._(super.value)
      : super(definitionName: 'InlineValueVariableLookup');
}

/// Validated LSP `InlineValueWorkspaceClientCapabilities` value.
final class LspInlineValueWorkspaceClientCapabilities extends LspSchemaValue {
  factory LspInlineValueWorkspaceClientCapabilities.fromJson(JsonValue value) {
    return LspInlineValueWorkspaceClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('InlineValueWorkspaceClientCapabilities', value),
    );
  }

  LspInlineValueWorkspaceClientCapabilities._(super.value)
      : super(definitionName: 'InlineValueWorkspaceClientCapabilities');
}

/// Validated LSP `InsertReplaceEdit` value.
final class LspInsertReplaceEdit extends LspSchemaValue {
  factory LspInsertReplaceEdit.fromJson(JsonValue value) {
    return LspInsertReplaceEdit._(
      LspModelRegistry.instance.validateNamed('InsertReplaceEdit', value),
    );
  }

  LspInsertReplaceEdit._(super.value)
      : super(definitionName: 'InsertReplaceEdit');
}

/// Validated LSP `InsertTextFormat` value.
final class LspInsertTextFormat extends LspSchemaValue {
  factory LspInsertTextFormat.fromJson(JsonValue value) {
    return LspInsertTextFormat._(
      LspModelRegistry.instance.validateNamed('InsertTextFormat', value),
    );
  }

  LspInsertTextFormat._(super.value)
      : super(definitionName: 'InsertTextFormat');
}

/// Validated LSP `InsertTextMode` value.
final class LspInsertTextMode extends LspSchemaValue {
  factory LspInsertTextMode.fromJson(JsonValue value) {
    return LspInsertTextMode._(
      LspModelRegistry.instance.validateNamed('InsertTextMode', value),
    );
  }

  LspInsertTextMode._(super.value) : super(definitionName: 'InsertTextMode');
}

/// Validated LSP `LSPAny` value.
final class LspLSPAny extends LspSchemaValue {
  factory LspLSPAny.fromJson(JsonValue value) {
    return LspLSPAny._(
      LspModelRegistry.instance.validateNamed('LSPAny', value),
    );
  }

  LspLSPAny._(super.value) : super(definitionName: 'LSPAny');
}

/// Validated LSP `LSPArray` value.
final class LspLSPArray extends LspSchemaValue {
  factory LspLSPArray.fromJson(JsonValue value) {
    return LspLSPArray._(
      LspModelRegistry.instance.validateNamed('LSPArray', value),
    );
  }

  LspLSPArray._(super.value) : super(definitionName: 'LSPArray');
}

/// Validated LSP `LSPErrorCodes` value.
final class LspLSPErrorCodes extends LspSchemaValue {
  factory LspLSPErrorCodes.fromJson(JsonValue value) {
    return LspLSPErrorCodes._(
      LspModelRegistry.instance.validateNamed('LSPErrorCodes', value),
    );
  }

  LspLSPErrorCodes._(super.value) : super(definitionName: 'LSPErrorCodes');
}

/// Validated LSP `LSPObject` value.
final class LspLSPObject extends LspSchemaValue {
  factory LspLSPObject.fromJson(JsonValue value) {
    return LspLSPObject._(
      LspModelRegistry.instance.validateNamed('LSPObject', value),
    );
  }

  LspLSPObject._(super.value) : super(definitionName: 'LSPObject');
}

/// Validated LSP `LanguageKind` value.
final class LspLanguageKind extends LspSchemaValue {
  factory LspLanguageKind.fromJson(JsonValue value) {
    return LspLanguageKind._(
      LspModelRegistry.instance.validateNamed('LanguageKind', value),
    );
  }

  LspLanguageKind._(super.value) : super(definitionName: 'LanguageKind');
}

/// Validated LSP `LinkedEditingRangeClientCapabilities` value.
final class LspLinkedEditingRangeClientCapabilities extends LspSchemaValue {
  factory LspLinkedEditingRangeClientCapabilities.fromJson(JsonValue value) {
    return LspLinkedEditingRangeClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('LinkedEditingRangeClientCapabilities', value),
    );
  }

  LspLinkedEditingRangeClientCapabilities._(super.value)
      : super(definitionName: 'LinkedEditingRangeClientCapabilities');
}

/// Validated LSP `LinkedEditingRangeOptions` value.
final class LspLinkedEditingRangeOptions extends LspSchemaValue {
  factory LspLinkedEditingRangeOptions.fromJson(JsonValue value) {
    return LspLinkedEditingRangeOptions._(
      LspModelRegistry.instance
          .validateNamed('LinkedEditingRangeOptions', value),
    );
  }

  LspLinkedEditingRangeOptions._(super.value)
      : super(definitionName: 'LinkedEditingRangeOptions');
}

/// Validated LSP `LinkedEditingRangeParams` value.
final class LspLinkedEditingRangeParams extends LspSchemaValue {
  factory LspLinkedEditingRangeParams.fromJson(JsonValue value) {
    return LspLinkedEditingRangeParams._(
      LspModelRegistry.instance
          .validateNamed('LinkedEditingRangeParams', value),
    );
  }

  LspLinkedEditingRangeParams._(super.value)
      : super(definitionName: 'LinkedEditingRangeParams');
}

/// Validated LSP `LinkedEditingRangeRegistrationOptions` value.
final class LspLinkedEditingRangeRegistrationOptions extends LspSchemaValue {
  factory LspLinkedEditingRangeRegistrationOptions.fromJson(JsonValue value) {
    return LspLinkedEditingRangeRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('LinkedEditingRangeRegistrationOptions', value),
    );
  }

  LspLinkedEditingRangeRegistrationOptions._(super.value)
      : super(definitionName: 'LinkedEditingRangeRegistrationOptions');
}

/// Validated LSP `LinkedEditingRanges` value.
final class LspLinkedEditingRanges extends LspSchemaValue {
  factory LspLinkedEditingRanges.fromJson(JsonValue value) {
    return LspLinkedEditingRanges._(
      LspModelRegistry.instance.validateNamed('LinkedEditingRanges', value),
    );
  }

  LspLinkedEditingRanges._(super.value)
      : super(definitionName: 'LinkedEditingRanges');
}

/// Validated LSP `Location` value.
final class LspLocation extends LspSchemaValue {
  factory LspLocation.fromJson(JsonValue value) {
    return LspLocation._(
      LspModelRegistry.instance.validateNamed('Location', value),
    );
  }

  LspLocation._(super.value) : super(definitionName: 'Location');
}

/// Validated LSP `LocationLink` value.
final class LspLocationLink extends LspSchemaValue {
  factory LspLocationLink.fromJson(JsonValue value) {
    return LspLocationLink._(
      LspModelRegistry.instance.validateNamed('LocationLink', value),
    );
  }

  LspLocationLink._(super.value) : super(definitionName: 'LocationLink');
}

/// Validated LSP `LocationUriOnly` value.
final class LspLocationUriOnly extends LspSchemaValue {
  factory LspLocationUriOnly.fromJson(JsonValue value) {
    return LspLocationUriOnly._(
      LspModelRegistry.instance.validateNamed('LocationUriOnly', value),
    );
  }

  LspLocationUriOnly._(super.value) : super(definitionName: 'LocationUriOnly');
}

/// Validated LSP `LogMessageParams` value.
final class LspLogMessageParams extends LspSchemaValue {
  factory LspLogMessageParams.fromJson(JsonValue value) {
    return LspLogMessageParams._(
      LspModelRegistry.instance.validateNamed('LogMessageParams', value),
    );
  }

  LspLogMessageParams._(super.value)
      : super(definitionName: 'LogMessageParams');
}

/// Validated LSP `LogTraceParams` value.
final class LspLogTraceParams extends LspSchemaValue {
  factory LspLogTraceParams.fromJson(JsonValue value) {
    return LspLogTraceParams._(
      LspModelRegistry.instance.validateNamed('LogTraceParams', value),
    );
  }

  LspLogTraceParams._(super.value) : super(definitionName: 'LogTraceParams');
}

/// Validated LSP `MarkdownClientCapabilities` value.
final class LspMarkdownClientCapabilities extends LspSchemaValue {
  factory LspMarkdownClientCapabilities.fromJson(JsonValue value) {
    return LspMarkdownClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('MarkdownClientCapabilities', value),
    );
  }

  LspMarkdownClientCapabilities._(super.value)
      : super(definitionName: 'MarkdownClientCapabilities');
}

/// Validated LSP `MarkedString` value.
final class LspMarkedString extends LspSchemaValue {
  factory LspMarkedString.fromJson(JsonValue value) {
    return LspMarkedString._(
      LspModelRegistry.instance.validateNamed('MarkedString', value),
    );
  }

  LspMarkedString._(super.value) : super(definitionName: 'MarkedString');
}

/// Validated LSP `MarkedStringWithLanguage` value.
final class LspMarkedStringWithLanguage extends LspSchemaValue {
  factory LspMarkedStringWithLanguage.fromJson(JsonValue value) {
    return LspMarkedStringWithLanguage._(
      LspModelRegistry.instance
          .validateNamed('MarkedStringWithLanguage', value),
    );
  }

  LspMarkedStringWithLanguage._(super.value)
      : super(definitionName: 'MarkedStringWithLanguage');
}

/// Validated LSP `MarkupContent` value.
final class LspMarkupContent extends LspSchemaValue {
  factory LspMarkupContent.fromJson(JsonValue value) {
    return LspMarkupContent._(
      LspModelRegistry.instance.validateNamed('MarkupContent', value),
    );
  }

  LspMarkupContent._(super.value) : super(definitionName: 'MarkupContent');
}

/// Validated LSP `MarkupKind` value.
final class LspMarkupKind extends LspSchemaValue {
  factory LspMarkupKind.fromJson(JsonValue value) {
    return LspMarkupKind._(
      LspModelRegistry.instance.validateNamed('MarkupKind', value),
    );
  }

  LspMarkupKind._(super.value) : super(definitionName: 'MarkupKind');
}

/// Validated LSP `MessageActionItem` value.
final class LspMessageActionItem extends LspSchemaValue {
  factory LspMessageActionItem.fromJson(JsonValue value) {
    return LspMessageActionItem._(
      LspModelRegistry.instance.validateNamed('MessageActionItem', value),
    );
  }

  LspMessageActionItem._(super.value)
      : super(definitionName: 'MessageActionItem');
}

/// Validated LSP `MessageType` value.
final class LspMessageType extends LspSchemaValue {
  factory LspMessageType.fromJson(JsonValue value) {
    return LspMessageType._(
      LspModelRegistry.instance.validateNamed('MessageType', value),
    );
  }

  LspMessageType._(super.value) : super(definitionName: 'MessageType');
}

/// Validated LSP `Moniker` value.
final class LspMoniker extends LspSchemaValue {
  factory LspMoniker.fromJson(JsonValue value) {
    return LspMoniker._(
      LspModelRegistry.instance.validateNamed('Moniker', value),
    );
  }

  LspMoniker._(super.value) : super(definitionName: 'Moniker');
}

/// Validated LSP `MonikerClientCapabilities` value.
final class LspMonikerClientCapabilities extends LspSchemaValue {
  factory LspMonikerClientCapabilities.fromJson(JsonValue value) {
    return LspMonikerClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('MonikerClientCapabilities', value),
    );
  }

  LspMonikerClientCapabilities._(super.value)
      : super(definitionName: 'MonikerClientCapabilities');
}

/// Validated LSP `MonikerKind` value.
final class LspMonikerKind extends LspSchemaValue {
  factory LspMonikerKind.fromJson(JsonValue value) {
    return LspMonikerKind._(
      LspModelRegistry.instance.validateNamed('MonikerKind', value),
    );
  }

  LspMonikerKind._(super.value) : super(definitionName: 'MonikerKind');
}

/// Validated LSP `MonikerOptions` value.
final class LspMonikerOptions extends LspSchemaValue {
  factory LspMonikerOptions.fromJson(JsonValue value) {
    return LspMonikerOptions._(
      LspModelRegistry.instance.validateNamed('MonikerOptions', value),
    );
  }

  LspMonikerOptions._(super.value) : super(definitionName: 'MonikerOptions');
}

/// Validated LSP `MonikerParams` value.
final class LspMonikerParams extends LspSchemaValue {
  factory LspMonikerParams.fromJson(JsonValue value) {
    return LspMonikerParams._(
      LspModelRegistry.instance.validateNamed('MonikerParams', value),
    );
  }

  LspMonikerParams._(super.value) : super(definitionName: 'MonikerParams');
}

/// Validated LSP `MonikerRegistrationOptions` value.
final class LspMonikerRegistrationOptions extends LspSchemaValue {
  factory LspMonikerRegistrationOptions.fromJson(JsonValue value) {
    return LspMonikerRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('MonikerRegistrationOptions', value),
    );
  }

  LspMonikerRegistrationOptions._(super.value)
      : super(definitionName: 'MonikerRegistrationOptions');
}

/// Validated LSP `NotebookCell` value.
final class LspNotebookCell extends LspSchemaValue {
  factory LspNotebookCell.fromJson(JsonValue value) {
    return LspNotebookCell._(
      LspModelRegistry.instance.validateNamed('NotebookCell', value),
    );
  }

  LspNotebookCell._(super.value) : super(definitionName: 'NotebookCell');
}

/// Validated LSP `NotebookCellArrayChange` value.
final class LspNotebookCellArrayChange extends LspSchemaValue {
  factory LspNotebookCellArrayChange.fromJson(JsonValue value) {
    return LspNotebookCellArrayChange._(
      LspModelRegistry.instance.validateNamed('NotebookCellArrayChange', value),
    );
  }

  LspNotebookCellArrayChange._(super.value)
      : super(definitionName: 'NotebookCellArrayChange');
}

/// Validated LSP `NotebookCellKind` value.
final class LspNotebookCellKind extends LspSchemaValue {
  factory LspNotebookCellKind.fromJson(JsonValue value) {
    return LspNotebookCellKind._(
      LspModelRegistry.instance.validateNamed('NotebookCellKind', value),
    );
  }

  LspNotebookCellKind._(super.value)
      : super(definitionName: 'NotebookCellKind');
}

/// Validated LSP `NotebookCellLanguage` value.
final class LspNotebookCellLanguage extends LspSchemaValue {
  factory LspNotebookCellLanguage.fromJson(JsonValue value) {
    return LspNotebookCellLanguage._(
      LspModelRegistry.instance.validateNamed('NotebookCellLanguage', value),
    );
  }

  LspNotebookCellLanguage._(super.value)
      : super(definitionName: 'NotebookCellLanguage');
}

/// Validated LSP `NotebookCellTextDocumentFilter` value.
final class LspNotebookCellTextDocumentFilter extends LspSchemaValue {
  factory LspNotebookCellTextDocumentFilter.fromJson(JsonValue value) {
    return LspNotebookCellTextDocumentFilter._(
      LspModelRegistry.instance
          .validateNamed('NotebookCellTextDocumentFilter', value),
    );
  }

  LspNotebookCellTextDocumentFilter._(super.value)
      : super(definitionName: 'NotebookCellTextDocumentFilter');
}

/// Validated LSP `NotebookDocument` value.
final class LspNotebookDocument extends LspSchemaValue {
  factory LspNotebookDocument.fromJson(JsonValue value) {
    return LspNotebookDocument._(
      LspModelRegistry.instance.validateNamed('NotebookDocument', value),
    );
  }

  LspNotebookDocument._(super.value)
      : super(definitionName: 'NotebookDocument');
}

/// Validated LSP `NotebookDocumentCellChangeStructure` value.
final class LspNotebookDocumentCellChangeStructure extends LspSchemaValue {
  factory LspNotebookDocumentCellChangeStructure.fromJson(JsonValue value) {
    return LspNotebookDocumentCellChangeStructure._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentCellChangeStructure', value),
    );
  }

  LspNotebookDocumentCellChangeStructure._(super.value)
      : super(definitionName: 'NotebookDocumentCellChangeStructure');
}

/// Validated LSP `NotebookDocumentCellChanges` value.
final class LspNotebookDocumentCellChanges extends LspSchemaValue {
  factory LspNotebookDocumentCellChanges.fromJson(JsonValue value) {
    return LspNotebookDocumentCellChanges._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentCellChanges', value),
    );
  }

  LspNotebookDocumentCellChanges._(super.value)
      : super(definitionName: 'NotebookDocumentCellChanges');
}

/// Validated LSP `NotebookDocumentCellContentChanges` value.
final class LspNotebookDocumentCellContentChanges extends LspSchemaValue {
  factory LspNotebookDocumentCellContentChanges.fromJson(JsonValue value) {
    return LspNotebookDocumentCellContentChanges._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentCellContentChanges', value),
    );
  }

  LspNotebookDocumentCellContentChanges._(super.value)
      : super(definitionName: 'NotebookDocumentCellContentChanges');
}

/// Validated LSP `NotebookDocumentChangeEvent` value.
final class LspNotebookDocumentChangeEvent extends LspSchemaValue {
  factory LspNotebookDocumentChangeEvent.fromJson(JsonValue value) {
    return LspNotebookDocumentChangeEvent._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentChangeEvent', value),
    );
  }

  LspNotebookDocumentChangeEvent._(super.value)
      : super(definitionName: 'NotebookDocumentChangeEvent');
}

/// Validated LSP `NotebookDocumentClientCapabilities` value.
final class LspNotebookDocumentClientCapabilities extends LspSchemaValue {
  factory LspNotebookDocumentClientCapabilities.fromJson(JsonValue value) {
    return LspNotebookDocumentClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentClientCapabilities', value),
    );
  }

  LspNotebookDocumentClientCapabilities._(super.value)
      : super(definitionName: 'NotebookDocumentClientCapabilities');
}

/// Validated LSP `NotebookDocumentFilter` value.
final class LspNotebookDocumentFilter extends LspSchemaValue {
  factory LspNotebookDocumentFilter.fromJson(JsonValue value) {
    return LspNotebookDocumentFilter._(
      LspModelRegistry.instance.validateNamed('NotebookDocumentFilter', value),
    );
  }

  LspNotebookDocumentFilter._(super.value)
      : super(definitionName: 'NotebookDocumentFilter');
}

/// Validated LSP `NotebookDocumentFilterNotebookType` value.
final class LspNotebookDocumentFilterNotebookType extends LspSchemaValue {
  factory LspNotebookDocumentFilterNotebookType.fromJson(JsonValue value) {
    return LspNotebookDocumentFilterNotebookType._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentFilterNotebookType', value),
    );
  }

  LspNotebookDocumentFilterNotebookType._(super.value)
      : super(definitionName: 'NotebookDocumentFilterNotebookType');
}

/// Validated LSP `NotebookDocumentFilterPattern` value.
final class LspNotebookDocumentFilterPattern extends LspSchemaValue {
  factory LspNotebookDocumentFilterPattern.fromJson(JsonValue value) {
    return LspNotebookDocumentFilterPattern._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentFilterPattern', value),
    );
  }

  LspNotebookDocumentFilterPattern._(super.value)
      : super(definitionName: 'NotebookDocumentFilterPattern');
}

/// Validated LSP `NotebookDocumentFilterScheme` value.
final class LspNotebookDocumentFilterScheme extends LspSchemaValue {
  factory LspNotebookDocumentFilterScheme.fromJson(JsonValue value) {
    return LspNotebookDocumentFilterScheme._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentFilterScheme', value),
    );
  }

  LspNotebookDocumentFilterScheme._(super.value)
      : super(definitionName: 'NotebookDocumentFilterScheme');
}

/// Validated LSP `NotebookDocumentFilterWithCells` value.
final class LspNotebookDocumentFilterWithCells extends LspSchemaValue {
  factory LspNotebookDocumentFilterWithCells.fromJson(JsonValue value) {
    return LspNotebookDocumentFilterWithCells._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentFilterWithCells', value),
    );
  }

  LspNotebookDocumentFilterWithCells._(super.value)
      : super(definitionName: 'NotebookDocumentFilterWithCells');
}

/// Validated LSP `NotebookDocumentFilterWithNotebook` value.
final class LspNotebookDocumentFilterWithNotebook extends LspSchemaValue {
  factory LspNotebookDocumentFilterWithNotebook.fromJson(JsonValue value) {
    return LspNotebookDocumentFilterWithNotebook._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentFilterWithNotebook', value),
    );
  }

  LspNotebookDocumentFilterWithNotebook._(super.value)
      : super(definitionName: 'NotebookDocumentFilterWithNotebook');
}

/// Validated LSP `NotebookDocumentIdentifier` value.
final class LspNotebookDocumentIdentifier extends LspSchemaValue {
  factory LspNotebookDocumentIdentifier.fromJson(JsonValue value) {
    return LspNotebookDocumentIdentifier._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentIdentifier', value),
    );
  }

  LspNotebookDocumentIdentifier._(super.value)
      : super(definitionName: 'NotebookDocumentIdentifier');
}

/// Validated LSP `NotebookDocumentSyncClientCapabilities` value.
final class LspNotebookDocumentSyncClientCapabilities extends LspSchemaValue {
  factory LspNotebookDocumentSyncClientCapabilities.fromJson(JsonValue value) {
    return LspNotebookDocumentSyncClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentSyncClientCapabilities', value),
    );
  }

  LspNotebookDocumentSyncClientCapabilities._(super.value)
      : super(definitionName: 'NotebookDocumentSyncClientCapabilities');
}

/// Validated LSP `NotebookDocumentSyncOptions` value.
final class LspNotebookDocumentSyncOptions extends LspSchemaValue {
  factory LspNotebookDocumentSyncOptions.fromJson(JsonValue value) {
    return LspNotebookDocumentSyncOptions._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentSyncOptions', value),
    );
  }

  LspNotebookDocumentSyncOptions._(super.value)
      : super(definitionName: 'NotebookDocumentSyncOptions');
}

/// Validated LSP `NotebookDocumentSyncRegistrationOptions` value.
final class LspNotebookDocumentSyncRegistrationOptions extends LspSchemaValue {
  factory LspNotebookDocumentSyncRegistrationOptions.fromJson(JsonValue value) {
    return LspNotebookDocumentSyncRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('NotebookDocumentSyncRegistrationOptions', value),
    );
  }

  LspNotebookDocumentSyncRegistrationOptions._(super.value)
      : super(definitionName: 'NotebookDocumentSyncRegistrationOptions');
}

/// Validated LSP `OptionalVersionedTextDocumentIdentifier` value.
final class LspOptionalVersionedTextDocumentIdentifier extends LspSchemaValue {
  factory LspOptionalVersionedTextDocumentIdentifier.fromJson(JsonValue value) {
    return LspOptionalVersionedTextDocumentIdentifier._(
      LspModelRegistry.instance
          .validateNamed('OptionalVersionedTextDocumentIdentifier', value),
    );
  }

  LspOptionalVersionedTextDocumentIdentifier._(super.value)
      : super(definitionName: 'OptionalVersionedTextDocumentIdentifier');
}

/// Validated LSP `ParameterInformation` value.
final class LspParameterInformation extends LspSchemaValue {
  factory LspParameterInformation.fromJson(JsonValue value) {
    return LspParameterInformation._(
      LspModelRegistry.instance.validateNamed('ParameterInformation', value),
    );
  }

  LspParameterInformation._(super.value)
      : super(definitionName: 'ParameterInformation');
}

/// Validated LSP `PartialResultParams` value.
final class LspPartialResultParams extends LspSchemaValue {
  factory LspPartialResultParams.fromJson(JsonValue value) {
    return LspPartialResultParams._(
      LspModelRegistry.instance.validateNamed('PartialResultParams', value),
    );
  }

  LspPartialResultParams._(super.value)
      : super(definitionName: 'PartialResultParams');
}

/// Validated LSP `Pattern` value.
final class LspPattern extends LspSchemaValue {
  factory LspPattern.fromJson(JsonValue value) {
    return LspPattern._(
      LspModelRegistry.instance.validateNamed('Pattern', value),
    );
  }

  LspPattern._(super.value) : super(definitionName: 'Pattern');
}

/// Validated LSP `Position` value.
final class LspPosition extends LspSchemaValue {
  factory LspPosition.fromJson(JsonValue value) {
    return LspPosition._(
      LspModelRegistry.instance.validateNamed('Position', value),
    );
  }

  LspPosition._(super.value) : super(definitionName: 'Position');
}

/// Validated LSP `PositionEncodingKind` value.
final class LspPositionEncodingKind extends LspSchemaValue {
  factory LspPositionEncodingKind.fromJson(JsonValue value) {
    return LspPositionEncodingKind._(
      LspModelRegistry.instance.validateNamed('PositionEncodingKind', value),
    );
  }

  LspPositionEncodingKind._(super.value)
      : super(definitionName: 'PositionEncodingKind');
}

/// Validated LSP `PrepareRenameDefaultBehavior` value.
final class LspPrepareRenameDefaultBehavior extends LspSchemaValue {
  factory LspPrepareRenameDefaultBehavior.fromJson(JsonValue value) {
    return LspPrepareRenameDefaultBehavior._(
      LspModelRegistry.instance
          .validateNamed('PrepareRenameDefaultBehavior', value),
    );
  }

  LspPrepareRenameDefaultBehavior._(super.value)
      : super(definitionName: 'PrepareRenameDefaultBehavior');
}

/// Validated LSP `PrepareRenameParams` value.
final class LspPrepareRenameParams extends LspSchemaValue {
  factory LspPrepareRenameParams.fromJson(JsonValue value) {
    return LspPrepareRenameParams._(
      LspModelRegistry.instance.validateNamed('PrepareRenameParams', value),
    );
  }

  LspPrepareRenameParams._(super.value)
      : super(definitionName: 'PrepareRenameParams');
}

/// Validated LSP `PrepareRenamePlaceholder` value.
final class LspPrepareRenamePlaceholder extends LspSchemaValue {
  factory LspPrepareRenamePlaceholder.fromJson(JsonValue value) {
    return LspPrepareRenamePlaceholder._(
      LspModelRegistry.instance
          .validateNamed('PrepareRenamePlaceholder', value),
    );
  }

  LspPrepareRenamePlaceholder._(super.value)
      : super(definitionName: 'PrepareRenamePlaceholder');
}

/// Validated LSP `PrepareRenameResult` value.
final class LspPrepareRenameResult extends LspSchemaValue {
  factory LspPrepareRenameResult.fromJson(JsonValue value) {
    return LspPrepareRenameResult._(
      LspModelRegistry.instance.validateNamed('PrepareRenameResult', value),
    );
  }

  LspPrepareRenameResult._(super.value)
      : super(definitionName: 'PrepareRenameResult');
}

/// Validated LSP `PrepareSupportDefaultBehavior` value.
final class LspPrepareSupportDefaultBehavior extends LspSchemaValue {
  factory LspPrepareSupportDefaultBehavior.fromJson(JsonValue value) {
    return LspPrepareSupportDefaultBehavior._(
      LspModelRegistry.instance
          .validateNamed('PrepareSupportDefaultBehavior', value),
    );
  }

  LspPrepareSupportDefaultBehavior._(super.value)
      : super(definitionName: 'PrepareSupportDefaultBehavior');
}

/// Validated LSP `PreviousResultId` value.
final class LspPreviousResultId extends LspSchemaValue {
  factory LspPreviousResultId.fromJson(JsonValue value) {
    return LspPreviousResultId._(
      LspModelRegistry.instance.validateNamed('PreviousResultId', value),
    );
  }

  LspPreviousResultId._(super.value)
      : super(definitionName: 'PreviousResultId');
}

/// Validated LSP `ProgressParams` value.
final class LspProgressParams extends LspSchemaValue {
  factory LspProgressParams.fromJson(JsonValue value) {
    return LspProgressParams._(
      LspModelRegistry.instance.validateNamed('ProgressParams', value),
    );
  }

  LspProgressParams._(super.value) : super(definitionName: 'ProgressParams');
}

/// Validated LSP `ProgressToken` value.
final class LspProgressToken extends LspSchemaValue {
  factory LspProgressToken.fromJson(JsonValue value) {
    return LspProgressToken._(
      LspModelRegistry.instance.validateNamed('ProgressToken', value),
    );
  }

  LspProgressToken._(super.value) : super(definitionName: 'ProgressToken');
}

/// Validated LSP `PublishDiagnosticsClientCapabilities` value.
final class LspPublishDiagnosticsClientCapabilities extends LspSchemaValue {
  factory LspPublishDiagnosticsClientCapabilities.fromJson(JsonValue value) {
    return LspPublishDiagnosticsClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('PublishDiagnosticsClientCapabilities', value),
    );
  }

  LspPublishDiagnosticsClientCapabilities._(super.value)
      : super(definitionName: 'PublishDiagnosticsClientCapabilities');
}

/// Validated LSP `PublishDiagnosticsParams` value.
final class LspPublishDiagnosticsParams extends LspSchemaValue {
  factory LspPublishDiagnosticsParams.fromJson(JsonValue value) {
    return LspPublishDiagnosticsParams._(
      LspModelRegistry.instance
          .validateNamed('PublishDiagnosticsParams', value),
    );
  }

  LspPublishDiagnosticsParams._(super.value)
      : super(definitionName: 'PublishDiagnosticsParams');
}

/// Validated LSP `Range` value.
final class LspRange extends LspSchemaValue {
  factory LspRange.fromJson(JsonValue value) {
    return LspRange._(
      LspModelRegistry.instance.validateNamed('Range', value),
    );
  }

  LspRange._(super.value) : super(definitionName: 'Range');
}

/// Validated LSP `ReferenceClientCapabilities` value.
final class LspReferenceClientCapabilities extends LspSchemaValue {
  factory LspReferenceClientCapabilities.fromJson(JsonValue value) {
    return LspReferenceClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('ReferenceClientCapabilities', value),
    );
  }

  LspReferenceClientCapabilities._(super.value)
      : super(definitionName: 'ReferenceClientCapabilities');
}

/// Validated LSP `ReferenceContext` value.
final class LspReferenceContext extends LspSchemaValue {
  factory LspReferenceContext.fromJson(JsonValue value) {
    return LspReferenceContext._(
      LspModelRegistry.instance.validateNamed('ReferenceContext', value),
    );
  }

  LspReferenceContext._(super.value)
      : super(definitionName: 'ReferenceContext');
}

/// Validated LSP `ReferenceOptions` value.
final class LspReferenceOptions extends LspSchemaValue {
  factory LspReferenceOptions.fromJson(JsonValue value) {
    return LspReferenceOptions._(
      LspModelRegistry.instance.validateNamed('ReferenceOptions', value),
    );
  }

  LspReferenceOptions._(super.value)
      : super(definitionName: 'ReferenceOptions');
}

/// Validated LSP `ReferenceParams` value.
final class LspReferenceParams extends LspSchemaValue {
  factory LspReferenceParams.fromJson(JsonValue value) {
    return LspReferenceParams._(
      LspModelRegistry.instance.validateNamed('ReferenceParams', value),
    );
  }

  LspReferenceParams._(super.value) : super(definitionName: 'ReferenceParams');
}

/// Validated LSP `ReferenceRegistrationOptions` value.
final class LspReferenceRegistrationOptions extends LspSchemaValue {
  factory LspReferenceRegistrationOptions.fromJson(JsonValue value) {
    return LspReferenceRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('ReferenceRegistrationOptions', value),
    );
  }

  LspReferenceRegistrationOptions._(super.value)
      : super(definitionName: 'ReferenceRegistrationOptions');
}

/// Validated LSP `Registration` value.
final class LspRegistration extends LspSchemaValue {
  factory LspRegistration.fromJson(JsonValue value) {
    return LspRegistration._(
      LspModelRegistry.instance.validateNamed('Registration', value),
    );
  }

  LspRegistration._(super.value) : super(definitionName: 'Registration');
}

/// Validated LSP `RegistrationParams` value.
final class LspRegistrationParams extends LspSchemaValue {
  factory LspRegistrationParams.fromJson(JsonValue value) {
    return LspRegistrationParams._(
      LspModelRegistry.instance.validateNamed('RegistrationParams', value),
    );
  }

  LspRegistrationParams._(super.value)
      : super(definitionName: 'RegistrationParams');
}

/// Validated LSP `RegularExpressionEngineKind` value.
final class LspRegularExpressionEngineKind extends LspSchemaValue {
  factory LspRegularExpressionEngineKind.fromJson(JsonValue value) {
    return LspRegularExpressionEngineKind._(
      LspModelRegistry.instance
          .validateNamed('RegularExpressionEngineKind', value),
    );
  }

  LspRegularExpressionEngineKind._(super.value)
      : super(definitionName: 'RegularExpressionEngineKind');
}

/// Validated LSP `RegularExpressionsClientCapabilities` value.
final class LspRegularExpressionsClientCapabilities extends LspSchemaValue {
  factory LspRegularExpressionsClientCapabilities.fromJson(JsonValue value) {
    return LspRegularExpressionsClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('RegularExpressionsClientCapabilities', value),
    );
  }

  LspRegularExpressionsClientCapabilities._(super.value)
      : super(definitionName: 'RegularExpressionsClientCapabilities');
}

/// Validated LSP `RelatedFullDocumentDiagnosticReport` value.
final class LspRelatedFullDocumentDiagnosticReport extends LspSchemaValue {
  factory LspRelatedFullDocumentDiagnosticReport.fromJson(JsonValue value) {
    return LspRelatedFullDocumentDiagnosticReport._(
      LspModelRegistry.instance
          .validateNamed('RelatedFullDocumentDiagnosticReport', value),
    );
  }

  LspRelatedFullDocumentDiagnosticReport._(super.value)
      : super(definitionName: 'RelatedFullDocumentDiagnosticReport');
}

/// Validated LSP `RelatedUnchangedDocumentDiagnosticReport` value.
final class LspRelatedUnchangedDocumentDiagnosticReport extends LspSchemaValue {
  factory LspRelatedUnchangedDocumentDiagnosticReport.fromJson(
      JsonValue value) {
    return LspRelatedUnchangedDocumentDiagnosticReport._(
      LspModelRegistry.instance
          .validateNamed('RelatedUnchangedDocumentDiagnosticReport', value),
    );
  }

  LspRelatedUnchangedDocumentDiagnosticReport._(super.value)
      : super(definitionName: 'RelatedUnchangedDocumentDiagnosticReport');
}

/// Validated LSP `RelativePattern` value.
final class LspRelativePattern extends LspSchemaValue {
  factory LspRelativePattern.fromJson(JsonValue value) {
    return LspRelativePattern._(
      LspModelRegistry.instance.validateNamed('RelativePattern', value),
    );
  }

  LspRelativePattern._(super.value) : super(definitionName: 'RelativePattern');
}

/// Validated LSP `RenameClientCapabilities` value.
final class LspRenameClientCapabilities extends LspSchemaValue {
  factory LspRenameClientCapabilities.fromJson(JsonValue value) {
    return LspRenameClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('RenameClientCapabilities', value),
    );
  }

  LspRenameClientCapabilities._(super.value)
      : super(definitionName: 'RenameClientCapabilities');
}

/// Validated LSP `RenameFile` value.
final class LspRenameFile extends LspSchemaValue {
  factory LspRenameFile.fromJson(JsonValue value) {
    return LspRenameFile._(
      LspModelRegistry.instance.validateNamed('RenameFile', value),
    );
  }

  LspRenameFile._(super.value) : super(definitionName: 'RenameFile');
}

/// Validated LSP `RenameFileOptions` value.
final class LspRenameFileOptions extends LspSchemaValue {
  factory LspRenameFileOptions.fromJson(JsonValue value) {
    return LspRenameFileOptions._(
      LspModelRegistry.instance.validateNamed('RenameFileOptions', value),
    );
  }

  LspRenameFileOptions._(super.value)
      : super(definitionName: 'RenameFileOptions');
}

/// Validated LSP `RenameFilesParams` value.
final class LspRenameFilesParams extends LspSchemaValue {
  factory LspRenameFilesParams.fromJson(JsonValue value) {
    return LspRenameFilesParams._(
      LspModelRegistry.instance.validateNamed('RenameFilesParams', value),
    );
  }

  LspRenameFilesParams._(super.value)
      : super(definitionName: 'RenameFilesParams');
}

/// Validated LSP `RenameOptions` value.
final class LspRenameOptions extends LspSchemaValue {
  factory LspRenameOptions.fromJson(JsonValue value) {
    return LspRenameOptions._(
      LspModelRegistry.instance.validateNamed('RenameOptions', value),
    );
  }

  LspRenameOptions._(super.value) : super(definitionName: 'RenameOptions');
}

/// Validated LSP `RenameParams` value.
final class LspRenameParams extends LspSchemaValue {
  factory LspRenameParams.fromJson(JsonValue value) {
    return LspRenameParams._(
      LspModelRegistry.instance.validateNamed('RenameParams', value),
    );
  }

  LspRenameParams._(super.value) : super(definitionName: 'RenameParams');
}

/// Validated LSP `RenameRegistrationOptions` value.
final class LspRenameRegistrationOptions extends LspSchemaValue {
  factory LspRenameRegistrationOptions.fromJson(JsonValue value) {
    return LspRenameRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('RenameRegistrationOptions', value),
    );
  }

  LspRenameRegistrationOptions._(super.value)
      : super(definitionName: 'RenameRegistrationOptions');
}

/// Validated LSP `ResourceOperation` value.
final class LspResourceOperation extends LspSchemaValue {
  factory LspResourceOperation.fromJson(JsonValue value) {
    return LspResourceOperation._(
      LspModelRegistry.instance.validateNamed('ResourceOperation', value),
    );
  }

  LspResourceOperation._(super.value)
      : super(definitionName: 'ResourceOperation');
}

/// Validated LSP `ResourceOperationKind` value.
final class LspResourceOperationKind extends LspSchemaValue {
  factory LspResourceOperationKind.fromJson(JsonValue value) {
    return LspResourceOperationKind._(
      LspModelRegistry.instance.validateNamed('ResourceOperationKind', value),
    );
  }

  LspResourceOperationKind._(super.value)
      : super(definitionName: 'ResourceOperationKind');
}

/// Validated LSP `SaveOptions` value.
final class LspSaveOptions extends LspSchemaValue {
  factory LspSaveOptions.fromJson(JsonValue value) {
    return LspSaveOptions._(
      LspModelRegistry.instance.validateNamed('SaveOptions', value),
    );
  }

  LspSaveOptions._(super.value) : super(definitionName: 'SaveOptions');
}

/// Validated LSP `SelectedCompletionInfo` value.
final class LspSelectedCompletionInfo extends LspSchemaValue {
  factory LspSelectedCompletionInfo.fromJson(JsonValue value) {
    return LspSelectedCompletionInfo._(
      LspModelRegistry.instance.validateNamed('SelectedCompletionInfo', value),
    );
  }

  LspSelectedCompletionInfo._(super.value)
      : super(definitionName: 'SelectedCompletionInfo');
}

/// Validated LSP `SelectionRange` value.
final class LspSelectionRange extends LspSchemaValue {
  factory LspSelectionRange.fromJson(JsonValue value) {
    return LspSelectionRange._(
      LspModelRegistry.instance.validateNamed('SelectionRange', value),
    );
  }

  LspSelectionRange._(super.value) : super(definitionName: 'SelectionRange');
}

/// Validated LSP `SelectionRangeClientCapabilities` value.
final class LspSelectionRangeClientCapabilities extends LspSchemaValue {
  factory LspSelectionRangeClientCapabilities.fromJson(JsonValue value) {
    return LspSelectionRangeClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('SelectionRangeClientCapabilities', value),
    );
  }

  LspSelectionRangeClientCapabilities._(super.value)
      : super(definitionName: 'SelectionRangeClientCapabilities');
}

/// Validated LSP `SelectionRangeOptions` value.
final class LspSelectionRangeOptions extends LspSchemaValue {
  factory LspSelectionRangeOptions.fromJson(JsonValue value) {
    return LspSelectionRangeOptions._(
      LspModelRegistry.instance.validateNamed('SelectionRangeOptions', value),
    );
  }

  LspSelectionRangeOptions._(super.value)
      : super(definitionName: 'SelectionRangeOptions');
}

/// Validated LSP `SelectionRangeParams` value.
final class LspSelectionRangeParams extends LspSchemaValue {
  factory LspSelectionRangeParams.fromJson(JsonValue value) {
    return LspSelectionRangeParams._(
      LspModelRegistry.instance.validateNamed('SelectionRangeParams', value),
    );
  }

  LspSelectionRangeParams._(super.value)
      : super(definitionName: 'SelectionRangeParams');
}

/// Validated LSP `SelectionRangeRegistrationOptions` value.
final class LspSelectionRangeRegistrationOptions extends LspSchemaValue {
  factory LspSelectionRangeRegistrationOptions.fromJson(JsonValue value) {
    return LspSelectionRangeRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('SelectionRangeRegistrationOptions', value),
    );
  }

  LspSelectionRangeRegistrationOptions._(super.value)
      : super(definitionName: 'SelectionRangeRegistrationOptions');
}

/// Validated LSP `SemanticTokenModifiers` value.
final class LspSemanticTokenModifiers extends LspSchemaValue {
  factory LspSemanticTokenModifiers.fromJson(JsonValue value) {
    return LspSemanticTokenModifiers._(
      LspModelRegistry.instance.validateNamed('SemanticTokenModifiers', value),
    );
  }

  LspSemanticTokenModifiers._(super.value)
      : super(definitionName: 'SemanticTokenModifiers');
}

/// Validated LSP `SemanticTokenTypes` value.
final class LspSemanticTokenTypes extends LspSchemaValue {
  factory LspSemanticTokenTypes.fromJson(JsonValue value) {
    return LspSemanticTokenTypes._(
      LspModelRegistry.instance.validateNamed('SemanticTokenTypes', value),
    );
  }

  LspSemanticTokenTypes._(super.value)
      : super(definitionName: 'SemanticTokenTypes');
}

/// Validated LSP `SemanticTokens` value.
final class LspSemanticTokens extends LspSchemaValue {
  factory LspSemanticTokens.fromJson(JsonValue value) {
    return LspSemanticTokens._(
      LspModelRegistry.instance.validateNamed('SemanticTokens', value),
    );
  }

  LspSemanticTokens._(super.value) : super(definitionName: 'SemanticTokens');
}

/// Validated LSP `SemanticTokensClientCapabilities` value.
final class LspSemanticTokensClientCapabilities extends LspSchemaValue {
  factory LspSemanticTokensClientCapabilities.fromJson(JsonValue value) {
    return LspSemanticTokensClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('SemanticTokensClientCapabilities', value),
    );
  }

  LspSemanticTokensClientCapabilities._(super.value)
      : super(definitionName: 'SemanticTokensClientCapabilities');
}

/// Validated LSP `SemanticTokensDelta` value.
final class LspSemanticTokensDelta extends LspSchemaValue {
  factory LspSemanticTokensDelta.fromJson(JsonValue value) {
    return LspSemanticTokensDelta._(
      LspModelRegistry.instance.validateNamed('SemanticTokensDelta', value),
    );
  }

  LspSemanticTokensDelta._(super.value)
      : super(definitionName: 'SemanticTokensDelta');
}

/// Validated LSP `SemanticTokensDeltaParams` value.
final class LspSemanticTokensDeltaParams extends LspSchemaValue {
  factory LspSemanticTokensDeltaParams.fromJson(JsonValue value) {
    return LspSemanticTokensDeltaParams._(
      LspModelRegistry.instance
          .validateNamed('SemanticTokensDeltaParams', value),
    );
  }

  LspSemanticTokensDeltaParams._(super.value)
      : super(definitionName: 'SemanticTokensDeltaParams');
}

/// Validated LSP `SemanticTokensDeltaPartialResult` value.
final class LspSemanticTokensDeltaPartialResult extends LspSchemaValue {
  factory LspSemanticTokensDeltaPartialResult.fromJson(JsonValue value) {
    return LspSemanticTokensDeltaPartialResult._(
      LspModelRegistry.instance
          .validateNamed('SemanticTokensDeltaPartialResult', value),
    );
  }

  LspSemanticTokensDeltaPartialResult._(super.value)
      : super(definitionName: 'SemanticTokensDeltaPartialResult');
}

/// Validated LSP `SemanticTokensEdit` value.
final class LspSemanticTokensEdit extends LspSchemaValue {
  factory LspSemanticTokensEdit.fromJson(JsonValue value) {
    return LspSemanticTokensEdit._(
      LspModelRegistry.instance.validateNamed('SemanticTokensEdit', value),
    );
  }

  LspSemanticTokensEdit._(super.value)
      : super(definitionName: 'SemanticTokensEdit');
}

/// Validated LSP `SemanticTokensFullDelta` value.
final class LspSemanticTokensFullDelta extends LspSchemaValue {
  factory LspSemanticTokensFullDelta.fromJson(JsonValue value) {
    return LspSemanticTokensFullDelta._(
      LspModelRegistry.instance.validateNamed('SemanticTokensFullDelta', value),
    );
  }

  LspSemanticTokensFullDelta._(super.value)
      : super(definitionName: 'SemanticTokensFullDelta');
}

/// Validated LSP `SemanticTokensLegend` value.
final class LspSemanticTokensLegend extends LspSchemaValue {
  factory LspSemanticTokensLegend.fromJson(JsonValue value) {
    return LspSemanticTokensLegend._(
      LspModelRegistry.instance.validateNamed('SemanticTokensLegend', value),
    );
  }

  LspSemanticTokensLegend._(super.value)
      : super(definitionName: 'SemanticTokensLegend');
}

/// Validated LSP `SemanticTokensOptions` value.
final class LspSemanticTokensOptions extends LspSchemaValue {
  factory LspSemanticTokensOptions.fromJson(JsonValue value) {
    return LspSemanticTokensOptions._(
      LspModelRegistry.instance.validateNamed('SemanticTokensOptions', value),
    );
  }

  LspSemanticTokensOptions._(super.value)
      : super(definitionName: 'SemanticTokensOptions');
}

/// Validated LSP `SemanticTokensParams` value.
final class LspSemanticTokensParams extends LspSchemaValue {
  factory LspSemanticTokensParams.fromJson(JsonValue value) {
    return LspSemanticTokensParams._(
      LspModelRegistry.instance.validateNamed('SemanticTokensParams', value),
    );
  }

  LspSemanticTokensParams._(super.value)
      : super(definitionName: 'SemanticTokensParams');
}

/// Validated LSP `SemanticTokensPartialResult` value.
final class LspSemanticTokensPartialResult extends LspSchemaValue {
  factory LspSemanticTokensPartialResult.fromJson(JsonValue value) {
    return LspSemanticTokensPartialResult._(
      LspModelRegistry.instance
          .validateNamed('SemanticTokensPartialResult', value),
    );
  }

  LspSemanticTokensPartialResult._(super.value)
      : super(definitionName: 'SemanticTokensPartialResult');
}

/// Validated LSP `SemanticTokensRangeParams` value.
final class LspSemanticTokensRangeParams extends LspSchemaValue {
  factory LspSemanticTokensRangeParams.fromJson(JsonValue value) {
    return LspSemanticTokensRangeParams._(
      LspModelRegistry.instance
          .validateNamed('SemanticTokensRangeParams', value),
    );
  }

  LspSemanticTokensRangeParams._(super.value)
      : super(definitionName: 'SemanticTokensRangeParams');
}

/// Validated LSP `SemanticTokensRegistrationOptions` value.
final class LspSemanticTokensRegistrationOptions extends LspSchemaValue {
  factory LspSemanticTokensRegistrationOptions.fromJson(JsonValue value) {
    return LspSemanticTokensRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('SemanticTokensRegistrationOptions', value),
    );
  }

  LspSemanticTokensRegistrationOptions._(super.value)
      : super(definitionName: 'SemanticTokensRegistrationOptions');
}

/// Validated LSP `SemanticTokensWorkspaceClientCapabilities` value.
final class LspSemanticTokensWorkspaceClientCapabilities
    extends LspSchemaValue {
  factory LspSemanticTokensWorkspaceClientCapabilities.fromJson(
      JsonValue value) {
    return LspSemanticTokensWorkspaceClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('SemanticTokensWorkspaceClientCapabilities', value),
    );
  }

  LspSemanticTokensWorkspaceClientCapabilities._(super.value)
      : super(definitionName: 'SemanticTokensWorkspaceClientCapabilities');
}

/// Validated LSP `ServerCapabilities` value.
final class LspServerCapabilities extends LspSchemaValue {
  factory LspServerCapabilities.fromJson(JsonValue value) {
    return LspServerCapabilities._(
      LspModelRegistry.instance.validateNamed('ServerCapabilities', value),
    );
  }

  LspServerCapabilities._(super.value)
      : super(definitionName: 'ServerCapabilities');
}

/// Validated LSP `ServerCompletionItemOptions` value.
final class LspServerCompletionItemOptions extends LspSchemaValue {
  factory LspServerCompletionItemOptions.fromJson(JsonValue value) {
    return LspServerCompletionItemOptions._(
      LspModelRegistry.instance
          .validateNamed('ServerCompletionItemOptions', value),
    );
  }

  LspServerCompletionItemOptions._(super.value)
      : super(definitionName: 'ServerCompletionItemOptions');
}

/// Validated LSP `ServerInfo` value.
final class LspServerInfo extends LspSchemaValue {
  factory LspServerInfo.fromJson(JsonValue value) {
    return LspServerInfo._(
      LspModelRegistry.instance.validateNamed('ServerInfo', value),
    );
  }

  LspServerInfo._(super.value) : super(definitionName: 'ServerInfo');
}

/// Validated LSP `SetTraceParams` value.
final class LspSetTraceParams extends LspSchemaValue {
  factory LspSetTraceParams.fromJson(JsonValue value) {
    return LspSetTraceParams._(
      LspModelRegistry.instance.validateNamed('SetTraceParams', value),
    );
  }

  LspSetTraceParams._(super.value) : super(definitionName: 'SetTraceParams');
}

/// Validated LSP `ShowDocumentClientCapabilities` value.
final class LspShowDocumentClientCapabilities extends LspSchemaValue {
  factory LspShowDocumentClientCapabilities.fromJson(JsonValue value) {
    return LspShowDocumentClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('ShowDocumentClientCapabilities', value),
    );
  }

  LspShowDocumentClientCapabilities._(super.value)
      : super(definitionName: 'ShowDocumentClientCapabilities');
}

/// Validated LSP `ShowDocumentParams` value.
final class LspShowDocumentParams extends LspSchemaValue {
  factory LspShowDocumentParams.fromJson(JsonValue value) {
    return LspShowDocumentParams._(
      LspModelRegistry.instance.validateNamed('ShowDocumentParams', value),
    );
  }

  LspShowDocumentParams._(super.value)
      : super(definitionName: 'ShowDocumentParams');
}

/// Validated LSP `ShowDocumentResult` value.
final class LspShowDocumentResult extends LspSchemaValue {
  factory LspShowDocumentResult.fromJson(JsonValue value) {
    return LspShowDocumentResult._(
      LspModelRegistry.instance.validateNamed('ShowDocumentResult', value),
    );
  }

  LspShowDocumentResult._(super.value)
      : super(definitionName: 'ShowDocumentResult');
}

/// Validated LSP `ShowMessageParams` value.
final class LspShowMessageParams extends LspSchemaValue {
  factory LspShowMessageParams.fromJson(JsonValue value) {
    return LspShowMessageParams._(
      LspModelRegistry.instance.validateNamed('ShowMessageParams', value),
    );
  }

  LspShowMessageParams._(super.value)
      : super(definitionName: 'ShowMessageParams');
}

/// Validated LSP `ShowMessageRequestClientCapabilities` value.
final class LspShowMessageRequestClientCapabilities extends LspSchemaValue {
  factory LspShowMessageRequestClientCapabilities.fromJson(JsonValue value) {
    return LspShowMessageRequestClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('ShowMessageRequestClientCapabilities', value),
    );
  }

  LspShowMessageRequestClientCapabilities._(super.value)
      : super(definitionName: 'ShowMessageRequestClientCapabilities');
}

/// Validated LSP `ShowMessageRequestParams` value.
final class LspShowMessageRequestParams extends LspSchemaValue {
  factory LspShowMessageRequestParams.fromJson(JsonValue value) {
    return LspShowMessageRequestParams._(
      LspModelRegistry.instance
          .validateNamed('ShowMessageRequestParams', value),
    );
  }

  LspShowMessageRequestParams._(super.value)
      : super(definitionName: 'ShowMessageRequestParams');
}

/// Validated LSP `SignatureHelp` value.
final class LspSignatureHelp extends LspSchemaValue {
  factory LspSignatureHelp.fromJson(JsonValue value) {
    return LspSignatureHelp._(
      LspModelRegistry.instance.validateNamed('SignatureHelp', value),
    );
  }

  LspSignatureHelp._(super.value) : super(definitionName: 'SignatureHelp');
}

/// Validated LSP `SignatureHelpClientCapabilities` value.
final class LspSignatureHelpClientCapabilities extends LspSchemaValue {
  factory LspSignatureHelpClientCapabilities.fromJson(JsonValue value) {
    return LspSignatureHelpClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('SignatureHelpClientCapabilities', value),
    );
  }

  LspSignatureHelpClientCapabilities._(super.value)
      : super(definitionName: 'SignatureHelpClientCapabilities');
}

/// Validated LSP `SignatureHelpContext` value.
final class LspSignatureHelpContext extends LspSchemaValue {
  factory LspSignatureHelpContext.fromJson(JsonValue value) {
    return LspSignatureHelpContext._(
      LspModelRegistry.instance.validateNamed('SignatureHelpContext', value),
    );
  }

  LspSignatureHelpContext._(super.value)
      : super(definitionName: 'SignatureHelpContext');
}

/// Validated LSP `SignatureHelpOptions` value.
final class LspSignatureHelpOptions extends LspSchemaValue {
  factory LspSignatureHelpOptions.fromJson(JsonValue value) {
    return LspSignatureHelpOptions._(
      LspModelRegistry.instance.validateNamed('SignatureHelpOptions', value),
    );
  }

  LspSignatureHelpOptions._(super.value)
      : super(definitionName: 'SignatureHelpOptions');
}

/// Validated LSP `SignatureHelpParams` value.
final class LspSignatureHelpParams extends LspSchemaValue {
  factory LspSignatureHelpParams.fromJson(JsonValue value) {
    return LspSignatureHelpParams._(
      LspModelRegistry.instance.validateNamed('SignatureHelpParams', value),
    );
  }

  LspSignatureHelpParams._(super.value)
      : super(definitionName: 'SignatureHelpParams');
}

/// Validated LSP `SignatureHelpRegistrationOptions` value.
final class LspSignatureHelpRegistrationOptions extends LspSchemaValue {
  factory LspSignatureHelpRegistrationOptions.fromJson(JsonValue value) {
    return LspSignatureHelpRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('SignatureHelpRegistrationOptions', value),
    );
  }

  LspSignatureHelpRegistrationOptions._(super.value)
      : super(definitionName: 'SignatureHelpRegistrationOptions');
}

/// Validated LSP `SignatureHelpTriggerKind` value.
final class LspSignatureHelpTriggerKind extends LspSchemaValue {
  factory LspSignatureHelpTriggerKind.fromJson(JsonValue value) {
    return LspSignatureHelpTriggerKind._(
      LspModelRegistry.instance
          .validateNamed('SignatureHelpTriggerKind', value),
    );
  }

  LspSignatureHelpTriggerKind._(super.value)
      : super(definitionName: 'SignatureHelpTriggerKind');
}

/// Validated LSP `SignatureInformation` value.
final class LspSignatureInformation extends LspSchemaValue {
  factory LspSignatureInformation.fromJson(JsonValue value) {
    return LspSignatureInformation._(
      LspModelRegistry.instance.validateNamed('SignatureInformation', value),
    );
  }

  LspSignatureInformation._(super.value)
      : super(definitionName: 'SignatureInformation');
}

/// Validated LSP `SnippetTextEdit` value.
final class LspSnippetTextEdit extends LspSchemaValue {
  factory LspSnippetTextEdit.fromJson(JsonValue value) {
    return LspSnippetTextEdit._(
      LspModelRegistry.instance.validateNamed('SnippetTextEdit', value),
    );
  }

  LspSnippetTextEdit._(super.value) : super(definitionName: 'SnippetTextEdit');
}

/// Validated LSP `StaleRequestSupportOptions` value.
final class LspStaleRequestSupportOptions extends LspSchemaValue {
  factory LspStaleRequestSupportOptions.fromJson(JsonValue value) {
    return LspStaleRequestSupportOptions._(
      LspModelRegistry.instance
          .validateNamed('StaleRequestSupportOptions', value),
    );
  }

  LspStaleRequestSupportOptions._(super.value)
      : super(definitionName: 'StaleRequestSupportOptions');
}

/// Validated LSP `StaticRegistrationOptions` value.
final class LspStaticRegistrationOptions extends LspSchemaValue {
  factory LspStaticRegistrationOptions.fromJson(JsonValue value) {
    return LspStaticRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('StaticRegistrationOptions', value),
    );
  }

  LspStaticRegistrationOptions._(super.value)
      : super(definitionName: 'StaticRegistrationOptions');
}

/// Validated LSP `StringValue` value.
final class LspStringValue extends LspSchemaValue {
  factory LspStringValue.fromJson(JsonValue value) {
    return LspStringValue._(
      LspModelRegistry.instance.validateNamed('StringValue', value),
    );
  }

  LspStringValue._(super.value) : super(definitionName: 'StringValue');
}

/// Validated LSP `SymbolInformation` value.
final class LspSymbolInformation extends LspSchemaValue {
  factory LspSymbolInformation.fromJson(JsonValue value) {
    return LspSymbolInformation._(
      LspModelRegistry.instance.validateNamed('SymbolInformation', value),
    );
  }

  LspSymbolInformation._(super.value)
      : super(definitionName: 'SymbolInformation');
}

/// Validated LSP `SymbolKind` value.
final class LspSymbolKind extends LspSchemaValue {
  factory LspSymbolKind.fromJson(JsonValue value) {
    return LspSymbolKind._(
      LspModelRegistry.instance.validateNamed('SymbolKind', value),
    );
  }

  LspSymbolKind._(super.value) : super(definitionName: 'SymbolKind');
}

/// Validated LSP `SymbolTag` value.
final class LspSymbolTag extends LspSchemaValue {
  factory LspSymbolTag.fromJson(JsonValue value) {
    return LspSymbolTag._(
      LspModelRegistry.instance.validateNamed('SymbolTag', value),
    );
  }

  LspSymbolTag._(super.value) : super(definitionName: 'SymbolTag');
}

/// Validated LSP `TextDocumentChangeRegistrationOptions` value.
final class LspTextDocumentChangeRegistrationOptions extends LspSchemaValue {
  factory LspTextDocumentChangeRegistrationOptions.fromJson(JsonValue value) {
    return LspTextDocumentChangeRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentChangeRegistrationOptions', value),
    );
  }

  LspTextDocumentChangeRegistrationOptions._(super.value)
      : super(definitionName: 'TextDocumentChangeRegistrationOptions');
}

/// Validated LSP `TextDocumentClientCapabilities` value.
final class LspTextDocumentClientCapabilities extends LspSchemaValue {
  factory LspTextDocumentClientCapabilities.fromJson(JsonValue value) {
    return LspTextDocumentClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentClientCapabilities', value),
    );
  }

  LspTextDocumentClientCapabilities._(super.value)
      : super(definitionName: 'TextDocumentClientCapabilities');
}

/// Validated LSP `TextDocumentContentChangeEvent` value.
final class LspTextDocumentContentChangeEvent extends LspSchemaValue {
  factory LspTextDocumentContentChangeEvent.fromJson(JsonValue value) {
    return LspTextDocumentContentChangeEvent._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentContentChangeEvent', value),
    );
  }

  LspTextDocumentContentChangeEvent._(super.value)
      : super(definitionName: 'TextDocumentContentChangeEvent');
}

/// Validated LSP `TextDocumentContentChangePartial` value.
final class LspTextDocumentContentChangePartial extends LspSchemaValue {
  factory LspTextDocumentContentChangePartial.fromJson(JsonValue value) {
    return LspTextDocumentContentChangePartial._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentContentChangePartial', value),
    );
  }

  LspTextDocumentContentChangePartial._(super.value)
      : super(definitionName: 'TextDocumentContentChangePartial');
}

/// Validated LSP `TextDocumentContentChangeWholeDocument` value.
final class LspTextDocumentContentChangeWholeDocument extends LspSchemaValue {
  factory LspTextDocumentContentChangeWholeDocument.fromJson(JsonValue value) {
    return LspTextDocumentContentChangeWholeDocument._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentContentChangeWholeDocument', value),
    );
  }

  LspTextDocumentContentChangeWholeDocument._(super.value)
      : super(definitionName: 'TextDocumentContentChangeWholeDocument');
}

/// Validated LSP `TextDocumentContentClientCapabilities` value.
final class LspTextDocumentContentClientCapabilities extends LspSchemaValue {
  factory LspTextDocumentContentClientCapabilities.fromJson(JsonValue value) {
    return LspTextDocumentContentClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentContentClientCapabilities', value),
    );
  }

  LspTextDocumentContentClientCapabilities._(super.value)
      : super(definitionName: 'TextDocumentContentClientCapabilities');
}

/// Validated LSP `TextDocumentContentOptions` value.
final class LspTextDocumentContentOptions extends LspSchemaValue {
  factory LspTextDocumentContentOptions.fromJson(JsonValue value) {
    return LspTextDocumentContentOptions._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentContentOptions', value),
    );
  }

  LspTextDocumentContentOptions._(super.value)
      : super(definitionName: 'TextDocumentContentOptions');
}

/// Validated LSP `TextDocumentContentParams` value.
final class LspTextDocumentContentParams extends LspSchemaValue {
  factory LspTextDocumentContentParams.fromJson(JsonValue value) {
    return LspTextDocumentContentParams._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentContentParams', value),
    );
  }

  LspTextDocumentContentParams._(super.value)
      : super(definitionName: 'TextDocumentContentParams');
}

/// Validated LSP `TextDocumentContentRefreshParams` value.
final class LspTextDocumentContentRefreshParams extends LspSchemaValue {
  factory LspTextDocumentContentRefreshParams.fromJson(JsonValue value) {
    return LspTextDocumentContentRefreshParams._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentContentRefreshParams', value),
    );
  }

  LspTextDocumentContentRefreshParams._(super.value)
      : super(definitionName: 'TextDocumentContentRefreshParams');
}

/// Validated LSP `TextDocumentContentRegistrationOptions` value.
final class LspTextDocumentContentRegistrationOptions extends LspSchemaValue {
  factory LspTextDocumentContentRegistrationOptions.fromJson(JsonValue value) {
    return LspTextDocumentContentRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentContentRegistrationOptions', value),
    );
  }

  LspTextDocumentContentRegistrationOptions._(super.value)
      : super(definitionName: 'TextDocumentContentRegistrationOptions');
}

/// Validated LSP `TextDocumentContentResult` value.
final class LspTextDocumentContentResult extends LspSchemaValue {
  factory LspTextDocumentContentResult.fromJson(JsonValue value) {
    return LspTextDocumentContentResult._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentContentResult', value),
    );
  }

  LspTextDocumentContentResult._(super.value)
      : super(definitionName: 'TextDocumentContentResult');
}

/// Validated LSP `TextDocumentEdit` value.
final class LspTextDocumentEdit extends LspSchemaValue {
  factory LspTextDocumentEdit.fromJson(JsonValue value) {
    return LspTextDocumentEdit._(
      LspModelRegistry.instance.validateNamed('TextDocumentEdit', value),
    );
  }

  LspTextDocumentEdit._(super.value)
      : super(definitionName: 'TextDocumentEdit');
}

/// Validated LSP `TextDocumentFilter` value.
final class LspTextDocumentFilter extends LspSchemaValue {
  factory LspTextDocumentFilter.fromJson(JsonValue value) {
    return LspTextDocumentFilter._(
      LspModelRegistry.instance.validateNamed('TextDocumentFilter', value),
    );
  }

  LspTextDocumentFilter._(super.value)
      : super(definitionName: 'TextDocumentFilter');
}

/// Validated LSP `TextDocumentFilterClientCapabilities` value.
final class LspTextDocumentFilterClientCapabilities extends LspSchemaValue {
  factory LspTextDocumentFilterClientCapabilities.fromJson(JsonValue value) {
    return LspTextDocumentFilterClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentFilterClientCapabilities', value),
    );
  }

  LspTextDocumentFilterClientCapabilities._(super.value)
      : super(definitionName: 'TextDocumentFilterClientCapabilities');
}

/// Validated LSP `TextDocumentFilterLanguage` value.
final class LspTextDocumentFilterLanguage extends LspSchemaValue {
  factory LspTextDocumentFilterLanguage.fromJson(JsonValue value) {
    return LspTextDocumentFilterLanguage._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentFilterLanguage', value),
    );
  }

  LspTextDocumentFilterLanguage._(super.value)
      : super(definitionName: 'TextDocumentFilterLanguage');
}

/// Validated LSP `TextDocumentFilterPattern` value.
final class LspTextDocumentFilterPattern extends LspSchemaValue {
  factory LspTextDocumentFilterPattern.fromJson(JsonValue value) {
    return LspTextDocumentFilterPattern._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentFilterPattern', value),
    );
  }

  LspTextDocumentFilterPattern._(super.value)
      : super(definitionName: 'TextDocumentFilterPattern');
}

/// Validated LSP `TextDocumentFilterScheme` value.
final class LspTextDocumentFilterScheme extends LspSchemaValue {
  factory LspTextDocumentFilterScheme.fromJson(JsonValue value) {
    return LspTextDocumentFilterScheme._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentFilterScheme', value),
    );
  }

  LspTextDocumentFilterScheme._(super.value)
      : super(definitionName: 'TextDocumentFilterScheme');
}

/// Validated LSP `TextDocumentIdentifier` value.
final class LspTextDocumentIdentifier extends LspSchemaValue {
  factory LspTextDocumentIdentifier.fromJson(JsonValue value) {
    return LspTextDocumentIdentifier._(
      LspModelRegistry.instance.validateNamed('TextDocumentIdentifier', value),
    );
  }

  LspTextDocumentIdentifier._(super.value)
      : super(definitionName: 'TextDocumentIdentifier');
}

/// Validated LSP `TextDocumentItem` value.
final class LspTextDocumentItem extends LspSchemaValue {
  factory LspTextDocumentItem.fromJson(JsonValue value) {
    return LspTextDocumentItem._(
      LspModelRegistry.instance.validateNamed('TextDocumentItem', value),
    );
  }

  LspTextDocumentItem._(super.value)
      : super(definitionName: 'TextDocumentItem');
}

/// Validated LSP `TextDocumentPositionParams` value.
final class LspTextDocumentPositionParams extends LspSchemaValue {
  factory LspTextDocumentPositionParams.fromJson(JsonValue value) {
    return LspTextDocumentPositionParams._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentPositionParams', value),
    );
  }

  LspTextDocumentPositionParams._(super.value)
      : super(definitionName: 'TextDocumentPositionParams');
}

/// Validated LSP `TextDocumentRegistrationOptions` value.
final class LspTextDocumentRegistrationOptions extends LspSchemaValue {
  factory LspTextDocumentRegistrationOptions.fromJson(JsonValue value) {
    return LspTextDocumentRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentRegistrationOptions', value),
    );
  }

  LspTextDocumentRegistrationOptions._(super.value)
      : super(definitionName: 'TextDocumentRegistrationOptions');
}

/// Validated LSP `TextDocumentSaveReason` value.
final class LspTextDocumentSaveReason extends LspSchemaValue {
  factory LspTextDocumentSaveReason.fromJson(JsonValue value) {
    return LspTextDocumentSaveReason._(
      LspModelRegistry.instance.validateNamed('TextDocumentSaveReason', value),
    );
  }

  LspTextDocumentSaveReason._(super.value)
      : super(definitionName: 'TextDocumentSaveReason');
}

/// Validated LSP `TextDocumentSaveRegistrationOptions` value.
final class LspTextDocumentSaveRegistrationOptions extends LspSchemaValue {
  factory LspTextDocumentSaveRegistrationOptions.fromJson(JsonValue value) {
    return LspTextDocumentSaveRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentSaveRegistrationOptions', value),
    );
  }

  LspTextDocumentSaveRegistrationOptions._(super.value)
      : super(definitionName: 'TextDocumentSaveRegistrationOptions');
}

/// Validated LSP `TextDocumentSyncClientCapabilities` value.
final class LspTextDocumentSyncClientCapabilities extends LspSchemaValue {
  factory LspTextDocumentSyncClientCapabilities.fromJson(JsonValue value) {
    return LspTextDocumentSyncClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('TextDocumentSyncClientCapabilities', value),
    );
  }

  LspTextDocumentSyncClientCapabilities._(super.value)
      : super(definitionName: 'TextDocumentSyncClientCapabilities');
}

/// Validated LSP `TextDocumentSyncKind` value.
final class LspTextDocumentSyncKind extends LspSchemaValue {
  factory LspTextDocumentSyncKind.fromJson(JsonValue value) {
    return LspTextDocumentSyncKind._(
      LspModelRegistry.instance.validateNamed('TextDocumentSyncKind', value),
    );
  }

  LspTextDocumentSyncKind._(super.value)
      : super(definitionName: 'TextDocumentSyncKind');
}

/// Validated LSP `TextDocumentSyncOptions` value.
final class LspTextDocumentSyncOptions extends LspSchemaValue {
  factory LspTextDocumentSyncOptions.fromJson(JsonValue value) {
    return LspTextDocumentSyncOptions._(
      LspModelRegistry.instance.validateNamed('TextDocumentSyncOptions', value),
    );
  }

  LspTextDocumentSyncOptions._(super.value)
      : super(definitionName: 'TextDocumentSyncOptions');
}

/// Validated LSP `TextEdit` value.
final class LspTextEdit extends LspSchemaValue {
  factory LspTextEdit.fromJson(JsonValue value) {
    return LspTextEdit._(
      LspModelRegistry.instance.validateNamed('TextEdit', value),
    );
  }

  LspTextEdit._(super.value) : super(definitionName: 'TextEdit');
}

/// Validated LSP `TokenFormat` value.
final class LspTokenFormat extends LspSchemaValue {
  factory LspTokenFormat.fromJson(JsonValue value) {
    return LspTokenFormat._(
      LspModelRegistry.instance.validateNamed('TokenFormat', value),
    );
  }

  LspTokenFormat._(super.value) : super(definitionName: 'TokenFormat');
}

/// Validated LSP `TraceValue` value.
final class LspTraceValue extends LspSchemaValue {
  factory LspTraceValue.fromJson(JsonValue value) {
    return LspTraceValue._(
      LspModelRegistry.instance.validateNamed('TraceValue', value),
    );
  }

  LspTraceValue._(super.value) : super(definitionName: 'TraceValue');
}

/// Validated LSP `TypeDefinitionClientCapabilities` value.
final class LspTypeDefinitionClientCapabilities extends LspSchemaValue {
  factory LspTypeDefinitionClientCapabilities.fromJson(JsonValue value) {
    return LspTypeDefinitionClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('TypeDefinitionClientCapabilities', value),
    );
  }

  LspTypeDefinitionClientCapabilities._(super.value)
      : super(definitionName: 'TypeDefinitionClientCapabilities');
}

/// Validated LSP `TypeDefinitionOptions` value.
final class LspTypeDefinitionOptions extends LspSchemaValue {
  factory LspTypeDefinitionOptions.fromJson(JsonValue value) {
    return LspTypeDefinitionOptions._(
      LspModelRegistry.instance.validateNamed('TypeDefinitionOptions', value),
    );
  }

  LspTypeDefinitionOptions._(super.value)
      : super(definitionName: 'TypeDefinitionOptions');
}

/// Validated LSP `TypeDefinitionParams` value.
final class LspTypeDefinitionParams extends LspSchemaValue {
  factory LspTypeDefinitionParams.fromJson(JsonValue value) {
    return LspTypeDefinitionParams._(
      LspModelRegistry.instance.validateNamed('TypeDefinitionParams', value),
    );
  }

  LspTypeDefinitionParams._(super.value)
      : super(definitionName: 'TypeDefinitionParams');
}

/// Validated LSP `TypeDefinitionRegistrationOptions` value.
final class LspTypeDefinitionRegistrationOptions extends LspSchemaValue {
  factory LspTypeDefinitionRegistrationOptions.fromJson(JsonValue value) {
    return LspTypeDefinitionRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('TypeDefinitionRegistrationOptions', value),
    );
  }

  LspTypeDefinitionRegistrationOptions._(super.value)
      : super(definitionName: 'TypeDefinitionRegistrationOptions');
}

/// Validated LSP `TypeHierarchyClientCapabilities` value.
final class LspTypeHierarchyClientCapabilities extends LspSchemaValue {
  factory LspTypeHierarchyClientCapabilities.fromJson(JsonValue value) {
    return LspTypeHierarchyClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('TypeHierarchyClientCapabilities', value),
    );
  }

  LspTypeHierarchyClientCapabilities._(super.value)
      : super(definitionName: 'TypeHierarchyClientCapabilities');
}

/// Validated LSP `TypeHierarchyItem` value.
final class LspTypeHierarchyItem extends LspSchemaValue {
  factory LspTypeHierarchyItem.fromJson(JsonValue value) {
    return LspTypeHierarchyItem._(
      LspModelRegistry.instance.validateNamed('TypeHierarchyItem', value),
    );
  }

  LspTypeHierarchyItem._(super.value)
      : super(definitionName: 'TypeHierarchyItem');
}

/// Validated LSP `TypeHierarchyOptions` value.
final class LspTypeHierarchyOptions extends LspSchemaValue {
  factory LspTypeHierarchyOptions.fromJson(JsonValue value) {
    return LspTypeHierarchyOptions._(
      LspModelRegistry.instance.validateNamed('TypeHierarchyOptions', value),
    );
  }

  LspTypeHierarchyOptions._(super.value)
      : super(definitionName: 'TypeHierarchyOptions');
}

/// Validated LSP `TypeHierarchyPrepareParams` value.
final class LspTypeHierarchyPrepareParams extends LspSchemaValue {
  factory LspTypeHierarchyPrepareParams.fromJson(JsonValue value) {
    return LspTypeHierarchyPrepareParams._(
      LspModelRegistry.instance
          .validateNamed('TypeHierarchyPrepareParams', value),
    );
  }

  LspTypeHierarchyPrepareParams._(super.value)
      : super(definitionName: 'TypeHierarchyPrepareParams');
}

/// Validated LSP `TypeHierarchyRegistrationOptions` value.
final class LspTypeHierarchyRegistrationOptions extends LspSchemaValue {
  factory LspTypeHierarchyRegistrationOptions.fromJson(JsonValue value) {
    return LspTypeHierarchyRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('TypeHierarchyRegistrationOptions', value),
    );
  }

  LspTypeHierarchyRegistrationOptions._(super.value)
      : super(definitionName: 'TypeHierarchyRegistrationOptions');
}

/// Validated LSP `TypeHierarchySubtypesParams` value.
final class LspTypeHierarchySubtypesParams extends LspSchemaValue {
  factory LspTypeHierarchySubtypesParams.fromJson(JsonValue value) {
    return LspTypeHierarchySubtypesParams._(
      LspModelRegistry.instance
          .validateNamed('TypeHierarchySubtypesParams', value),
    );
  }

  LspTypeHierarchySubtypesParams._(super.value)
      : super(definitionName: 'TypeHierarchySubtypesParams');
}

/// Validated LSP `TypeHierarchySupertypesParams` value.
final class LspTypeHierarchySupertypesParams extends LspSchemaValue {
  factory LspTypeHierarchySupertypesParams.fromJson(JsonValue value) {
    return LspTypeHierarchySupertypesParams._(
      LspModelRegistry.instance
          .validateNamed('TypeHierarchySupertypesParams', value),
    );
  }

  LspTypeHierarchySupertypesParams._(super.value)
      : super(definitionName: 'TypeHierarchySupertypesParams');
}

/// Validated LSP `UnchangedDocumentDiagnosticReport` value.
final class LspUnchangedDocumentDiagnosticReport extends LspSchemaValue {
  factory LspUnchangedDocumentDiagnosticReport.fromJson(JsonValue value) {
    return LspUnchangedDocumentDiagnosticReport._(
      LspModelRegistry.instance
          .validateNamed('UnchangedDocumentDiagnosticReport', value),
    );
  }

  LspUnchangedDocumentDiagnosticReport._(super.value)
      : super(definitionName: 'UnchangedDocumentDiagnosticReport');
}

/// Validated LSP `UniquenessLevel` value.
final class LspUniquenessLevel extends LspSchemaValue {
  factory LspUniquenessLevel.fromJson(JsonValue value) {
    return LspUniquenessLevel._(
      LspModelRegistry.instance.validateNamed('UniquenessLevel', value),
    );
  }

  LspUniquenessLevel._(super.value) : super(definitionName: 'UniquenessLevel');
}

/// Validated LSP `Unregistration` value.
final class LspUnregistration extends LspSchemaValue {
  factory LspUnregistration.fromJson(JsonValue value) {
    return LspUnregistration._(
      LspModelRegistry.instance.validateNamed('Unregistration', value),
    );
  }

  LspUnregistration._(super.value) : super(definitionName: 'Unregistration');
}

/// Validated LSP `UnregistrationParams` value.
final class LspUnregistrationParams extends LspSchemaValue {
  factory LspUnregistrationParams.fromJson(JsonValue value) {
    return LspUnregistrationParams._(
      LspModelRegistry.instance.validateNamed('UnregistrationParams', value),
    );
  }

  LspUnregistrationParams._(super.value)
      : super(definitionName: 'UnregistrationParams');
}

/// Validated LSP `VersionedNotebookDocumentIdentifier` value.
final class LspVersionedNotebookDocumentIdentifier extends LspSchemaValue {
  factory LspVersionedNotebookDocumentIdentifier.fromJson(JsonValue value) {
    return LspVersionedNotebookDocumentIdentifier._(
      LspModelRegistry.instance
          .validateNamed('VersionedNotebookDocumentIdentifier', value),
    );
  }

  LspVersionedNotebookDocumentIdentifier._(super.value)
      : super(definitionName: 'VersionedNotebookDocumentIdentifier');
}

/// Validated LSP `VersionedTextDocumentIdentifier` value.
final class LspVersionedTextDocumentIdentifier extends LspSchemaValue {
  factory LspVersionedTextDocumentIdentifier.fromJson(JsonValue value) {
    return LspVersionedTextDocumentIdentifier._(
      LspModelRegistry.instance
          .validateNamed('VersionedTextDocumentIdentifier', value),
    );
  }

  LspVersionedTextDocumentIdentifier._(super.value)
      : super(definitionName: 'VersionedTextDocumentIdentifier');
}

/// Validated LSP `WatchKind` value.
final class LspWatchKind extends LspSchemaValue {
  factory LspWatchKind.fromJson(JsonValue value) {
    return LspWatchKind._(
      LspModelRegistry.instance.validateNamed('WatchKind', value),
    );
  }

  LspWatchKind._(super.value) : super(definitionName: 'WatchKind');
}

/// Validated LSP `WillSaveTextDocumentParams` value.
final class LspWillSaveTextDocumentParams extends LspSchemaValue {
  factory LspWillSaveTextDocumentParams.fromJson(JsonValue value) {
    return LspWillSaveTextDocumentParams._(
      LspModelRegistry.instance
          .validateNamed('WillSaveTextDocumentParams', value),
    );
  }

  LspWillSaveTextDocumentParams._(super.value)
      : super(definitionName: 'WillSaveTextDocumentParams');
}

/// Validated LSP `WindowClientCapabilities` value.
final class LspWindowClientCapabilities extends LspSchemaValue {
  factory LspWindowClientCapabilities.fromJson(JsonValue value) {
    return LspWindowClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('WindowClientCapabilities', value),
    );
  }

  LspWindowClientCapabilities._(super.value)
      : super(definitionName: 'WindowClientCapabilities');
}

/// Validated LSP `WorkDoneProgressBegin` value.
final class LspWorkDoneProgressBegin extends LspSchemaValue {
  factory LspWorkDoneProgressBegin.fromJson(JsonValue value) {
    return LspWorkDoneProgressBegin._(
      LspModelRegistry.instance.validateNamed('WorkDoneProgressBegin', value),
    );
  }

  LspWorkDoneProgressBegin._(super.value)
      : super(definitionName: 'WorkDoneProgressBegin');
}

/// Validated LSP `WorkDoneProgressCancelParams` value.
final class LspWorkDoneProgressCancelParams extends LspSchemaValue {
  factory LspWorkDoneProgressCancelParams.fromJson(JsonValue value) {
    return LspWorkDoneProgressCancelParams._(
      LspModelRegistry.instance
          .validateNamed('WorkDoneProgressCancelParams', value),
    );
  }

  LspWorkDoneProgressCancelParams._(super.value)
      : super(definitionName: 'WorkDoneProgressCancelParams');
}

/// Validated LSP `WorkDoneProgressCreateParams` value.
final class LspWorkDoneProgressCreateParams extends LspSchemaValue {
  factory LspWorkDoneProgressCreateParams.fromJson(JsonValue value) {
    return LspWorkDoneProgressCreateParams._(
      LspModelRegistry.instance
          .validateNamed('WorkDoneProgressCreateParams', value),
    );
  }

  LspWorkDoneProgressCreateParams._(super.value)
      : super(definitionName: 'WorkDoneProgressCreateParams');
}

/// Validated LSP `WorkDoneProgressEnd` value.
final class LspWorkDoneProgressEnd extends LspSchemaValue {
  factory LspWorkDoneProgressEnd.fromJson(JsonValue value) {
    return LspWorkDoneProgressEnd._(
      LspModelRegistry.instance.validateNamed('WorkDoneProgressEnd', value),
    );
  }

  LspWorkDoneProgressEnd._(super.value)
      : super(definitionName: 'WorkDoneProgressEnd');
}

/// Validated LSP `WorkDoneProgressOptions` value.
final class LspWorkDoneProgressOptions extends LspSchemaValue {
  factory LspWorkDoneProgressOptions.fromJson(JsonValue value) {
    return LspWorkDoneProgressOptions._(
      LspModelRegistry.instance.validateNamed('WorkDoneProgressOptions', value),
    );
  }

  LspWorkDoneProgressOptions._(super.value)
      : super(definitionName: 'WorkDoneProgressOptions');
}

/// Validated LSP `WorkDoneProgressParams` value.
final class LspWorkDoneProgressParams extends LspSchemaValue {
  factory LspWorkDoneProgressParams.fromJson(JsonValue value) {
    return LspWorkDoneProgressParams._(
      LspModelRegistry.instance.validateNamed('WorkDoneProgressParams', value),
    );
  }

  LspWorkDoneProgressParams._(super.value)
      : super(definitionName: 'WorkDoneProgressParams');
}

/// Validated LSP `WorkDoneProgressReport` value.
final class LspWorkDoneProgressReport extends LspSchemaValue {
  factory LspWorkDoneProgressReport.fromJson(JsonValue value) {
    return LspWorkDoneProgressReport._(
      LspModelRegistry.instance.validateNamed('WorkDoneProgressReport', value),
    );
  }

  LspWorkDoneProgressReport._(super.value)
      : super(definitionName: 'WorkDoneProgressReport');
}

/// Validated LSP `WorkspaceClientCapabilities` value.
final class LspWorkspaceClientCapabilities extends LspSchemaValue {
  factory LspWorkspaceClientCapabilities.fromJson(JsonValue value) {
    return LspWorkspaceClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceClientCapabilities', value),
    );
  }

  LspWorkspaceClientCapabilities._(super.value)
      : super(definitionName: 'WorkspaceClientCapabilities');
}

/// Validated LSP `WorkspaceDiagnosticParams` value.
final class LspWorkspaceDiagnosticParams extends LspSchemaValue {
  factory LspWorkspaceDiagnosticParams.fromJson(JsonValue value) {
    return LspWorkspaceDiagnosticParams._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceDiagnosticParams', value),
    );
  }

  LspWorkspaceDiagnosticParams._(super.value)
      : super(definitionName: 'WorkspaceDiagnosticParams');
}

/// Validated LSP `WorkspaceDiagnosticReport` value.
final class LspWorkspaceDiagnosticReport extends LspSchemaValue {
  factory LspWorkspaceDiagnosticReport.fromJson(JsonValue value) {
    return LspWorkspaceDiagnosticReport._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceDiagnosticReport', value),
    );
  }

  LspWorkspaceDiagnosticReport._(super.value)
      : super(definitionName: 'WorkspaceDiagnosticReport');
}

/// Validated LSP `WorkspaceDiagnosticReportPartialResult` value.
final class LspWorkspaceDiagnosticReportPartialResult extends LspSchemaValue {
  factory LspWorkspaceDiagnosticReportPartialResult.fromJson(JsonValue value) {
    return LspWorkspaceDiagnosticReportPartialResult._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceDiagnosticReportPartialResult', value),
    );
  }

  LspWorkspaceDiagnosticReportPartialResult._(super.value)
      : super(definitionName: 'WorkspaceDiagnosticReportPartialResult');
}

/// Validated LSP `WorkspaceDocumentDiagnosticReport` value.
final class LspWorkspaceDocumentDiagnosticReport extends LspSchemaValue {
  factory LspWorkspaceDocumentDiagnosticReport.fromJson(JsonValue value) {
    return LspWorkspaceDocumentDiagnosticReport._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceDocumentDiagnosticReport', value),
    );
  }

  LspWorkspaceDocumentDiagnosticReport._(super.value)
      : super(definitionName: 'WorkspaceDocumentDiagnosticReport');
}

/// Validated LSP `WorkspaceEdit` value.
final class LspWorkspaceEdit extends LspSchemaValue {
  factory LspWorkspaceEdit.fromJson(JsonValue value) {
    return LspWorkspaceEdit._(
      LspModelRegistry.instance.validateNamed('WorkspaceEdit', value),
    );
  }

  LspWorkspaceEdit._(super.value) : super(definitionName: 'WorkspaceEdit');
}

/// Validated LSP `WorkspaceEditClientCapabilities` value.
final class LspWorkspaceEditClientCapabilities extends LspSchemaValue {
  factory LspWorkspaceEditClientCapabilities.fromJson(JsonValue value) {
    return LspWorkspaceEditClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceEditClientCapabilities', value),
    );
  }

  LspWorkspaceEditClientCapabilities._(super.value)
      : super(definitionName: 'WorkspaceEditClientCapabilities');
}

/// Validated LSP `WorkspaceEditMetadata` value.
final class LspWorkspaceEditMetadata extends LspSchemaValue {
  factory LspWorkspaceEditMetadata.fromJson(JsonValue value) {
    return LspWorkspaceEditMetadata._(
      LspModelRegistry.instance.validateNamed('WorkspaceEditMetadata', value),
    );
  }

  LspWorkspaceEditMetadata._(super.value)
      : super(definitionName: 'WorkspaceEditMetadata');
}

/// Validated LSP `WorkspaceFolder` value.
final class LspWorkspaceFolder extends LspSchemaValue {
  factory LspWorkspaceFolder.fromJson(JsonValue value) {
    return LspWorkspaceFolder._(
      LspModelRegistry.instance.validateNamed('WorkspaceFolder', value),
    );
  }

  LspWorkspaceFolder._(super.value) : super(definitionName: 'WorkspaceFolder');
}

/// Validated LSP `WorkspaceFoldersChangeEvent` value.
final class LspWorkspaceFoldersChangeEvent extends LspSchemaValue {
  factory LspWorkspaceFoldersChangeEvent.fromJson(JsonValue value) {
    return LspWorkspaceFoldersChangeEvent._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceFoldersChangeEvent', value),
    );
  }

  LspWorkspaceFoldersChangeEvent._(super.value)
      : super(definitionName: 'WorkspaceFoldersChangeEvent');
}

/// Validated LSP `WorkspaceFoldersInitializeParams` value.
final class LspWorkspaceFoldersInitializeParams extends LspSchemaValue {
  factory LspWorkspaceFoldersInitializeParams.fromJson(JsonValue value) {
    return LspWorkspaceFoldersInitializeParams._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceFoldersInitializeParams', value),
    );
  }

  LspWorkspaceFoldersInitializeParams._(super.value)
      : super(definitionName: 'WorkspaceFoldersInitializeParams');
}

/// Validated LSP `WorkspaceFoldersServerCapabilities` value.
final class LspWorkspaceFoldersServerCapabilities extends LspSchemaValue {
  factory LspWorkspaceFoldersServerCapabilities.fromJson(JsonValue value) {
    return LspWorkspaceFoldersServerCapabilities._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceFoldersServerCapabilities', value),
    );
  }

  LspWorkspaceFoldersServerCapabilities._(super.value)
      : super(definitionName: 'WorkspaceFoldersServerCapabilities');
}

/// Validated LSP `WorkspaceFullDocumentDiagnosticReport` value.
final class LspWorkspaceFullDocumentDiagnosticReport extends LspSchemaValue {
  factory LspWorkspaceFullDocumentDiagnosticReport.fromJson(JsonValue value) {
    return LspWorkspaceFullDocumentDiagnosticReport._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceFullDocumentDiagnosticReport', value),
    );
  }

  LspWorkspaceFullDocumentDiagnosticReport._(super.value)
      : super(definitionName: 'WorkspaceFullDocumentDiagnosticReport');
}

/// Validated LSP `WorkspaceOptions` value.
final class LspWorkspaceOptions extends LspSchemaValue {
  factory LspWorkspaceOptions.fromJson(JsonValue value) {
    return LspWorkspaceOptions._(
      LspModelRegistry.instance.validateNamed('WorkspaceOptions', value),
    );
  }

  LspWorkspaceOptions._(super.value)
      : super(definitionName: 'WorkspaceOptions');
}

/// Validated LSP `WorkspaceSymbol` value.
final class LspWorkspaceSymbol extends LspSchemaValue {
  factory LspWorkspaceSymbol.fromJson(JsonValue value) {
    return LspWorkspaceSymbol._(
      LspModelRegistry.instance.validateNamed('WorkspaceSymbol', value),
    );
  }

  LspWorkspaceSymbol._(super.value) : super(definitionName: 'WorkspaceSymbol');
}

/// Validated LSP `WorkspaceSymbolClientCapabilities` value.
final class LspWorkspaceSymbolClientCapabilities extends LspSchemaValue {
  factory LspWorkspaceSymbolClientCapabilities.fromJson(JsonValue value) {
    return LspWorkspaceSymbolClientCapabilities._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceSymbolClientCapabilities', value),
    );
  }

  LspWorkspaceSymbolClientCapabilities._(super.value)
      : super(definitionName: 'WorkspaceSymbolClientCapabilities');
}

/// Validated LSP `WorkspaceSymbolOptions` value.
final class LspWorkspaceSymbolOptions extends LspSchemaValue {
  factory LspWorkspaceSymbolOptions.fromJson(JsonValue value) {
    return LspWorkspaceSymbolOptions._(
      LspModelRegistry.instance.validateNamed('WorkspaceSymbolOptions', value),
    );
  }

  LspWorkspaceSymbolOptions._(super.value)
      : super(definitionName: 'WorkspaceSymbolOptions');
}

/// Validated LSP `WorkspaceSymbolParams` value.
final class LspWorkspaceSymbolParams extends LspSchemaValue {
  factory LspWorkspaceSymbolParams.fromJson(JsonValue value) {
    return LspWorkspaceSymbolParams._(
      LspModelRegistry.instance.validateNamed('WorkspaceSymbolParams', value),
    );
  }

  LspWorkspaceSymbolParams._(super.value)
      : super(definitionName: 'WorkspaceSymbolParams');
}

/// Validated LSP `WorkspaceSymbolRegistrationOptions` value.
final class LspWorkspaceSymbolRegistrationOptions extends LspSchemaValue {
  factory LspWorkspaceSymbolRegistrationOptions.fromJson(JsonValue value) {
    return LspWorkspaceSymbolRegistrationOptions._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceSymbolRegistrationOptions', value),
    );
  }

  LspWorkspaceSymbolRegistrationOptions._(super.value)
      : super(definitionName: 'WorkspaceSymbolRegistrationOptions');
}

/// Validated LSP `WorkspaceUnchangedDocumentDiagnosticReport` value.
final class LspWorkspaceUnchangedDocumentDiagnosticReport
    extends LspSchemaValue {
  factory LspWorkspaceUnchangedDocumentDiagnosticReport.fromJson(
      JsonValue value) {
    return LspWorkspaceUnchangedDocumentDiagnosticReport._(
      LspModelRegistry.instance
          .validateNamed('WorkspaceUnchangedDocumentDiagnosticReport', value),
    );
  }

  LspWorkspaceUnchangedDocumentDiagnosticReport._(super.value)
      : super(definitionName: 'WorkspaceUnchangedDocumentDiagnosticReport');
}

/// Validated LSP `_InitializeParams` value.
final class Lsp_InitializeParams extends LspSchemaValue {
  factory Lsp_InitializeParams.fromJson(JsonValue value) {
    return Lsp_InitializeParams._(
      LspModelRegistry.instance.validateNamed('_InitializeParams', value),
    );
  }

  Lsp_InitializeParams._(super.value)
      : super(definitionName: '_InitializeParams');
}
