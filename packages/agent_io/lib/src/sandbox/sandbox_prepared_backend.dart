import '../exec/process_cleanup_ledger.dart';
import 'sandbox_backend.dart';
import 'sandbox_policy.dart';

typedef PersistProcessGroup = Future<ProcessCleanupRecord> Function(
  int processGroupId,
);

abstract interface class PreparedSandboxBackend implements SandboxBackend {
  Future<SandboxedProcess> startPrepared(
    SandboxPolicy policy,
    HostCommand command, {
    required PersistProcessGroup persistProcessGroup,
  });

  Future<HostCommand> prepareForPty(
    SandboxPolicy policy,
    HostCommand command,
  );
}
