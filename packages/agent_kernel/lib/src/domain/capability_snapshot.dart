import '../json/domain_json.dart';
import '../event/agent_event_metadata.dart';

final class CapabilitySnapshot {
  CapabilitySnapshot(Map<String, Object?> value)
      : value = _freezeCapabilitySnapshot(value);

  CapabilitySnapshot.empty() : value = const <String, Object?>{};

  final Map<String, Object?> value;

  Map<String, Object?> toJson() => value;
}

Map<String, Object?> _freezeCapabilitySnapshot(Map<String, Object?> value) {
  final frozen = DomainJson.freeze(value)! as Map<String, Object?>;
  validateSafePersistedJson(frozen);
  return frozen;
}
