import '../id/opaque_id.dart';
import '../event/agent_event_metadata.dart';
import '../json/canonical_json.dart';
import '../json/domain_json.dart';

enum DriverEventKind {
  attemptStarted,
  runStarted,
  runSuspended,
  workProposed,
  workSucceeded,
  workFailed,
  workOutcomeUnknown,
  sourceDrained,
  terminalCompleted,
  terminalFailed,
  cancellationBarrier,
  interrupted,
}

final class DriverEvent {
  DriverEvent({
    required this.driverId,
    required this.sessionId,
    this.runId,
    this.attemptId,
    this.executionEpoch,
    required this.connectionEpoch,
    required this.sourceId,
    required this.sourceOrdinal,
    this.sourceWatermark,
    required this.kind,
    required Map<String, Object?> payload,
    Map<String, Object?> metadata = const <String, Object?>{},
  })  : payload = _freezeDriverJson(payload),
        metadata = _freezeDriverJson(metadata);

  final String driverId;
  final SessionId sessionId;
  final RunId? runId;
  final AttemptId? attemptId;
  final int? executionEpoch;
  final int connectionEpoch;
  final String sourceId;
  final int sourceOrdinal;
  final int? sourceWatermark;
  final DriverEventKind kind;
  final Map<String, Object?> payload;
  final Map<String, Object?> metadata;

  String get contentDigest => canonicalJsonSha256(<String, Object?>{
        'attemptId': attemptId?.value,
        'connectionEpoch': connectionEpoch,
        'driverId': driverId,
        'executionEpoch': executionEpoch,
        'kind': kind.name,
        'metadata': metadata,
        'payload': payload,
        'runId': runId?.value,
        'sessionId': sessionId.value,
        'sourceId': sourceId,
        'sourceOrdinal': sourceOrdinal,
        'sourceWatermark': sourceWatermark,
      });
}

Map<String, Object?> _freezeDriverJson(Map<String, Object?> value) {
  final frozen = DomainJson.freeze(value)! as Map<String, Object?>;
  validateSafePersistedJson(frozen);
  return frozen;
}
