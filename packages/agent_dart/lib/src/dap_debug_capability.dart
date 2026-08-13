import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';

enum DartHostEffectControl { interceptable }

final class DartHostProposal {
  DartHostProposal({
    required this.identity,
    required this.effectControl,
    required this.payload,
  });

  final String identity;
  final DartHostEffectControl effectControl;
  final Object payload;
  bool executed = false;

  void markExecutedAfterApproval({required bool approved}) {
    if (!approved) throw StateError('Host proposal was not approved.');
    executed = true;
  }
}

final class DapDebugCapability {
  DartHostProposal proposeRunInTerminal(Map<String, Object?> arguments) {
    final proposal = DapRunInTerminalProposal.fromArguments(arguments);
    return DartHostProposal(
      identity: 'dap.runInTerminal',
      effectControl: DartHostEffectControl.interceptable,
      payload: proposal,
    );
  }
}
