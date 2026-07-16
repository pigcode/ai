import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

void main() {
  group('delayCancellable', () {
    test('completes normally after the given duration', () async {
      final stopwatch = Stopwatch()..start();

      await delayCancellable(const Duration(milliseconds: 20));

      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(15));
    });

    test('ends early with an error when cancellation fires first', () async {
      final controller = CancellationController();

      final future = delayCancellable(
        const Duration(seconds: 30),
        cancellation: controller.signal,
      );

      controller.cancel();

      await expectLater(future, throwsA(isA<StateError>()));
    });

    test('rejects immediately when already cancelled', () async {
      final controller = CancellationController();
      controller.cancel();

      await expectLater(
        () => delayCancellable(
          const Duration(seconds: 30),
          cancellation: controller.signal,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
