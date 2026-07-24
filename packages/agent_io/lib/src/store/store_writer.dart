import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

typedef StoreWriterFaultCallback = FutureOr<void> Function(
  StoreWriterFaultPoint point,
  File target,
);

enum StoreWriterFaultPoint {
  beforeWrite,
  afterWrite,
  beforeFlush,
  beforePublish,
}

final class StoreWriterFaults {
  const StoreWriterFaults(this.callback);

  const StoreWriterFaults.none() : callback = null;

  final StoreWriterFaultCallback? callback;

  Future<void> check(StoreWriterFaultPoint point, File target) async =>
      callback?.call(point, target);
}

final class StoreWriter {
  StoreWriter({
    this.faults = const StoreWriterFaults.none(),
  });

  final StoreWriterFaults faults;
  final Random _random = Random.secure();

  Future<void> writeImmutable(
    File target,
    Uint8List bytes, {
    required AgentStoreDurability durability,
  }) async {
    if (target.existsSync()) {
      final existing = await target.readAsBytes();
      if (!_bytesEqual(existing, bytes)) {
        throw const AgentStoreException(
          AgentStoreErrorCode.corruption,
          'Content-addressed Store artifact has conflicting bytes.',
        );
      }
      return;
    }
    await target.parent.create(recursive: true);
    final temporary = File(
      '${target.path}.tmp-${_randomHex(16)}',
    );
    RandomAccessFile? handle;
    try {
      await faults.check(StoreWriterFaultPoint.beforeWrite, target);
      handle = await temporary.open(mode: FileMode.write);
      await handle.writeFrom(bytes);
      await faults.check(StoreWriterFaultPoint.afterWrite, target);
      if (durability == AgentStoreDurability.processCrashFlush) {
        await faults.check(StoreWriterFaultPoint.beforeFlush, target);
        await handle.flush();
      }
      await handle.close();
      handle = null;
      await faults.check(StoreWriterFaultPoint.beforePublish, target);
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        if (!target.existsSync()) rethrow;
        final existing = await target.readAsBytes();
        if (!_bytesEqual(existing, bytes)) {
          throw const AgentStoreException(
            AgentStoreErrorCode.corruption,
            'Concurrent immutable artifact has conflicting bytes.',
          );
        }
        if (temporary.existsSync()) await temporary.delete();
      }
      if (durability == AgentStoreDurability.processCrashFlush) {
        final published = await target.open(mode: FileMode.append);
        try {
          await published.flush();
        } finally {
          await published.close();
        }
      }
    } on AgentStoreException {
      rethrow;
    } on Object {
      throw const AgentStoreException(
        AgentStoreErrorCode.ioFailure,
        'Store artifact write or flush failed.',
      );
    } finally {
      if (handle != null) {
        await handle.close();
      }
      if (temporary.existsSync()) {
        await temporary.delete();
      }
    }
  }

  String _randomHex(int byteCount) {
    final output = StringBuffer();
    for (var index = 0; index < byteCount; index++) {
      output.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return output.toString();
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
