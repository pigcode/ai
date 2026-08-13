import 'dart:io';

import '../exec/process_cleanup_ledger.dart';
import 'sandbox_backend.dart';
import 'sandbox_policy.dart';

typedef PersistProcessGroup = Future<ProcessCleanupRecord> Function(
  int processGroupId,
);

/// Non-secret host variables that sandboxed launches may keep. Everything
/// else (API keys, tokens, cloud credentials) must never cross the boundary.
const List<String> sandboxLaunchEnvironmentBaseline = <String>[
  'LANG',
  'LC_ALL',
  'PATH',
  'TERM',
  'TMPDIR',
  'TZ',
];

/// Builds the explicit environment for a sandboxed launch: the non-secret
/// baseline plus the caller-provided variables. Callers must combine this
/// with `includeParentEnvironment: false` so the host environment (and any
/// credentials it carries) never reaches sandboxed processes.
Map<String, String> sandboxLaunchEnvironment(Map<String, String>? explicit) =>
    Map<String, String>.unmodifiable(<String, String>{
      for (final key in sandboxLaunchEnvironmentBaseline)
        if (Platform.environment[key] != null) key: Platform.environment[key]!,
      ...?explicit,
    });

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
