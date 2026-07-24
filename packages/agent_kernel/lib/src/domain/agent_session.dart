import '../id/opaque_id.dart';
import 'agent_definition.dart';
import 'agent_run.dart';
import 'approval.dart';
import 'capability_snapshot.dart';
import 'deferred_operation.dart';
import 'run_attempt.dart';
import 'runtime_resource.dart';
import 'work_item.dart';

enum ConversationAvailability { available, tombstoned }

enum ControlAttachment { attached, detached }

enum RuntimeLiveness { unknown, alive, stopped }

enum ResumeStateAvailability { none, stored }

final class AgentSessionProjection {
  AgentSessionProjection({
    required this.id,
    required this.journalSequence,
    required this.definitionRef,
    required this.capabilitySnapshot,
    required this.conversationAvailability,
    required this.controlAttachment,
    required this.runtimeLiveness,
    required this.resumeStateAvailability,
    required this.currentRunId,
    required Map<RunId, AgentRun> runs,
    required List<RunId> runHistory,
    required Map<WorkItemId, WorkItem> workItems,
    required Map<ApprovalId, Approval> approvals,
    required Map<DeferredOperationId, DeferredOperation> deferredOperations,
    required Map<RuntimeResourceId, RuntimeResource> resources,
  })  : runs = Map<RunId, AgentRun>.unmodifiable(runs),
        runHistory = List<RunId>.unmodifiable(runHistory),
        workItems = Map<WorkItemId, WorkItem>.unmodifiable(workItems),
        approvals = Map<ApprovalId, Approval>.unmodifiable(approvals),
        deferredOperations =
            Map<DeferredOperationId, DeferredOperation>.unmodifiable(
          deferredOperations,
        ),
        resources =
            Map<RuntimeResourceId, RuntimeResource>.unmodifiable(resources);

  factory AgentSessionProjection.fromJson(Map<String, Object?> value) {
    _requireExactProjectionKeys(
      value,
      required: const <String>{
        'sessionId',
        'journalSequence',
        'capabilitySnapshot',
        'conversationAvailability',
        'controlAttachment',
        'runtimeLiveness',
        'resumeStateAvailability',
        'runs',
        'runHistory',
        'workItems',
        'approvals',
        'deferredOperations',
        'resources',
      },
      optional: const <String>{
        'definitionRef',
        'currentRunId',
      },
    );
    final id = SessionId.parse(_requiredProjectionString(value, 'sessionId'));
    final journalSequence = _requiredProjectionInt(value, 'journalSequence');
    if (journalSequence <= 0) {
      throw const FormatException(
        'Snapshot journalSequence must be positive.',
      );
    }
    final definitionValue = value['definitionRef'];
    AgentDefinitionRef? definitionRef;
    if (definitionValue != null) {
      final object = _projectionObject(definitionValue, 'definitionRef');
      _requireExactProjectionKeys(
        object,
        required: const <String>{'value'},
      );
      definitionRef = AgentDefinitionRef(
        _requiredProjectionString(object, 'value'),
      );
    }
    final capabilitySnapshot = CapabilitySnapshot(
      _projectionObject(value['capabilitySnapshot'], 'capabilitySnapshot'),
    );
    final runs = _decodeProjectionMap<RunId, AgentRun>(
      value,
      'runs',
      RunId.parse,
      _decodeRun,
      (run) => run.id,
    );
    final runHistory = _projectionList(value, 'runHistory')
        .map(
          (raw) => RunId.parse(
            _projectionString(raw, 'runHistory entry'),
          ),
        )
        .toList(growable: false);
    if (runHistory.toSet().length != runHistory.length ||
        runHistory.any((runId) => !runs.containsKey(runId))) {
      throw const FormatException(
        'Snapshot runHistory must reference each Run at most once.',
      );
    }
    final workItems = _decodeProjectionMap<WorkItemId, WorkItem>(
      value,
      'workItems',
      WorkItemId.parse,
      _decodeWorkItem,
      (workItem) => workItem.id,
    );
    final approvals = _decodeProjectionMap<ApprovalId, Approval>(
      value,
      'approvals',
      ApprovalId.parse,
      _decodeApproval,
      (approval) => approval.id,
    );
    final deferredOperations =
        _decodeProjectionMap<DeferredOperationId, DeferredOperation>(
      value,
      'deferredOperations',
      DeferredOperationId.parse,
      _decodeDeferredOperation,
      (operation) => operation.id,
    );
    final resources = _decodeProjectionMap<RuntimeResourceId, RuntimeResource>(
      value,
      'resources',
      RuntimeResourceId.parse,
      _decodeRuntimeResource,
      (resource) => resource.id,
    );
    final currentRunValue = value['currentRunId'];
    final currentRunId = currentRunValue == null
        ? null
        : RunId.parse(_projectionString(currentRunValue, 'currentRunId'));
    if (currentRunId != null && !runs.containsKey(currentRunId)) {
      throw const FormatException(
        'Snapshot currentRunId does not reference a Run.',
      );
    }
    for (final workItem in workItems.values) {
      if (!runs.containsKey(workItem.runId) ||
          (workItem.approvalId != null &&
              !approvals.containsKey(workItem.approvalId))) {
        throw const FormatException(
          'Snapshot WorkItem references are not closed.',
        );
      }
    }
    for (final approval in approvals.values) {
      if (!workItems.containsKey(approval.workItemId)) {
        throw const FormatException(
          'Snapshot Approval references an unknown WorkItem.',
        );
      }
    }
    for (final operation in deferredOperations.values) {
      if (!runs.containsKey(operation.originRunId)) {
        throw const FormatException(
          'Snapshot DeferredOperation references an unknown Run.',
        );
      }
    }
    for (final resource in resources.values) {
      if ((resource.originRunId != null &&
              !runs.containsKey(resource.originRunId)) ||
          (resource.ownerRunId != null &&
              !runs.containsKey(resource.ownerRunId))) {
        throw const FormatException(
          'Snapshot RuntimeResource references an unknown Run.',
        );
      }
    }
    return AgentSessionProjection(
      id: id,
      journalSequence: journalSequence,
      definitionRef: definitionRef,
      capabilitySnapshot: capabilitySnapshot,
      conversationAvailability: _projectionEnum(
        ConversationAvailability.values,
        value,
        'conversationAvailability',
      ),
      controlAttachment: _projectionEnum(
        ControlAttachment.values,
        value,
        'controlAttachment',
      ),
      runtimeLiveness: _projectionEnum(
        RuntimeLiveness.values,
        value,
        'runtimeLiveness',
      ),
      resumeStateAvailability: _projectionEnum(
        ResumeStateAvailability.values,
        value,
        'resumeStateAvailability',
      ),
      currentRunId: currentRunId,
      runs: runs,
      runHistory: runHistory,
      workItems: workItems,
      approvals: approvals,
      deferredOperations: deferredOperations,
      resources: resources,
    );
  }

