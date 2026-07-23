import 'package:pigcode_ai_provider/src/shared/cancellation.dart';
import 'package:test/test.dart';

void main() {
  group('CancellationController', () {
    test('fresh controller is not cancelled', () {
      final controller = CancellationController();
      expect(controller.isCancelled, isFalse);
      expect(controller.signal.isCancelled, isFalse);
    });

    test('cancel() flips isCancelled on controller and signal', () {
      final controller = CancellationController();
      controller.cancel();
      expect(controller.isCancelled, isTrue);
      expect(controller.signal.isCancelled, isTrue);
    });

    test('cancel() completes whenCancelled', () async {
      final controller = CancellationController();
      final signal = controller.signal;
      var completed = false;
      final waiter = signal.whenCancelled.then((_) => completed = true);
      expect(completed, isFalse);
      controller.cancel();
      await waiter;
      expect(completed, isTrue);
    });

    test('cancel() preserves the first reason', () async {
      final controller = CancellationController();
      final firstReason = StateError('first');

      controller.cancel(firstReason);
      controller.cancel(StateError('second'));
      await controller.signal.whenCancelled;

      expect(controller.signal.reason, same(firstReason));
    });

    test('cancel() without a reason preserves null', () {
      final controller = CancellationController();

      controller.cancel();

      expect(controller.signal.reason, isNull);
    });

    test('whenCancelled resolves even when awaited after cancel()', () async {
      final controller = CancellationController();
      controller.cancel();
      await controller.signal.whenCancelled;
      expect(controller.isCancelled, isTrue);
    });

    test('double cancel() is idempotent and does not throw', () async {
      final controller = CancellationController();
      controller.cancel();
      expect(controller.cancel, returnsNormally);
      expect(controller.isCancelled, isTrue);
      await controller.signal.whenCancelled;
    });

    test('signal returns the same instance across reads', () {
      final controller = CancellationController();
      expect(identical(controller.signal, controller.signal), isTrue);
    });

    test('two controllers are not equal (identity semantics)', () {
      final a = CancellationController();
      final b = CancellationController();
      expect(a == b, isFalse);
      expect(a.signal == b.signal, isFalse);
      expect(a == a, isTrue);
      expect(a.signal == a.signal, isTrue);
    });
  });
}
