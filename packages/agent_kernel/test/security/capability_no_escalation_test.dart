import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('P3-TM-ELEV-01 recovered capability is an intersection', () {
    final currentManifest = DriverCapabilitySnapshot(
      capabilities: const <String>{'run'},
      eventKinds: const <DriverEventKind>{DriverEventKind.runStarted},
      maximumPayloadBytes: 1024,
    );
    final persisted = DriverCapabilitySnapshot(
      capabilities: const <String>{'run', 'managedEffect'},
      eventKinds: const <DriverEventKind>{
        DriverEventKind.runStarted,
        DriverEventKind.workProposed,
      },
      maximumPayloadBytes: 4096,
    );

    final binding = DriverBinding.bind(
      driverId: 'driver:test',
      sessionId: SessionId.parse('ses_00000000000000000000000000000000'),
      runId: RunId.parse('run_00000000000000000000000000000000'),
      attemptId: AttemptId.parse('att_00000000000000000000000000000000'),
      executionEpoch: 1,
      connectionEpoch: 1,
      manifestCapabilities: currentManifest,
      persistedSessionCapabilities: persisted,
    );

    expect(binding.sessionCapabilities.capabilities, <String>{'run'});
    expect(
      binding.sessionCapabilities.eventKinds,
      <DriverEventKind>{DriverEventKind.runStarted},
    );
    expect(binding.sessionCapabilities.maximumPayloadBytes, 1024);
  });

  test('P3-TM-ELEV-02 direct expanded binding is rejected', () {
    final narrow = DriverCapabilitySnapshot(
      capabilities: const <String>{'run'},
      eventKinds: const <DriverEventKind>{DriverEventKind.runStarted},
    );
    final expanded = DriverCapabilitySnapshot(
      capabilities: const <String>{'run', 'managedEffect'},
      eventKinds: const <DriverEventKind>{
        DriverEventKind.runStarted,
        DriverEventKind.workProposed,
      },
    );

    expect(
      () => DriverBinding(
        driverId: 'driver:test',
        sessionId: SessionId.parse('ses_00000000000000000000000000000000'),
        runId: RunId.parse('run_00000000000000000000000000000000'),
        attemptId: AttemptId.parse('att_00000000000000000000000000000000'),
        executionEpoch: 1,
        connectionEpoch: 1,
        manifestCapabilities: narrow,
        sessionCapabilities: expanded,
      ),
      throwsArgumentError,
    );
  });
}
