import '../id/opaque_id.dart';
import '../kernel/session_handle.dart';
import 'agent_command.dart';

final class AgentCommandReceipt {
  AgentCommandReceipt({
    required this.commandId,
    required this.type,
    required this.sessionId,
    this.runId,
    this.workItemId,
    this.approvalId,
    this.deferredOperationId,
    this.runtimeResourceId,
    required List<EventId> eventIds,
    required this.acceptedThroughSequence,
    this.sessionHandle,
  }) : eventIds = List<EventId>.unmodifiable(eventIds);

  factory AgentCommandReceipt.fromJson(
    Map<String, Object?> json, {
    AgentSessionHandle? sessionHandle,
  }) {
    final eventIds = json['eventIds'];
    if (eventIds is! List<Object?>) {
      throw const FormatException('Command receipt eventIds is invalid.');
    }
    return AgentCommandReceipt(
      commandId: CommandId.parse(json['commandId']! as String),
      type: AgentCommandType.values.byName(json['type']! as String),
      sessionId: SessionId.parse(json['sessionId']! as String),
      runId:
          json['runId'] == null ? null : RunId.parse(json['runId']! as String),
      workItemId: json['workItemId'] == null
          ? null
          : WorkItemId.parse(json['workItemId']! as String),
      approvalId: json['approvalId'] == null
          ? null
          : ApprovalId.parse(json['approvalId']! as String),
      deferredOperationId: json['deferredOperationId'] == null
          ? null
          : DeferredOperationId.parse(
              json['deferredOperationId']! as String,
            ),
      runtimeResourceId: json['runtimeResourceId'] == null
          ? null
          : RuntimeResourceId.parse(json['runtimeResourceId']! as String),
      eventIds: eventIds
          .map((value) => EventId.parse(value! as String))
          .toList(growable: false),
      acceptedThroughSequence: json['acceptedThroughSequence']! as int,
      sessionHandle: sessionHandle,
    );
  }

  final CommandId commandId;
  final AgentCommandType type;
  final SessionId sessionId;
  final RunId? runId;
  final WorkItemId? workItemId;
  final ApprovalId? approvalId;
  final DeferredOperationId? deferredOperationId;
  final RuntimeResourceId? runtimeResourceId;
  final List<EventId> eventIds;
  final int acceptedThroughSequence;
  final AgentSessionHandle? sessionHandle;

  Map<String, Object?> toJson() => <String, Object?>{
        'commandId': commandId.value,
        'type': type.name,
        'sessionId': sessionId.value,
        if (runId != null) 'runId': runId!.value,
        if (workItemId != null) 'workItemId': workItemId!.value,
        if (approvalId != null) 'approvalId': approvalId!.value,
        if (deferredOperationId != null)
          'deferredOperationId': deferredOperationId!.value,
        if (runtimeResourceId != null)
          'runtimeResourceId': runtimeResourceId!.value,
        'eventIds': eventIds.map((id) => id.value).toList(growable: false),
        'acceptedThroughSequence': acceptedThroughSequence,
      };
}
