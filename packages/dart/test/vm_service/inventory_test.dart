import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';
import 'package:test/test.dart';

void main() {
  test('generated VM Service union is complete and classified', () {
    final registry = VmServiceModelRegistry.instance;

    expect(registry.minimumRpcNames, hasLength(60));
    expect(registry.currentRpcNames, hasLength(61));
    expect(registry.minimumTypeNames, hasLength(81));
    expect(registry.currentTypeNames, hasLength(83));
    expect(registry.currentOnlyRpcNames, {'getQueuedMicrotasks'});
    expect(
      registry.currentOnlyTypeNames,
      {'Microtask', 'QueuedMicrotasks'},
    );
    expect(registry.minimumEventKinds, hasLength(31));
    expect(registry.currentEventKinds, hasLength(32));
    expect(
      registry.currentEventKinds.difference(registry.minimumEventKinds),
      {'TimerSignificantlyOverdue'},
    );
    expect(registry.unclassifiedDifferences, isEmpty);
  });
}
