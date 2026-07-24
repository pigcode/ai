import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('cancel requires capability and a tracked request or progress id', () {
    final unsupported = DapCancellationRegistry(
      capabilities: DapCapabilitySnapshot.fromInitialize(
        connectionId: 1,
        capabilities: const <String, Object?>{},
      ),
    )..trackRequest(3);
    expect(
      () => unsupported.cancel(requestId: 3),
      throwsA(isA<DapCancellationException>()),
    );

    final cancellations = DapCancellationRegistry(
      capabilities: DapCapabilitySnapshot.fromInitialize(
        connectionId: 1,
        capabilities: const <String, Object?>{'supportsCancelRequest': true},
      ),
    )
      ..trackRequest(3)
      ..trackProgress('build');
    final requestIntent = cancellations.cancel(requestId: 3);
    final progressIntent = cancellations.cancel(progressId: 'build');
    expect(requestIntent.toJson(), const {'requestId': 3});
    expect(progressIntent.toJson(), const {'progressId': 'build'});
    expect(cancellations.isRequestPending(3), isTrue);
    cancellations.completeRequest(3);
    expect(cancellations.isRequestPending(3), isFalse);
    expect(
      () => cancellations.cancel(requestId: 99),
      throwsA(isA<DapCancellationException>()),
    );
  });
}
