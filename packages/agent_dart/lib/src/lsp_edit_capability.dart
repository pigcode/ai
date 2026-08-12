import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';

import 'dap_debug_capability.dart';

final class LspEditCapability {
  DartHostProposal proposeApplyEdit(Map<String, Object?> params) {
    final proposal = LspApplyEditProposal.fromParams(params);
    return DartHostProposal(
      identity: 'lsp.workspace.applyEdit',
      effectControl: DartHostEffectControl.interceptable,
      payload: proposal,
    );
  }
}
