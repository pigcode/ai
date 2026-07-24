import 'dart:async';
import 'dart:io';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

final class StoreGarbageCollectionReport {
  const StoreGarbageCollectionReport({
    required this.retiredCount,
    required this.deletedCount,
  });

  final int retiredCount;
  final int deletedCount;
}

final class StoreGarbageCollector {
  const StoreGarbageCollector({
    this.faults = const StoreGarbageCollectionFaults.none(),
  });

  final StoreGarbageCollectionFaults faults;

  Future<StoreGarbageCollectionReport> collect({
    required Directory retiredDirectory,
    required Map<String, Directory> artifactDirectories,
    required Set<String> protectedCanonicalPaths,
  }) async {
    await retiredDirectory.create(recursive: true);
    var deleted = 0;
    for (final entity in retiredDirectory.listSync(followLinks: false)) {
      if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Retired Store directory contains a non-regular entity.',
        );
      }
      final file = File(entity.path);
      await faults.check(
        StoreGarbageCollectionFaultPoint.beforeDelete,
        file,
      );
      await file.delete();
      deleted++;
    }

    var retired = 0;
    for (final directoryEntry in artifactDirectories.entries) {
      final directory = directoryEntry.value;
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(followLinks: false)) {
        if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const AgentStoreException(
            AgentStoreErrorCode.corruption,
            'Store artifact directory contains a non-regular entity.',
          );
        }
        final file = File(entity.path);
        final canonical = file.absolute.path;
        if (protectedCanonicalPaths.contains(canonical)) continue;
        final retiredName =
            '${directoryEntry.key}--${file.uri.pathSegments.last}';
        await faults.check(
          StoreGarbageCollectionFaultPoint.beforeRetire,
          file,
        );
        await file.rename(
          File.fromUri(
            retiredDirectory.uri.resolve(retiredName),
          ).path,
        );
        retired++;
      }
    }
    return StoreGarbageCollectionReport(
      retiredCount: retired,
      deletedCount: deleted,
    );
  }
}

typedef StoreGarbageCollectionFaultCallback = FutureOr<void> Function(
  StoreGarbageCollectionFaultPoint point,
  File artifact,
);

enum StoreGarbageCollectionFaultPoint {
  beforeRetire,
  beforeDelete,
}

final class StoreGarbageCollectionFaults {
  const StoreGarbageCollectionFaults(this.callback);

  const StoreGarbageCollectionFaults.none() : callback = null;

  final StoreGarbageCollectionFaultCallback? callback;

  Future<void> check(
    StoreGarbageCollectionFaultPoint point,
    File artifact,
  ) async =>
      callback?.call(point, artifact);
}
