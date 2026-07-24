import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import 'driver_binding_test.dart';

void main() {
  test('old execution and connection epochs are fenced', () {
    const validator = DriverEventValidator();
    final binding = testBinding();
    final cursor = DriverSourceCursor(sourceId: 'source:test');

    for (final proposal in <DriverEvent>[
      event(executionEpoch: 1),
      event(connectionEpoch: 2),
    ]) {
      final result = validator.validate(
        binding: binding,
        proposal: proposal,
        cursor: cursor,
      );
      expect(result.disposition, DriverProposalDisposition.fenced);
      expect(result.changesDomain, isFalse);
      expect(result.audit!.code, contains('epoch'));
    }
  });

  test('unbound future epochs are protocol violations', () {
    const validator = DriverEventValidator();
    final binding = testBinding();
    final cursor = DriverSourceCursor(sourceId: 'source:test');

    for (final proposal in <DriverEvent>[
      event(executionEpoch: 3),
      event(connectionEpoch: 4),
    ]) {
      final result = validator.validate(
        binding: binding,
        proposal: proposal,
        cursor: cursor,
      );
      expect(
        result.disposition,
        DriverProposalDisposition.protocolViolation,
      );
      expect(result.audit!.code, 'future_epoch');
    }
  });
}
