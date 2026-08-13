import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

void main() {
  test('missing sandbox fails closed with sandboxUnavailable', () {
    final report = SandboxCapabilityReport.untrusted(
      platform: SandboxPlatform.macosArm64,
      backend: 'seatbelt',
      available: false,
      minimumSatisfied: false,
      sandboxExecPresent: false,
    );

    expect(
      report.requireProductionReady,
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.code,
          'code',
          HostCapabilityError.sandboxUnavailable,
        ),
      ),
    );
  });

  test('start never executes when sandbox-exec probe is unavailable', () async {
    final backend = SeatbeltSandboxBackend(
      capabilityProbe: SandboxCapabilityProbe(
        platform: SandboxPlatform.macosArm64,
        sandboxExecExists: () => false,
      ),
    );

    await expectLater(
      backend.start(
        SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: '/tmp',
              access: SandboxPathAccess.readOnly,
            ),
          ],
        ),
        HostCommand(executable: '/usr/bin/false'),
      ),
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.code,
          'code',
          HostCapabilityError.sandboxUnavailable,
        ),
      ),
    );
  });

  test('low capability fails closed with capabilityBelowMinimum', () {
    final report = SandboxCapabilityReport.untrusted(
      platform: SandboxPlatform.linuxX64,
      backend: 'landlock-seccomp',
      available: false,
      minimumSatisfied: false,
      landlockAbi: 3,
      seccompSupported: true,
    );

    expect(
      report.requireProductionReady,
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.code,
          'code',
          HostCapabilityError.capabilityBelowMinimum,
        ),
      ),
    );
  });

  test('start never executes when Landlock ABI is below minimum', () async {
    final backend = SeatbeltSandboxBackend(
      capabilityProbe: SandboxCapabilityProbe(
        platform: SandboxPlatform.linuxX64,
        landlockAbi: () => 3,
        seccompSupported: () => true,
      ),
    );

    await expectLater(
      backend.start(
        SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: '/tmp',
              access: SandboxPathAccess.readOnly,
            ),
          ],
        ),
        HostCommand(executable: '/usr/bin/false'),
      ),
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.code,
          'code',
          HostCapabilityError.capabilityBelowMinimum,
        ),
      ),
    );
  });

  test('unsafe backend is explicit and always marked unsafe/dev-only', () {
    final backend = UnsafeDevSandboxBackend();

    expect(backend.probe().labels, contains('unsafe/dev-only'));
    expect(backend.probe().productionReady, isFalse);
  });
}
