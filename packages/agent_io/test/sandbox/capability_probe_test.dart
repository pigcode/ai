import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

void main() {
  test('macOS probe reports a missing sandbox-exec exactly', () {
    final report = SandboxCapabilityProbe(
      platform: SandboxPlatform.macosArm64,
      sandboxExecExists: () => false,
    ).probe();

    expect(report.available, isFalse);
    expect(report.sandboxExecPresent, isFalse);
    expect(report.backend, 'seatbelt');
  });

  for (final abi in const <int?>[null, 1, 2, 3]) {
    test('Linux Landlock ABI $abi is below the production minimum', () {
      final report = SandboxCapabilityProbe(
        platform: SandboxPlatform.linuxX64,
        landlockAbi: () => abi,
        seccompSupported: () => true,
      ).probe();

      expect(report.available, isFalse);
      expect(report.minimumSatisfied, isFalse);
    });
  }

  test('Linux probe fails closed when seccomp is unavailable', () {
    final report = SandboxCapabilityProbe(
      platform: SandboxPlatform.linuxX64,
      landlockAbi: () => 4,
      seccompSupported: () => false,
    ).probe();

    expect(report.available, isFalse);
    expect(report.seccompSupported, isFalse);
  });
}
