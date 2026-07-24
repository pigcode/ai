import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';
import 'package:test/test.dart';

void main() {
  test('current-only RPC and event are unavailable at 4.16', () {
    final registry = VmServiceModelRegistry.instance;
    expect(
      registry.isRpcAvailable(
        'getQueuedMicrotasks',
        const VmServiceWireVersion(4, 16),
      ),
      isFalse,
    );
    expect(
      registry.isRpcAvailable(
        'getQueuedMicrotasks',
        const VmServiceWireVersion(4, 21),
      ),
      isTrue,
    );
    expect(
      registry.isEventKindAvailable(
        'TimerSignificantlyOverdue',
        const VmServiceWireVersion(4, 16),
      ),
      isFalse,
    );
  });

  test('unknown extension types and event kinds remain inspectable', () {
    final type = VmServiceTypeValue.parse('FutureResponse');
    final event = VmServiceEventKind.parse('FutureEvent');

    expect(type.isKnown, isFalse);
    expect(event.isKnown, isFalse);
    expect(type.value, 'FutureResponse');
    expect(event.value, 'FutureEvent');
  });
}
