import '../id/opaque_id.dart';
import 'driver_capability_snapshot.dart';

final class DriverBinding {
  DriverBinding({
    required this.driverId,
    required this.sessionId,
    required this.runId,
    required this.attemptId,
    required this.executionEpoch,
    required this.connectionEpoch,
    required this.manifestCapabilities,
    required this.sessionCapabilities,
  }) {
    if (driverId.isEmpty ||
        executionEpoch <= 0 ||
        connectionEpoch <= 0 ||
        !manifestCapabilities.containsAll(sessionCapabilities)) {
      throw ArgumentError(
        'Driver binding must have positive epochs and non-escalating '
        'Session capabilities.',
      );
    }
  }

  factory DriverBinding.bind({
    required String driverId,
    required SessionId sessionId,
    required RunId runId,
    required AttemptId attemptId,
    required int executionEpoch,
    required int connectionEpoch,
    required DriverCapabilitySnapshot manifestCapabilities,
    required DriverCapabilitySnapshot persistedSessionCapabilities,
  }) =>
      DriverBinding(
        driverId: driverId,
        sessionId: sessionId,
        runId: runId,
        attemptId: attemptId,
        executionEpoch: executionEpoch,
        connectionEpoch: connectionEpoch,
        manifestCapabilities: manifestCapabilities,
        sessionCapabilities:
            manifestCapabilities.intersect(persistedSessionCapabilities),
      );

  final String driverId;
  final SessionId sessionId;
  final RunId runId;
  final AttemptId attemptId;
  final int executionEpoch;
  final int connectionEpoch;
  final DriverCapabilitySnapshot manifestCapabilities;
  final DriverCapabilitySnapshot sessionCapabilities;
}
