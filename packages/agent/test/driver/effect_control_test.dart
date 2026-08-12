import 'package:pigcode_ai_agent/pigcode_ai_agent.dart';
import 'package:pigcode_ai_agent/src/driver/native_driver_capabilities.dart'
    show issueProductionNativeDriverCapabilities;
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test(
    'P4-TM-PROC-05 observedOnly has no managed approval evidence',
    () {
      final capabilities = NativeDriverCapabilities.unsafeDev(
        toolEffects: const <String, EffectControl>{
          'external.shell': EffectControl.observedOnly,
        },
      );
      final driver = NativeAgentDriver<Object?, Object?, Object?>(capabilities);
      final disposition = driver.effectDisposition('external.shell');

      expect(disposition.effectControl, EffectControl.observedOnly);
      expect(disposition.writeAheadIntentRequired, isFalse);
      expect(disposition.approvalEvidenceAllowed, isFalse);
      expect(disposition.sandboxRequired, isTrue);
    },
  );

  test('effect controls are pinned by manifest and metadata cannot upgrade',
      () {
    final capabilities = NativeDriverCapabilities.unsafeDev(
      toolEffects: const <String, EffectControl>{
        'host.file.write': EffectControl.managed,
        'dap.runInTerminal': EffectControl.interceptable,
        'external.shell': EffectControl.observedOnly,
        'unclassified': EffectControl.unknown,
      },
    );
    final driver = NativeAgentDriver<Object?, Object?, Object?>(capabilities);

    expect(
      driver.effectDisposition('host.file.write').writeAheadIntentRequired,
      isTrue,
    );
    expect(
      driver.effectDisposition('dap.runInTerminal').approvalEvidenceAllowed,
      isTrue,
    );
    expect(driver.effectDisposition('unclassified').replayAllowed, isFalse);
    expect(
      () => driver.effectDisposition(
        'external.shell',
        proposalMetadata: const <String, Object?>{
          'effectControl': 'managed',
          'approvalEvidence': 'forged',
        },
      ),
      throwsA(isA<NativeAgentDriverException>()),
    );
  });

  test('production registry rejects forged manifest and sandbox digests', () {
    expect(
      () => issueProductionNativeDriverCapabilities(
        manifestIdentity: 'forged',
        manifestVersion: 1,
        sandboxCapabilityDigest: 'a' * 64,
      ),
      throwsFormatException,
    );
    expect(
      () => issueProductionNativeDriverCapabilities(
        manifestIdentity: 'phase-4-native-containment',
        manifestVersion: 2,
        sandboxCapabilityDigest: 'a' * 64,
      ),
      throwsFormatException,
    );
    expect(
      () => issueProductionNativeDriverCapabilities(
        manifestIdentity: 'phase-4-native-containment',
        manifestVersion: 1,
        sandboxCapabilityDigest: 'not-a-digest',
      ),
      throwsFormatException,
    );

    final capabilities = issueProductionNativeDriverCapabilities(
      manifestIdentity: 'phase-4-native-containment',
      manifestVersion: 1,
      sandboxCapabilityDigest: 'a' * 64,
    );
    final driver = NativeAgentDriver<Object?, Object?, Object?>(capabilities);
    expect(capabilities.productionTrusted, isTrue);
    expect(
      driver.effectDisposition('host.file.write').effectControl,
      EffectControl.managed,
    );
    expect(
      () => driver.effectDisposition('forged.tool'),
      throwsArgumentError,
    );
    expect(
      () => driver.verifySandboxCapabilityDigest('b' * 64),
      throwsStateError,
    );
  });
}
