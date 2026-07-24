import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import 'driver_binding_test.dart';

void main() {
  test('exact ordinal duplicate is idempotent', () {
    const validator = DriverEventValidator();
    final binding = testBinding();
    final proposal = event();
    final accepted = validator.validate(
      binding: binding,
      proposal: proposal,
      cursor: DriverSourceCursor(sourceId: 'source:test'),
    );
    final duplicate = validator.validate(
      binding: binding,
      proposal: proposal,
      cursor: accepted.cursor,
    );

    expect(accepted.disposition, DriverProposalDisposition.accepted);
    expect(accepted.changesDomain, isTrue);
    expect(duplicate.disposition, DriverProposalDisposition.duplicate);
    expect(duplicate.changesDomain, isFalse);
    expect(duplicate.cursor.lastOrdinal, 1);
  });

  test('same ordinal with different content is a protocol violation', () {
    const validator = DriverEventValidator();
    final binding = testBinding();
    final accepted = validator.validate(
      binding: binding,
      proposal: event(),
      cursor: DriverSourceCursor(sourceId: 'source:test'),
    );
    final changed = validator.validate(
      binding: binding,
      proposal: event(metadata: const <String, Object?>{'trace': 'changed'}),
      cursor: accepted.cursor,
    );

    expect(
      changed.disposition,
      DriverProposalDisposition.protocolViolation,
    );
    expect(changed.audit!.code, 'ordinal_content_mismatch');
  });

  test('ordinal gap enters reconciliation without advancing the cursor', () {
    const validator = DriverEventValidator();
    final result = validator.validate(
      binding: testBinding(),
      proposal: event(sourceOrdinal: 2),
      cursor: DriverSourceCursor(sourceId: 'source:test'),
    );

    expect(result.disposition, DriverProposalDisposition.reconcile);
    expect(result.audit!.code, 'source_ordinal_gap');
    expect(result.cursor.lastOrdinal, 0);
  });

  test('source cursor keeps a bounded exact duplicate window', () {
    var cursor = DriverSourceCursor(
      sourceId: 'source:test',
      maximumRememberedOrdinals: 4,
    );
    for (var ordinal = 1; ordinal <= 10; ordinal++) {
      cursor = cursor.advance(ordinal, 'digest-$ordinal');
    }

    expect(cursor.recentDigests, hasLength(4));
    expect(cursor.recentDigests.keys, <int>[7, 8, 9, 10]);
  });
}
