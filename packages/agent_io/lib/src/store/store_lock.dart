import 'dart:async';
import 'dart:io';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

final class StoreLock {
  StoreLock._(this._handle);

  final RandomAccessFile _handle;
  bool _released = false;

  static Future<StoreLock> acquire(
    File lockFile, {
    required Duration timeout,
  }) async {
    await lockFile.parent.create(recursive: true);
    final handle = await lockFile.open(mode: FileMode.append);
    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        await handle.lock(FileLock.exclusive);
        return StoreLock._(handle);
      } on FileSystemException {
        if (!DateTime.now().isBefore(deadline)) {
          await handle.close();
          throw const AgentStoreException(
            AgentStoreErrorCode.storeBusy,
            'Timed out acquiring the Store advisory lock.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _handle.unlock();
    } finally {
      await _handle.close();
    }
  }
}
