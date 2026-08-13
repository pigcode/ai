import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';

import 'dap_debug_capability.dart';
import 'lsp_edit_capability.dart';

final class DartToolingWorkspace {
  const DartToolingWorkspace({
    required this.launcher,
    required this.policy,
  });

  final SandboxedProcessLauncher launcher;
  final SandboxPolicy policy;

  Future<SandboxedProcess> launch(HostCommand command) =>
      launcher.launch(policy, command);
}

final class DartDevelopmentCapabilities {
  const DartDevelopmentCapabilities({
    required this.workspace,
    required this.dap,
    required this.lsp,
  });

  final DartToolingWorkspace workspace;
  final DapDebugCapability dap;
  final LspEditCapability lsp;
}
