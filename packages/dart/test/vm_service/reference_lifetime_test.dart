import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';
import 'package:test/test.dart';

void main() {
  test('temporary IDs expire across pause, isolate, and connection changes',
      () {
    final state = VmServiceExecutionState(connectionId: 1);
    final pause = state.pause('isolates/1');
    final references = VmServiceReferenceRegistry()
      ..bindObject(
        id: 'objects/1',
        isolateId: 'isolates/1',
        temporary: true,
        state: state,
      )
      ..bindIsolate(id: 'isolates/1', state: state);

    expect(
      references.resolveObject('objects/1', state: state).pauseGeneration,
      pause,
    );
    state.resume('isolates/1');
    expect(
      () => references.resolveObject('objects/1', state: state),
      throwsA(isA<ToolingProtocolStateError>()),
    );

    state.exitIsolate('isolates/1');
    expect(
      () => references.resolveIsolate('isolates/1', state: state),
      throwsA(isA<ToolingProtocolStateError>()),
    );
    state.disconnect();
    expect(
      () => references.bindIsolate(id: 'isolates/2', state: state),
      throwsA(isA<ToolingProtocolStateError>()),
    );
  });

  test('Sentinel is not accepted as an object reference', () {
    final state = VmServiceExecutionState(connectionId: 1)..pause('isolates/1');
    expect(
      () => VmServiceReferenceRegistry().bindResponse(
        const <String, Object?>{
          'type': 'Sentinel',
          'kind': 'Expired',
          'valueAsString': '<expired>',
        },
        isolateId: 'isolates/1',
        state: state,
      ),
      throwsA(isA<ToolingProtocolStateError>()),
    );
  });
}
