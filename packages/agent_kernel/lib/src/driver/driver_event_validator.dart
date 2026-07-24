import '../domain/work_item.dart';
import '../event/agent_event_type.dart';
import '../json/canonical_json.dart';
import 'driver_binding.dart';
import 'driver_event.dart';
import 'source_cursor.dart';

enum DriverProposalDisposition {
  accepted,
  duplicate,
  fenced,
  protocolViolation,
  reconcile,
}

final class DriverAuditDiagnostic {
  const DriverAuditDiagnostic({
    required this.code,
    required this.sourceId,
    required this.sourceOrdinal,
  });

  final String code;
  final String sourceId;
  final int sourceOrdinal;
}

final class DriverValidationResult {
  const DriverValidationResult({
    required this.disposition,
    required this.cursor,
    this.canonicalEventType,
    this.audit,
  });

  final DriverProposalDisposition disposition;
  final DriverSourceCursor cursor;
  final AgentEventType? canonicalEventType;
  final DriverAuditDiagnostic? audit;

  bool get changesDomain =>
      disposition == DriverProposalDisposition.accepted &&
      canonicalEventType != null;
}

final class DriverEventValidator {
  const DriverEventValidator();

  DriverValidationResult validate({
    required DriverBinding binding,
    required DriverEvent proposal,
    required DriverSourceCursor cursor,
    EffectControl? expectedEffectControl,
  }) {
    final associationError = _associationError(binding, proposal, cursor);
    if (associationError != null) {
      return _audit(
        DriverProposalDisposition.fenced,
        cursor,
        proposal,
        associationError,
      );
    }
    if (proposal.executionEpoch! > binding.executionEpoch ||
        proposal.connectionEpoch > binding.connectionEpoch) {
      return _audit(
        DriverProposalDisposition.protocolViolation,
        cursor,
        proposal,
        'future_epoch',
      );
    }

    final previousDigest = cursor.recentDigests[proposal.sourceOrdinal];
    if (proposal.sourceOrdinal <= cursor.lastOrdinal) {
      return previousDigest == proposal.contentDigest
          ? DriverValidationResult(
              disposition: DriverProposalDisposition.duplicate,
              cursor: cursor,
            )
          : _audit(
              DriverProposalDisposition.protocolViolation,
              cursor,
              proposal,
              'ordinal_content_mismatch',
            );
    }
    if (proposal.sourceOrdinal != cursor.lastOrdinal + 1) {
      return _audit(
        DriverProposalDisposition.reconcile,
        cursor,
        proposal,
        'source_ordinal_gap',
      );
    }
    if (!binding.sessionCapabilities.eventKinds.contains(proposal.kind)) {
      return _audit(
        DriverProposalDisposition.fenced,
        cursor,
        proposal,
        'capability_not_pinned',
      );
    }
    if (canonicalJsonBytes(proposal.payload).length >
        binding.sessionCapabilities.maximumPayloadBytes) {
      return _audit(
        DriverProposalDisposition.protocolViolation,
        cursor,
        proposal,
        'payload_too_large',
      );
    }
    final schemaError = _validateSchema(
      proposal,
      expectedEffectControl: expectedEffectControl,
    );
    if (schemaError != null) {
      return _audit(
        DriverProposalDisposition.protocolViolation,
        cursor,
        proposal,
        schemaError,
      );
    }
    return DriverValidationResult(
      disposition: DriverProposalDisposition.accepted,
      cursor: cursor.advance(
        proposal.sourceOrdinal,
        proposal.contentDigest,
      ),
      canonicalEventType: _eventType(proposal.kind),
    );
  }

  String? _associationError(
    DriverBinding binding,
    DriverEvent proposal,
    DriverSourceCursor cursor,
  ) {
    if (proposal.driverId != binding.driverId) return 'driver_mismatch';
    if (proposal.sessionId != binding.sessionId) return 'session_mismatch';
    if (proposal.runId != binding.runId) return 'run_mismatch';
    if (proposal.attemptId != binding.attemptId) return 'attempt_mismatch';
    if (proposal.executionEpoch == null ||
        proposal.executionEpoch! < binding.executionEpoch) {
      return 'execution_epoch_fenced';
    }
    if (proposal.connectionEpoch < binding.connectionEpoch) {
      return 'connection_epoch_fenced';
    }
    if (proposal.sourceId != cursor.sourceId) return 'source_mismatch';
    return null;
  }

