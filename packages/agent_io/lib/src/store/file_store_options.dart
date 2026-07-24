import 'dart:async';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'store_limits.dart';
import 'store_garbage_collector.dart';
import 'store_retention.dart';
import 'store_writer.dart';

typedef StoreCommitFaultCallback = FutureOr<void> Function(
  StoreCommitPoint point,
);

enum StoreCommitPoint {
  createSession,
  append,
  snapshot,
  compaction,
}

/// How [FileAgentStore] treats filesystem permission evidence for its root.
enum FileStoreRootAccessPolicy {
  /// Require a POSIX owner-only (0700-equivalent) Store root.
  requirePrivate,

  /// Explicit test-only escape hatch where permissions are outside the test.
  explicitTestOnly,
}

final class StoreCommitFaults {
  const StoreCommitFaults(this.callback);

  const StoreCommitFaults.none() : callback = null;

  final StoreCommitFaultCallback? callback;

  Future<void> check(StoreCommitPoint point) async => callback?.call(point);
}

final class FileStoreOptions {
  const FileStoreOptions({
    this.defaultDurability = AgentStoreDurability.processCrashFlush,
    this.allowBufferedDurability = false,
    this.lockTimeout = const Duration(seconds: 10),
    this.coordinatorTimeout = const Duration(seconds: 10),
    this.limits = const StoreLimits(),
    this.faults = const StoreWriterFaults.none(),
    this.commitFaults = const StoreCommitFaults.none(),
    this.retentionPolicy = StoreRetentionPolicy.retainAll,
    this.garbageCollectionFaults = const StoreGarbageCollectionFaults.none(),
    this.rootAccessPolicy = FileStoreRootAccessPolicy.requirePrivate,
  });

  final AgentStoreDurability defaultDurability;
  final bool allowBufferedDurability;
  final Duration lockTimeout;
  final Duration coordinatorTimeout;
  final StoreLimits limits;
  final StoreWriterFaults faults;
  final StoreCommitFaults commitFaults;
  final StoreRetentionPolicy retentionPolicy;
  final StoreGarbageCollectionFaults garbageCollectionFaults;
  final FileStoreRootAccessPolicy rootAccessPolicy;
}
