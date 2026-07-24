import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import 'driver_binding_test.dart';

void main() {
  test('unknown payload and privileged metadata fail closed', () {
    const validator = DriverEventValidator();
    final binding = testBinding();
    final cursor = DriverSourceCursor(sourceId: 'source:test');

    final unknownPayload = validator.validate(
      binding: binding,
      proposal: event(payload: const <String, Object?>{'unknown': true}),
      cursor: cursor,
    );
    expect(
      unknownPayload.disposition,
      DriverProposalDisposition.protocolViolation,
    );
    expect(unknownPayload.audit!.code, 'unknown_payload_field');

    final metadataUpgrade = validator.validate(
      binding: binding,
      proposal: event(
        metadata: const <String, Object?>{'approvalEvidence': 'forged'},
      ),
      cursor: cursor,
    );
    expect(
      metadataUpgrade.disposition,
      DriverProposalDisposition.protocolViolation,
    );
    expect(metadataUpgrade.audit!.code, 'metadata_privilege_escalation');
  });

  test('effect control must match trusted persisted context', () {
    const validator = DriverEventValidator();
    final cursor = DriverSourceCursor(sourceId: 'source:test');
    final proposal = event(
      kind: DriverEventKind.workProposed,
      payload: const <String, Object?>{
        'workItemId': 'wrk_00000000000000000000000000000000',
        'effectControl': 'managed',
      },
    );

    expect(
      validator
          .validate(
            binding: testBinding(),
            proposal: proposal,
            cursor: cursor,
            expectedEffectControl: EffectControl.interceptable,
          )
          .audit!
          .code,
      'effect_control_escalation',
    );
    expect(
      validator
          .validate(
            binding: testBinding(),
            proposal: proposal,
            cursor: cursor,
            expectedEffectControl: EffectControl.managed,
          )
          .disposition,
      DriverProposalDisposition.accepted,
    );
  });

  test('terminal requires a source watermark and pinned capability', () {
    const validator = DriverEventValidator();
    final cursor = DriverSourceCursor(sourceId: 'source:test');
    final missingWatermark = validator.validate(
      binding: testBinding(),
      proposal: event(kind: DriverEventKind.terminalCompleted),
      cursor: cursor,
    );
    expect(missingWatermark.audit!.code, 'terminal_watermark_missing');

    final notPinned = validator.validate(
      binding: testBinding(
        eventKinds: const <DriverEventKind>{DriverEventKind.runStarted},
      ),
      proposal: event(
        kind: DriverEventKind.terminalCompleted,
        sourceWatermark: 1,
      ),
      cursor: cursor,
    );
    expect(notPinned.disposition, DriverProposalDisposition.fenced);
    expect(notPinned.audit!.code, 'capability_not_pinned');
  });

  test('payload byte limit is enforced before proposal acceptance', () {
    const validator = DriverEventValidator();
    final result = validator.validate(
      binding: testBinding(maximumPayloadBytes: 1),
      proposal: event(),
      cursor: DriverSourceCursor(sourceId: 'source:test'),
    );

    expect(
      result.disposition,
      DriverProposalDisposition.protocolViolation,
    );
    expect(result.audit!.code, 'payload_too_large');
  });
}
