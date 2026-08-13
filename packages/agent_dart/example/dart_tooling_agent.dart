import 'dart:io';

import 'package:pigcode_ai_agent_dart/pigcode_ai_agent_dart.dart';
import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('pigcode-dart-tooling-');
  final dataRoot =
      Directory.systemTemp.createTempSync('pigcode-dart-tooling-data-');
  final backend = switch (SandboxPlatform.current) {
    SandboxPlatform.macosArm64 => SeatbeltSandboxBackend(),
    SandboxPlatform.linuxX64 ||
    SandboxPlatform.linuxArm64 =>
      LandlockSeccompSandboxBackend(),
    SandboxPlatform.unsupported => throw const HostCapabilityException(
        HostCapabilityError.unsupportedPlatform,
        'native-containment-platform-unsupported',
      ),
  };
  backend.probe().requireProductionReady();
  final launcher = SandboxedProcessLauncher(
    backend,
    hostDataDirectory: dataRoot.path,
    sessionIdentity: 'dart-tooling-example',
  );
  SandboxedProcess? process;
  try {
    final workspace = DartToolingWorkspace(
      launcher: launcher,
      policy: SandboxPolicy(
        roots: <SandboxPathRule>[
          SandboxPathRule(
            path: root.path,
            access: SandboxPathAccess.readWrite,
          ),
          SandboxPathRule(
            path: File(Platform.resolvedExecutable).parent.parent.path,
            access: SandboxPathAccess.readOnly,
          ),
        ],
      ),
    );
    process = await workspace.launch(
      HostCommand(
        executable: Platform.resolvedExecutable,
        arguments: const <String>['--version'],
        workingDirectory: root.path,
      ),
    );
    final code = await process.exitCode.timeout(const Duration(seconds: 10));
    final cleanup = await launcher.cleanup(process).timeout(
          const Duration(seconds: 10),
        );
    if (code != 0 || !cleanup.confirmed) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'tooling-example-cleanup-unconfirmed',
      );
    }
    print('sandbox=${process.capability.backend} cleanup=confirmed');
  } finally {
    if (process != null) {
      await launcher.cleanup(process).timeout(const Duration(seconds: 10));
    }
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (dataRoot.existsSync()) dataRoot.deleteSync(recursive: true);
  }
}
