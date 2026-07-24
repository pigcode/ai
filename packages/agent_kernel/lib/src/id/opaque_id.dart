const _opaqueIdPayloadLength = 32;
const _opaqueIdAlphabet = '0123456789abcdefghjkmnpqrstvwxyz';

final RegExp _opaqueIdPayloadPattern = RegExp(
  '^[${RegExp.escape(_opaqueIdAlphabet)}]{$_opaqueIdPayloadLength}\$',
);

/// An immutable, kind-separated 160-bit logical identifier.
sealed class OpaqueId {
  const OpaqueId._(this.value);

  /// The canonical prefixed identifier.
  final String value;

  @override
  bool operator ==(Object other) =>
      runtimeType == other.runtimeType &&
      other is OpaqueId &&
      value == other.value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

final class SessionId extends OpaqueId {
  const SessionId._(super.value) : super._();

  factory SessionId.parse(String value) {
    _validateOpaqueId(value, 'ses');
    return SessionId._(value);
  }
}

final class RunId extends OpaqueId {
  const RunId._(super.value) : super._();

  factory RunId.parse(String value) {
    _validateOpaqueId(value, 'run');
    return RunId._(value);
  }
}

final class EventId extends OpaqueId {
  const EventId._(super.value) : super._();

  factory EventId.parse(String value) {
    _validateOpaqueId(value, 'evt');
    return EventId._(value);
  }
}

final class CommandId extends OpaqueId {
  const CommandId._(super.value) : super._();

  factory CommandId.parse(String value) {
    _validateOpaqueId(value, 'cmd');
    return CommandId._(value);
  }
}

final class WorkItemId extends OpaqueId {
  const WorkItemId._(super.value) : super._();

  factory WorkItemId.parse(String value) {
    _validateOpaqueId(value, 'wrk');
    return WorkItemId._(value);
  }
}

final class AttemptId extends OpaqueId {
  const AttemptId._(super.value) : super._();

  factory AttemptId.parse(String value) {
    _validateOpaqueId(value, 'att');
    return AttemptId._(value);
  }
}

final class ApprovalId extends OpaqueId {
  const ApprovalId._(super.value) : super._();

  factory ApprovalId.parse(String value) {
    _validateOpaqueId(value, 'apr');
    return ApprovalId._(value);
  }
}

final class DeferredOperationId extends OpaqueId {
  const DeferredOperationId._(super.value) : super._();

  factory DeferredOperationId.parse(String value) {
    _validateOpaqueId(value, 'dop');
    return DeferredOperationId._(value);
  }
}

final class RuntimeResourceId extends OpaqueId {
  const RuntimeResourceId._(super.value) : super._();

  factory RuntimeResourceId.parse(String value) {
    _validateOpaqueId(value, 'res');
    return RuntimeResourceId._(value);
  }
}

final class SnapshotId extends OpaqueId {
  const SnapshotId._(super.value) : super._();

  factory SnapshotId.parse(String value) {
    _validateOpaqueId(value, 'snp');
    return SnapshotId._(value);
  }
}

void _validateOpaqueId(String value, String expectedPrefix) {
  final prefix = '${expectedPrefix}_';
  if (!value.startsWith(prefix) ||
      value.length != prefix.length + _opaqueIdPayloadLength ||
      !_opaqueIdPayloadPattern.hasMatch(value.substring(prefix.length))) {
    throw FormatException(
      'Expected canonical $expectedPrefix opaque identifier.',
      value,
    );
  }
}
