import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import '../sandbox/sandbox_errors.dart';

final class ProcessTreeCleanupReport {
  const ProcessTreeCleanupReport({
    required this.processGroupId,
    required this.confirmed,
    required this.forced,
  });

  final int processGroupId;
  final bool confirmed;
  final bool forced;
}

final class ProcessGroup {
  ProcessGroup(this.id);

  final int id;

  static String? captureIdentity(int processId) {
    if (Platform.isLinux) {
      try {
        final stat = File('/proc/$processId/stat').readAsStringSync();
        final close = stat.lastIndexOf(')');
        return stat.substring(close + 2).split(' ')[19];
      } on Object {
        return null;
      }
    }
    if (Platform.isMacOS) {
      final library = DynamicLibrary.process();
      final pidInfo = library.lookupFunction<
          Int32 Function(Int32, Int32, Uint64, Pointer<Void>, Int32),
          int Function(int, int, int, Pointer<Void>, int)>('proc_pidinfo');
      final calloc = library.lookupFunction<
          Pointer<Void> Function(Uint64, Uint64),
          Pointer<Void> Function(int, int)>('calloc');
      final free = library.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('free');
      final info = calloc(1, 256).cast<Uint8>();
      if (info == nullptr) return null;
      try {
        if (pidInfo(processId, 3, 0, info.cast<Void>(), 256) < 136) {
          return null;
        }
        final bytes = info.asTypedList(256).buffer.asByteData();
        return '${bytes.getUint64(120, Endian.host)}:'
            '${bytes.getUint64(128, Endian.host)}';
      } finally {
        free(info.cast<Void>());
      }
    }
    return null;
  }

  Future<void> waitUntilEstablished({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!_exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw const HostCapabilityException(
          HostCapabilityError.processCleanupFailed,
          'process-group-not-established',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<ProcessTreeCleanupReport> cleanup({
    Duration gracefulTimeout = const Duration(milliseconds: 500),
  }) async {
    final descendants = _snapshotDescendants();
    if (!_exists() && descendants.isEmpty) {
      return ProcessTreeCleanupReport(
        processGroupId: id,
        confirmed: true,
        forced: false,
      );
    }
    _signal(15);
    for (final process in descendants) {
      process.signal(15);
    }
    final deadline = DateTime.now().add(gracefulTimeout);
    while ((_exists() || descendants.any((process) => process.exists)) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    var forced = false;
    if (_exists() || descendants.any((process) => process.exists)) {
      forced = true;
      _signal(9);
      for (final process in descendants) {
        process.signal(9);
      }
      final hardDeadline = DateTime.now().add(const Duration(seconds: 2));
      while ((_exists() || descendants.any((process) => process.exists)) &&
          DateTime.now().isBefore(hardDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    final confirmed =
        !_exists() && descendants.every((process) => !process.exists);
    if (!confirmed) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'process-group-still-running',
      );
    }
    return ProcessTreeCleanupReport(
      processGroupId: id,
      confirmed: true,
      forced: forced,
    );
  }

  bool _exists() => _kill(-id, 0) == 0;

  void _signal(int signal) {
    _kill(-id, signal);
  }

  List<_ProcessIdentity> _snapshotDescendants() {
    final processes = Platform.isLinux
        ? _linuxProcesses()
        : Platform.isMacOS
            ? _macProcesses()
            : const <_ProcessIdentity>[];
    final descendants = <_ProcessIdentity>[];
    final parents = <int>{id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final process in processes) {
        if (parents.contains(process.parentId) && parents.add(process.id)) {
          descendants.add(process);
          changed = true;
        }
      }
    }
    return descendants;
  }

  List<_ProcessIdentity> _linuxProcesses() {
    final result = <_ProcessIdentity>[];
    for (final entity in Directory('/proc').listSync()) {
      final processId = int.tryParse(
          entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last);
      if (processId == null) continue;
      try {
        final stat = File('/proc/$processId/stat').readAsStringSync();
        final close = stat.lastIndexOf(')');
        final fields = stat.substring(close + 2).split(' ');
        result.add(
          _ProcessIdentity(
            processId,
            int.parse(fields[1]),
            fields[19],
            () {
              final current = File('/proc/$processId/stat').readAsStringSync();
              final currentClose = current.lastIndexOf(')');
              return current.substring(currentClose + 2).split(' ')[19];
            },
          ),
        );
      } on Object {
        continue;
      }
    }
    return result;
  }

  List<_ProcessIdentity> _macProcesses() {
    final library = DynamicLibrary.process();
    final listAll = library.lookupFunction<
        Int32 Function(Pointer<Int32>, Int32),
        int Function(Pointer<Int32>, int)>('proc_listallpids');
    final pidInfo = library.lookupFunction<
        Int32 Function(Int32, Int32, Uint64, Pointer<Void>, Int32),
        int Function(int, int, int, Pointer<Void>, int)>('proc_pidinfo');
    final calloc = library.lookupFunction<
        Pointer<Void> Function(Uint64, Uint64),
        Pointer<Void> Function(int, int)>('calloc');
    final free = library.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('free');
    final capacity = listAll(nullptr, 0) + 64;
    final pids = calloc(capacity, sizeOf<Int32>()).cast<Int32>();
    final info = calloc(1, 256).cast<Uint8>();
    final result = <_ProcessIdentity>[];
    try {
      final count = listAll(pids, capacity * sizeOf<Int32>());
      for (var index = 0; index < count; index += 1) {
        final processId = pids[index];
        if (processId <= 0 ||
            pidInfo(processId, 3, 0, info.cast<Void>(), 256) < 136) {
          continue;
        }
        final bytes = info.asTypedList(256).buffer.asByteData();
        final parentId = bytes.getUint32(16, Endian.host);
        final startSeconds = bytes.getUint64(120, Endian.host);
        final startMicros = bytes.getUint64(128, Endian.host);
        final token = '$startSeconds:$startMicros';
        result.add(
          _ProcessIdentity(processId, parentId, token, () {
            final current = calloc(1, 256).cast<Uint8>();
            try {
              if (pidInfo(
                    processId,
                    3,
                    0,
                    current.cast<Void>(),
                    256,
                  ) <
                  136) {
                return '';
              }
              final currentBytes = current.asTypedList(256).buffer.asByteData();
              return '${currentBytes.getUint64(120, Endian.host)}:'
                  '${currentBytes.getUint64(128, Endian.host)}';
            } finally {
              free(current.cast<Void>());
            }
          }),
        );
      }
    } finally {
      free(info.cast<Void>());
      free(pids.cast<Void>());
    }
    return result;
  }

  static int _kill(int pid, int signal) {
    final kill = DynamicLibrary.process()
        .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'kill');
    return kill(pid, signal);
  }
}

final class _ProcessIdentity {
  const _ProcessIdentity(
    this.id,
    this.parentId,
    this.startToken,
    this._currentStartToken,
  );

  final int id;
  final int parentId;
  final String startToken;
  final String Function() _currentStartToken;

  bool get exists {
    try {
      return _currentStartToken() == startToken &&
          ProcessGroup._kill(id, 0) == 0;
    } on Object {
      return false;
    }
  }

  void signal(int signal) {
    if (exists) ProcessGroup._kill(id, signal);
  }
}
