import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'native_agent_driver.dart';
import 'native_driver_capabilities.dart';

final class NativeModelDelta {
  const NativeModelDelta(this.delta);

  final String delta;
}

final class AiSdkDriverMapping {
  AiSdkDriverMapping(
    this.binding, {
    required this.capabilities,
    this.sourceId = 'ai-sdk',
    DriverEventValidator validator = const DriverEventValidator(),
  })  : _validator = validator,
        _cursor = DriverSourceCursor(sourceId: sourceId);

  final DriverBinding binding;
  final NativeDriverCapabilities capabilities;
  final String sourceId;
  final DriverEventValidator _validator;
  DriverSourceCursor _cursor;
  int _ordinal = 0;
  final Map<String, EffectControl> _expectedEffects = <String, EffectControl>{};

  List<DriverEvent> accepted() {
    final events = <DriverEvent>[
      _event(
        DriverEventKind.attemptStarted,
        <String, Object?>{'executionEpoch': binding.executionEpoch},
      ),
      _event(DriverEventKind.runStarted, const <String, Object?>{}),
    ];
    for (final event in events) {
      final result = validate(event);
      if (result.disposition != DriverProposalDisposition.accepted) {
        throw const NativeAgentDriverException('run_acceptance_rejected');
      }
    }
    return List<DriverEvent>.unmodifiable(events);
  }

  NativeModelDelta modelDelta(String delta) {
    if (canonicalJsonBytes(<String, Object?>{'delta': delta}).length >
        capabilities.maximumPayloadBytes) {
      throw const NativeAgentDriverException('model_delta_too_large');
    }
    return NativeModelDelta(delta);
  }

  DriverEvent toolCall({
    required WorkItemId workItemId,
    required String toolIdentity,
  }) {
    final effectControl = capabilities.effectFor(toolIdentity);
    _expectedEffects[workItemId.value] = effectControl;
    return _event(
      DriverEventKind.workProposed,
      <String, Object?>{
        'workItemId': workItemId.value,
        'effectControl': effectControl.name,
      },
    );
  }

  DriverEvent toolResult({
    required WorkItemId workItemId,
    required bool succeeded,
  }) =>
      _event(
        succeeded ? DriverEventKind.workSucceeded : DriverEventKind.workFailed,
        <String, Object?>{'workItemId': workItemId.value},
      );

  DriverEvent completed(Map<String, Object?> result) => _terminal(
        DriverEventKind.terminalCompleted,
        <String, Object?>{'result': result},
      );

  DriverEvent failed(String errorCode) => _terminal(
        DriverEventKind.terminalFailed,
        <String, Object?>{
          'error': <String, Object?>{'code': errorCode}
        },
      );

  DriverValidationResult validate(DriverEvent event) {
    final expectedEffectControl = event.kind == DriverEventKind.workProposed
        ? (_expectedEffects[event.payload['workItemId']] ??
            EffectControl.unknown)
        : null;
    final result = _validator.validate(
      binding: binding,
      proposal: event,
      cursor: _cursor,
      expectedEffectControl: expectedEffectControl,
    );
    if (result.disposition == DriverProposalDisposition.accepted) {
      _cursor = result.cursor;
    }
    return result;
  }

  DriverEvent _terminal(
    DriverEventKind kind,
    Map<String, Object?> payload,
  ) {
    final ordinal = _ordinal + 1;
    return _event(kind, payload, sourceWatermark: ordinal);
  }

  DriverEvent _event(
    DriverEventKind kind,
    Map<String, Object?> payload, {
    int? sourceWatermark,
  }) {
    _ordinal += 1;
    return DriverEvent(
      driverId: binding.driverId,
      sessionId: binding.sessionId,
      runId: binding.runId,
      attemptId: binding.attemptId,
      executionEpoch: binding.executionEpoch,
      connectionEpoch: binding.connectionEpoch,
      sourceId: sourceId,
      sourceOrdinal: _ordinal,
      sourceWatermark: sourceWatermark,
      kind: kind,
      payload: payload,
    );
  }
}
