import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  const zeroPayload = '00000000000000000000000000000000';

  test('20 bytes encode as a 32-character lowercase Crockford payload', () {
    final generator = OpaqueIdGenerator(
      byteSource: (length) => List<int>.generate(length, (index) => index),
    );

    final id = generator.generateSessionId();

    expect(id.value, startsWith('ses_'));
    expect(id.value.substring(4), hasLength(32));
    expect(
      id.value.substring(4),
      matches(RegExp(r'^[0123456789abcdefghjkmnpqrstvwxyz]{32}$')),
    );
  });

  test('every parser preserves its distinct kind', () {
    final ids = <OpaqueId>[
      SessionId.parse('ses_$zeroPayload'),
      RunId.parse('run_$zeroPayload'),
      EventId.parse('evt_$zeroPayload'),
      CommandId.parse('cmd_$zeroPayload'),
      WorkItemId.parse('wrk_$zeroPayload'),
      AttemptId.parse('att_$zeroPayload'),
      ApprovalId.parse('apr_$zeroPayload'),
      DeferredOperationId.parse('dop_$zeroPayload'),
      RuntimeResourceId.parse('res_$zeroPayload'),
      SnapshotId.parse('snp_$zeroPayload'),
    ];

    expect(ids.map((id) => id.runtimeType).toSet(), hasLength(ids.length));
    expect(SessionId.parse('ses_$zeroPayload'), isNot(RunId));
  });

  test('parsers reject non-canonical and wrong-kind values', () {
    final rejected = <String>[
      'ses_0000000000000000000000000000000',
      'ses_000000000000000000000000000000000',
      'ses_0000000000000000000000000000000i',
      'ses_0000000000000000000000000000000l',
      'ses_0000000000000000000000000000000o',
      'ses_0000000000000000000000000000000u',
      'ses_0000000000000000000000000000000A',
      'run_$zeroPayload',
      'ses-00000000000000000000000000000000',
    ];

    for (final value in rejected) {
      expect(
        () => SessionId.parse(value),
        throwsA(isA<FormatException>()),
        reason: value,
      );
    }
  });

  test('bounded collisions produce a typed entropy failure', () {
    var calls = 0;
    final generator = OpaqueIdGenerator(
      maxAttempts: 3,
      byteSource: (length) {
        calls += 1;
        return List<int>.filled(length, 0);
      },
    );

    expect(
      () => generator.generateEventId(isAllocated: (_) => true),
      throwsA(
        isA<OpaqueIdGenerationException>().having(
          (error) => error.kind,
          'kind',
          OpaqueIdGenerationFailure.collisionLimitExceeded,
        ),
      ),
    );
    expect(calls, 3);
  });

  test('source failure is typed and never falls back', () {
    final generator = OpaqueIdGenerator(
      byteSource: (_) => throw StateError('entropy unavailable'),
    );

    expect(
      generator.generateCommandId,
      throwsA(
        isA<OpaqueIdGenerationException>().having(
          (error) => error.kind,
          'kind',
          OpaqueIdGenerationFailure.sourceUnavailable,
        ),
      ),
    );
  });
}