  final SessionId id;
  final int journalSequence;
  final AgentDefinitionRef? definitionRef;
  final CapabilitySnapshot capabilitySnapshot;
  final ConversationAvailability conversationAvailability;
  final ControlAttachment controlAttachment;
  final RuntimeLiveness runtimeLiveness;
  final ResumeStateAvailability resumeStateAvailability;
  final RunId? currentRunId;
  final Map<RunId, AgentRun> runs;
  final List<RunId> runHistory;
  final Map<WorkItemId, WorkItem> workItems;
  final Map<ApprovalId, Approval> approvals;
  final Map<DeferredOperationId, DeferredOperation> deferredOperations;
  final Map<RuntimeResourceId, RuntimeResource> resources;

  AgentSessionProjection copyWith({
    int? journalSequence,
    AgentDefinitionRef? definitionRef,
    CapabilitySnapshot? capabilitySnapshot,
    ConversationAvailability? conversationAvailability,
    ControlAttachment? controlAttachment,
    RuntimeLiveness? runtimeLiveness,
    ResumeStateAvailability? resumeStateAvailability,
    RunId? currentRunId,
    bool clearCurrentRun = false,
    Map<RunId, AgentRun>? runs,
    List<RunId>? runHistory,
    Map<WorkItemId, WorkItem>? workItems,
    Map<ApprovalId, Approval>? approvals,
    Map<DeferredOperationId, DeferredOperation>? deferredOperations,
    Map<RuntimeResourceId, RuntimeResource>? resources,
  }) =>
      AgentSessionProjection(
        id: id,
        journalSequence: journalSequence ?? this.journalSequence,
        definitionRef: definitionRef ?? this.definitionRef,
        capabilitySnapshot: capabilitySnapshot ?? this.capabilitySnapshot,
        conversationAvailability:
            conversationAvailability ?? this.conversationAvailability,
        controlAttachment: controlAttachment ?? this.controlAttachment,
        runtimeLiveness: runtimeLiveness ?? this.runtimeLiveness,
        resumeStateAvailability:
            resumeStateAvailability ?? this.resumeStateAvailability,
        currentRunId:
            clearCurrentRun ? null : currentRunId ?? this.currentRunId,
        runs: runs ?? this.runs,
        runHistory: runHistory ?? this.runHistory,
        workItems: workItems ?? this.workItems,
        approvals: approvals ?? this.approvals,
        deferredOperations: deferredOperations ?? this.deferredOperations,
        resources: resources ?? this.resources,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'sessionId': id.value,
        'journalSequence': journalSequence,
        if (definitionRef != null) 'definitionRef': definitionRef!.toJson(),
        'capabilitySnapshot': capabilitySnapshot.toJson(),
        'conversationAvailability': conversationAvailability.name,
        'controlAttachment': controlAttachment.name,
        'runtimeLiveness': runtimeLiveness.name,
        'resumeStateAvailability': resumeStateAvailability.name,
        if (currentRunId != null) 'currentRunId': currentRunId!.value,
        'runs': <String, Object?>{
          for (final entry in runs.entries)
            entry.key.value: entry.value.toJson(),
        },
        'runHistory': runHistory.map((id) => id.value).toList(growable: false),
        'workItems': <String, Object?>{
          for (final entry in workItems.entries)
            entry.key.value: entry.value.toJson(),
        },
        'approvals': <String, Object?>{
          for (final entry in approvals.entries)
            entry.key.value: entry.value.toJson(),
        },
        'deferredOperations': <String, Object?>{
          for (final entry in deferredOperations.entries)
            entry.key.value: entry.value.toJson(),
        },
        'resources': <String, Object?>{
          for (final entry in resources.entries)
            entry.key.value: entry.value.toJson(),
        },
      };
}

