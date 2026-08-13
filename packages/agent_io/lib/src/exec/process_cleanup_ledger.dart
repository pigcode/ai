import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

final class ProcessCleanupRecord {
  const ProcessCleanupRecord({
    required this.sessionIdentity,
    required this.processGroupId,
    required this.processIdentity,
  });

  final String sessionIdentity;
  final int processGroupId;
  final String processIdentity;

  Map<String, Object?> toJson() => <String, Object?>{
        'processGroupId': processGroupId,
        'processIdentity': processIdentity,
        'sessionIdentity': sessionIdentity,
      };
}

final class ProcessCleanupLedger {
  ProcessCleanupLedger(this.path);

  final String path;

  Future<List<ProcessCleanupRecord>> pending(String sessionIdentity) async =>
      (await all())
          .where((record) => record.sessionIdentity == sessionIdentity)
          .toList(growable: false);

  Future<List<ProcessCleanupRecord>> all() => _transaction(
        (records) => List<ProcessCleanupRecord>.unmodifiable(records),
        write: false,
      );

  Future<void> record(ProcessCleanupRecord record) => _transaction(
        (records) {
          records.removeWhere(
            (current) =>
                current.sessionIdentity == record.sessionIdentity &&
                current.processGroupId == record.processGroupId,
          );
          records.add(record);
        },
      );

  Future<void> confirm(ProcessCleanupRecord record) => _transaction(
        (records) {
          records.removeWhere(
            (current) =>
                current.sessionIdentity == record.sessionIdentity &&
                current.processGroupId == record.processGroupId &&
                current.processIdentity == record.processIdentity,
          );
        },
      );

  Future<T> _transaction<T>(
    T Function(List<ProcessCleanupRecord> records) action, {
    bool write = true,
  }) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final guard = await _acquireGuard();
    final lock = await File('$path.lock').open(mode: FileMode.append);
    try {
      await _lockExclusive(lock);
      final records = await _readUnlocked();
      final result = action(records);
      if (write) await _writeUnlocked(records);
      return result;
    } finally {
      try {
        await lock.unlock();
      } on FileSystemException {
        // The descriptor may not have acquired a lock after an earlier failure.
      }
      await lock.close();
      if (await guard.exists()) await guard.delete(recursive: true);
    }
  }

  Future<File> _acquireGuard() async {
    final guard = File('$path.lock.guard');
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (true) {
      try {
        await guard.create(exclusive: true);
        await guard.writeAsString(
          '$pid ${DateTime.now().microsecondsSinceEpoch}',
          flush: true,
        );
        return guard;
      } on FileSystemException {
        if (await _removeAbandonedGuard(guard)) continue;
        if (DateTime.now().isAfter(deadline)) {
          throw const FileSystemException(
            'cleanup ledger transaction lock timeout',
          );
        }
        await Future<void>.delayed(
          Duration(milliseconds: 2 + Random.secure().nextInt(8)),
        );
      }
    }
  }

  Future<bool> _removeAbandonedGuard(File guard) async {
    try {
      final contents = await guard.readAsString();
      final owner = int.tryParse(contents.split(' ').first);
      if (owner == null || _processExists(owner)) return false;
      await guard.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  bool _processExists(int processId) {
    final kill = DynamicLibrary.process()
        .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'kill');
    return kill(processId, 0) == 0;
  }

  Future<void> _lockExclusive(RandomAccessFile lock) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (true) {
      try {
        await lock.lock(FileLock.exclusive);
        return;
      } on FileSystemException {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 2 + Random.secure().nextInt(8)),
        );
      }
    }
  }

  Future<List<ProcessCleanupRecord>> _readUnlocked() async {
    final file = File(path);
    if (!await file.exists()) return <ProcessCleanupRecord>[];
    final value = jsonDecode(await file.readAsString()) as List<Object?>;
    return value
        .cast<Map<String, Object?>>()
        .map(
          (json) => ProcessCleanupRecord(
            sessionIdentity: json['sessionIdentity']! as String,
            processGroupId: json['processGroupId']! as int,
            processIdentity: json['processIdentity']! as String,
          ),
        )
        .toList();
  }

  Future<void> _writeUnlocked(List<ProcessCleanupRecord> records) async {
    final file = File(path);
    if (records.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    final temporary = File(
      '$path.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}.'
      '${Random.secure().nextInt(1 << 32)}',
    );
    try {
      final output = await temporary.open(mode: FileMode.writeOnly);
      try {
        await output.writeString(
          jsonEncode(records.map((record) => record.toJson()).toList()),
        );
        await output.flush();
      } finally {
        await output.close();
      }
      await temporary.rename(path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
