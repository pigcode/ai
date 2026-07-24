import 'driver_event.dart';

final class DriverCapabilitySnapshot {
  DriverCapabilitySnapshot({
    required Set<String> capabilities,
    required Set<DriverEventKind> eventKinds,
    this.maximumPayloadBytes = 64 * 1024,
  })  : capabilities = Set<String>.unmodifiable(capabilities),
        eventKinds = Set<DriverEventKind>.unmodifiable(eventKinds) {
    if (maximumPayloadBytes <= 0) {
      throw ArgumentError.value(
        maximumPayloadBytes,
        'maximumPayloadBytes',
        'Must be positive.',
      );
    }
  }

  final Set<String> capabilities;
  final Set<DriverEventKind> eventKinds;
  final int maximumPayloadBytes;

  bool containsAll(DriverCapabilitySnapshot other) =>
      capabilities.containsAll(other.capabilities) &&
      eventKinds.containsAll(other.eventKinds) &&
      maximumPayloadBytes >= other.maximumPayloadBytes;

  DriverCapabilitySnapshot intersect(DriverCapabilitySnapshot other) =>
      DriverCapabilitySnapshot(
        capabilities: capabilities.intersection(other.capabilities),
        eventKinds: eventKinds.intersection(other.eventKinds),
        maximumPayloadBytes: maximumPayloadBytes < other.maximumPayloadBytes
            ? maximumPayloadBytes
            : other.maximumPayloadBytes,
      );
}
