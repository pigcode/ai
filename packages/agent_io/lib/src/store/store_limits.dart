final class StoreLimits {
  const StoreLimits({
    this.maximumEventBodyBytes = 4 * 1024 * 1024,
    this.maximumBatchEventCount = 1024,
    this.maximumBatchMetadataBytes = 1024 * 1024,
    this.maximumBatchBytes = 64 * 1024 * 1024,
    this.maximumSegmentCount = 100000,
    this.maximumReplayPageEvents = 4096,
    this.maximumSnapshotBytes = 64 * 1024 * 1024,
    this.maximumRecoveryBytes = 512 * 1024 * 1024,
    this.maximumRegistryEntries = 1000000,
    this.maximumRegistryBytes = 64 * 1024 * 1024,
  })  : assert(maximumEventBodyBytes > 0),
        assert(maximumEventBodyBytes <= hardMaximumEventBodyBytes),
        assert(maximumBatchEventCount > 0),
        assert(maximumBatchMetadataBytes > 0),
        assert(maximumBatchBytes > 0),
        assert(maximumBatchBytes <= hardMaximumBatchBytes),
        assert(maximumSegmentCount > 0),
        assert(maximumReplayPageEvents > 0),
        assert(maximumSnapshotBytes > 0),
        assert(maximumSnapshotBytes <= hardMaximumSnapshotBytes),
        assert(maximumRecoveryBytes > 0),
        assert(maximumRecoveryBytes <= hardMaximumRecoveryBytes),
        assert(maximumRegistryEntries > 0),
        assert(maximumRegistryBytes > 0),
        assert(maximumRegistryBytes <= hardMaximumRegistryBytes);

  static const hardMaximumEventBodyBytes = 64 * 1024 * 1024;
  static const hardMaximumBatchBytes = 128 * 1024 * 1024;
  static const hardMaximumSnapshotBytes = 256 * 1024 * 1024;
  static const hardMaximumRecoveryBytes = 2 * 1024 * 1024 * 1024;
  static const hardMaximumRegistryBytes = 256 * 1024 * 1024;

  final int maximumEventBodyBytes;
  final int maximumBatchEventCount;
  final int maximumBatchMetadataBytes;
  final int maximumBatchBytes;
  final int maximumSegmentCount;
  final int maximumReplayPageEvents;
  final int maximumSnapshotBytes;
  final int maximumRecoveryBytes;
  final int maximumRegistryEntries;
  final int maximumRegistryBytes;
}