AgentRun _decodeRun(Map<String, Object?> value) {
  _requireExactProjectionKeys(
    value,
    required: const <String>{'id', 'state', 'attempts'},
    optional: const <String>{'currentAttemptId', 'terminalEventId'},
  );
  final attempts = _decodeProjectionMap<AttemptId, RunAttempt>(
    value,
    'attempts',
    AttemptId.parse,
    _decodeAttempt,
    (attempt) => attempt.id,
  );
  final currentAttemptValue = value['currentAttemptId'];
  final currentAttemptId = currentAttemptValue == null
      ? null
      : AttemptId.parse(
          _projectionString(currentAttemptValue, 'currentAttemptId'),
        );
  if (currentAttemptId != null && !attempts.containsKey(currentAttemptId)) {
    throw const FormatException(
      'Snapshot currentAttemptId does not reference an Attempt.',
    );
  }
  final terminalEventValue = value['terminalEventId'];
  return AgentRun(
    id: RunId.parse(_requiredProjectionString(value, 'id')),
    state: _projectionEnum(AgentRunState.values, value, 'state'),
    attempts: attempts,
    currentAttemptId: currentAttemptId,
    terminalEventId: terminalEventValue == null
        ? null
        : EventId.parse(
            _projectionString(terminalEventValue, 'terminalEventId'),
          ),
  );
}

RunAttempt _decodeAttempt(Map<String, Object?> value) {
  _requireExactProjectionKeys(
    value,
    required: const <String>{'id', 'state', 'executionEpoch'},
  );
  final executionEpoch = _requiredProjectionInt(value, 'executionEpoch');
  if (executionEpoch < 0) {
    throw const FormatException(
      'Snapshot executionEpoch cannot be negative.',
    );
  }
  return RunAttempt(
    id: AttemptId.parse(_requiredProjectionString(value, 'id')),
    state: _projectionEnum(RunAttemptState.values, value, 'state'),
    executionEpoch: executionEpoch,
  );
}

WorkItem _decodeWorkItem(Map<String, Object?> value) {
  _requireExactProjectionKeys(
    value,
    required: const <String>{'id', 'runId', 'state', 'effectControl'},
    optional: const <String>{'approvalId'},
  );
  final approvalValue = value['approvalId'];
  return WorkItem(
    id: WorkItemId.parse(_requiredProjectionString(value, 'id')),
    runId: RunId.parse(_requiredProjectionString(value, 'runId')),
    state: _projectionEnum(WorkItemState.values, value, 'state'),
    effectControl: _projectionEnum(
      EffectControl.values,
      value,
      'effectControl',
    ),
    approvalId: approvalValue == null
        ? null
        : ApprovalId.parse(
            _projectionString(approvalValue, 'approvalId'),
          ),
  );
}

Approval _decodeApproval(Map<String, Object?> value) {
  _requireExactProjectionKeys(
    value,
    required: const <String>{'id', 'workItemId', 'state'},
    optional: const <String>{'bindingDigest'},
  );
  final bindingDigest = value['bindingDigest'];
  return Approval(
    id: ApprovalId.parse(_requiredProjectionString(value, 'id')),
    workItemId:
        WorkItemId.parse(_requiredProjectionString(value, 'workItemId')),
    state: _projectionEnum(ApprovalState.values, value, 'state'),
    bindingDigest: bindingDigest == null
        ? null
        : _projectionString(bindingDigest, 'bindingDigest'),
  );
}

