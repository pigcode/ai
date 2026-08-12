import 'package:pigcode_ai_agent/pigcode_ai_agent.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('AI SDK facts map to validated DriverEvent sequence', () {
    final capabilities = _capabilities();
    final binding = _binding(capabilities: capabilities);
    final mapping = AiSdkDriverMapping(binding, capabilities: capabilities);

    final accepted = mapping.accepted();
    expect(
      accepted.map((event) => event.kind),
      <DriverEventKind>[
        DriverEventKind.attemptStarted,
        DriverEventKind.runStarted,
      ],
    );
    final delta = mapping.modelDelta('bounded text');
    expect(delta.delta, 'bounded text');
    final completed = mapping.completed(<String, Object?>{'text': 'done'});
    expect(completed.kind, DriverEventKind.terminalCompleted);
    expect(
      mapping.validate(completed).disposition,
      DriverProposalDisposition.accepted,
    );
  });

  test('oversized model delta fails before becoming canonical', () {
    final capabilities = _capabilities(maximumPayloadBytes: 16);
    final mapping = AiSdkDriverMapping(
      _binding(capabilities: capabilities),
      capabilities: capabilities,
    );
    expect(
      () => mapping.modelDelta(''.padLeft(128, 'x')),
      throwsA(isA<NativeAgentDriverException>()),
    );
  });

  test('tool effect control comes only from the fixed manifest', () {
    final capabilities = _capabilities(
      toolEffects: const <String, EffectControl>{
        'external.shell': EffectControl.observedOnly,
      },
    );
    final mapping = AiSdkDriverMapping(
      _binding(capabilities: capabilities),
      capabilities: capabilities,
    );

    final event = mapping.toolCall(
      workItemId: WorkItemId.parse('wrk_${''.padLeft(32, '3')}'),
      toolIdentity: 'external.shell',
    );

    expect(event.payload['effectControl'], 'observedOnly');
    expect(
      mapping.validate(event).disposition,
      DriverProposalDisposition.accepted,
    );
  });
}

NativeDriverCapabilities _capabilities({
  int maximumPayloadBytes = 64 * 1024,
  Map<String, EffectControl> toolEffects = const <String, EffectControl>{},
}) =>
    NativeDriverCapabilities.unsafeDev(
      toolEffects: toolEffects,
      maximumPayloadBytes: maximumPayloadBytes,
    );

DriverBinding _binding({required NativeDriverCapabilities capabilities}) {
  final snapshot = capabilities.snapshot;
  return DriverBinding(
    driverId: 'native',
    sessionId: SessionId.parse('ses_${''.padLeft(32, '0')}'),
    runId: RunId.parse('run_${''.padLeft(32, '1')}'),
    attemptId: AttemptId.parse('att_${''.padLeft(32, '2')}'),
    executionEpoch: 1,
    connectionEpoch: 1,
    manifestCapabilities: snapshot,
    sessionCapabilities: snapshot,
  );
}