  String? _validateSchema(
    DriverEvent proposal, {
    required EffectControl? expectedEffectControl,
  }) {
    if (proposal.metadata.keys.any(
      const <String>{
        'capabilitySnapshot',
        'effectControl',
        'approvalEvidence',
      }.contains,
    )) {
      return 'metadata_privilege_escalation';
    }
    final allowedKeys = switch (proposal.kind) {
      DriverEventKind.attemptStarted => const <String>{'executionEpoch'},
      DriverEventKind.runStarted ||
      DriverEventKind.runSuspended ||
      DriverEventKind.sourceDrained =>
        const <String>{},
      DriverEventKind.workProposed => const <String>{
          'workItemId',
          'effectControl',
        },
      DriverEventKind.workSucceeded ||
      DriverEventKind.workFailed ||
      DriverEventKind.workOutcomeUnknown =>
        const <String>{'workItemId'},
      DriverEventKind.terminalCompleted => const <String>{'result'},
      DriverEventKind.terminalFailed => const <String>{'error'},
      DriverEventKind.cancellationBarrier => const <String>{'intentCommandId'},
      DriverEventKind.interrupted => const <String>{'reason'},
    };
    if (proposal.payload.keys.any((key) => !allowedKeys.contains(key))) {
      return 'unknown_payload_field';
    }
    final workItemId = proposal.payload['workItemId'];
    if (proposal.kind.name.startsWith('work') &&
        (workItemId is! String || !workItemId.startsWith('wrk_'))) {
      return 'invalid_work_item_id';
    }
    if (proposal.kind == DriverEventKind.workProposed) {
      final proposedControl = proposal.payload['effectControl'];
      if (expectedEffectControl == null ||
          proposedControl != expectedEffectControl.name) {
        return 'effect_control_escalation';
      }
    }
    if (_isTerminal(proposal.kind) && proposal.sourceWatermark == null) {
      return 'terminal_watermark_missing';
    }
    return null;
  }

  bool _isTerminal(DriverEventKind kind) => switch (kind) {
        DriverEventKind.terminalCompleted ||
        DriverEventKind.terminalFailed ||
        DriverEventKind.cancellationBarrier ||
        DriverEventKind.interrupted =>
          true,
        _ => false,
      };

  AgentEventType _eventType(DriverEventKind kind) => switch (kind) {
        DriverEventKind.attemptStarted => AgentEventType.runAttemptStarted,
        DriverEventKind.runStarted => AgentEventType.runStarted,
        DriverEventKind.runSuspended => AgentEventType.runSuspended,
        DriverEventKind.workProposed => AgentEventType.workProposed,
        DriverEventKind.workSucceeded => AgentEventType.workSucceeded,
        DriverEventKind.workFailed => AgentEventType.workFailed,
        DriverEventKind.workOutcomeUnknown => AgentEventType.workOutcomeUnknown,
        DriverEventKind.sourceDrained => AgentEventType.driverSourceDrained,
        DriverEventKind.terminalCompleted => AgentEventType.runCompleted,
        DriverEventKind.terminalFailed => AgentEventType.runFailed,
        DriverEventKind.cancellationBarrier => AgentEventType.runCancelled,
        DriverEventKind.interrupted => AgentEventType.runInterrupted,
      };

  DriverValidationResult _audit(
    DriverProposalDisposition disposition,
    DriverSourceCursor cursor,
    DriverEvent proposal,
    String code,
  ) =>
      DriverValidationResult(
        disposition: disposition,
        cursor: cursor,
        audit: DriverAuditDiagnostic(
          code: code,
          sourceId: proposal.sourceId,
          sourceOrdinal: proposal.sourceOrdinal,
        ),
      );
}