DeferredOperation _decodeDeferredOperation(Map<String, Object?> value) {
  _requireExactProjectionKeys(
    value,
    required: const <String>{
      'id',
      'originRunId',
      'owner',
      'state',
      'cancellationPolicy',
    },
    optional: const <String>{
      'deadlineAt',
      'ownershipTransferDigest',
      'terminalDigest',
      'terminalResult',
    },
  );
  final deadlineValue = value['deadlineAt'];
  final ownershipDigest = value['ownershipTransferDigest'];
  final terminalDigest = value['terminalDigest'];
  return DeferredOperation(
    id: DeferredOperationId.parse(_requiredProjectionString(value, 'id')),
    originRunId: RunId.parse(_requiredProjectionString(value, 'originRunId')),
    owner: _projectionEnum(
      DeferredOperationOwner.values,
      value,
      'owner',
    ),
    state: _projectionEnum(
      DeferredOperationState.values,
      value,
      'state',
    ),
    cancellationPolicy: _projectionEnum(
      DeferredCancellationPolicy.values,
      value,
      'cancellationPolicy',
    ),
    deadlineAt: deadlineValue == null
        ? null
        : DateTime.parse(_projectionString(deadlineValue, 'deadlineAt')),
    ownershipTransferDigest: ownershipDigest == null
        ? null
        : _projectionString(
            ownershipDigest,
            'ownershipTransferDigest',
          ),
    terminalDigest: terminalDigest == null
        ? null
        : _projectionString(terminalDigest, 'terminalDigest'),
    terminalResult: value['terminalResult'],
  );
}

RuntimeResource _decodeRuntimeResource(Map<String, Object?> value) {
  _requireExactProjectionKeys(
    value,
    required: const <String>{'id', 'state', 'owner'},
    optional: const <String>{
      'originRunId',
      'ownerRunId',
      'ownershipTransferDigest',
      'terminalDigest',
    },
  );
  final originRunValue = value['originRunId'];
  final ownerRunValue = value['ownerRunId'];
  final ownershipDigest = value['ownershipTransferDigest'];
  final terminalDigest = value['terminalDigest'];
  return RuntimeResource(
    id: RuntimeResourceId.parse(_requiredProjectionString(value, 'id')),
    state: _projectionEnum(RuntimeResourceState.values, value, 'state'),
    owner: _projectionEnum(RuntimeResourceOwner.values, value, 'owner'),
    originRunId: originRunValue == null
        ? null
        : RunId.parse(_projectionString(originRunValue, 'originRunId')),
    ownerRunId: ownerRunValue == null
        ? null
        : RunId.parse(_projectionString(ownerRunValue, 'ownerRunId')),
    ownershipTransferDigest: ownershipDigest == null
        ? null
        : _projectionString(
            ownershipDigest,
            'ownershipTransferDigest',
          ),
    terminalDigest: terminalDigest == null
        ? null
        : _projectionString(terminalDigest, 'terminalDigest'),
  );
}

Map<K, V> _decodeProjectionMap<K, V>(
  Map<String, Object?> parent,
  String key,
  K Function(String) parseKey,
  V Function(Map<String, Object?>) parseValue,
  K Function(V) valueKey,
) {
  final object = _projectionObject(parent[key], key);
  final result = <K, V>{};
  for (final entry in object.entries) {
    final parsedKey = parseKey(entry.key);
    final parsedValue = parseValue(
      _projectionObject(entry.value, '$key.${entry.key}'),
    );
    if (valueKey(parsedValue) != parsedKey || result.containsKey(parsedKey)) {
      throw FormatException(
        'Snapshot $key key does not match its value.',
      );
    }
    result[parsedKey] = parsedValue;
  }
  return result;
}

T _projectionEnum<T extends Enum>(
  List<T> values,
  Map<String, Object?> object,
  String key,
) {
  final name = _requiredProjectionString(object, key);
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Snapshot $key has an unknown value.');
}

void _requireExactProjectionKeys(
  Map<String, Object?> value, {
  required Set<String> required,
  Set<String> optional = const <String>{},
}) {
  if (!value.keys.toSet().containsAll(required) ||
      value.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    throw const FormatException(
      'Snapshot projection has missing or unknown fields.',
    );
  }
}

Map<String, Object?> _projectionObject(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Snapshot $label must be an object.');
  }
  return value;
}

List<Object?> _projectionList(
  Map<String, Object?> object,
  String key,
) {
  final value = object[key];
  if (value is! List<Object?>) {
    throw FormatException('Snapshot $key must be a list.');
  }
  return value;
}

String _requiredProjectionString(
  Map<String, Object?> object,
  String key,
) =>
    _projectionString(object[key], key);

String _projectionString(Object? value, String label) {
  if (value is! String) {
    throw FormatException('Snapshot $label must be a string.');
  }
  return value;
}

int _requiredProjectionInt(
  Map<String, Object?> object,
  String key,
) {
  final value = object[key];
  if (value is! int) {
    throw FormatException('Snapshot $key must be an integer.');
  }
  return value;
}
