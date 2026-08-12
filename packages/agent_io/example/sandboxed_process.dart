import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('pigcode-sandbox-example-');
  final dataRoot = Directory.systemTemp.createTempSync('pigcode-sandbox-data-');
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
    sessionIdentity: 'sandbox-example',
  );
  SandboxedProcess? child;
  try {
    child = await launcher.launch(
      SandboxPolicy(
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
      HostCommand(
        executable: Platform.resolvedExecutable,
        arguments: const <String>['--version'],
        workingDirectory: root.path,
      ),
    );
    final code = await child.exitCode.timeout(const Duration(seconds: 10));
    final report = await launcher.cleanup(child).timeout(
          const Duration(seconds: 10),
        );
    if (code != 0 || !report.confirmed) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'sandbox-example-cleanup-unconfirmed',
      );
    }
    print('sandbox=${child.capability.backend} cleanup=confirmed');
  } finally {
    if (child != null) {
      await launcher.cleanup(child).timeout(const Duration(seconds: 10));
    }
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (dataRoot.existsSync()) dataRoot.deleteSync(recursive: true);
  }
}
