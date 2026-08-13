import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../exec/process_cleanup_ledger.dart';
import '../exec/process_group.dart';
import '../sandbox/runner_control.dart';
import '../sandbox/sandbox_errors.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 2 && arguments.first == '--child') {
    await _runChildGate(arguments.last);
    return;
  }
  if (arguments.length != 2) {
    exitCode = 64;
    return;
  }
  final writeAhead = _decodeWriteAhead(arguments.last);
  _NativePty? native;
  _PtyChild? child;
  try {
    native = _NativePty(
      Platform.resolvedExecutable,
      <String>[
        Platform.script.toFilePath(),
        '--child',
        arguments.first,
      ],
    );
    child = native.spawn();
    native.releaseArguments();
    final activeNative = native;
    final activeChild = child;

    activeNative.validateSpawnedGroup(activeChild.pid);
    final identity = await _captureIdentity(activeChild.pid);
    if (identity == null) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'pty-process-identity-unavailable',
      );
    }
    final record = ProcessCleanupRecord(
      sessionIdentity: writeAhead.sessionIdentity,
      processGroupId: activeChild.pid,
      processIdentity: identity,
    );
    final ledger = ProcessCleanupLedger(writeAhead.ledgerPath);
    try {
      await ledger.record(record);
      final persisted = (await ledger.pending(writeAhead.sessionIdentity))
          .where((current) => current.processGroupId == activeChild.pid)
          .toList(growable: false);
      if (persisted.length != 1 ||
          persisted.single.processIdentity != identity) {
        throw const FileSystemException(
          'PTY cleanup ledger read-after-write mismatch',
        );
      }
    } on Object {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'pty-parent-write-ahead-failed',
      );
    }
    await RunnerControl.report('group-ready', <String, Object?>{
      'brokerPid': pid,
      'identity': identity,
      'pgid': activeChild.pid,
      'source': 'posix-spawn-parent',
    });
    RunnerControl.waitForAck('group-ready');
    activeNative.continueChild(activeChild.pid);

    final masterPath = File('/dev/fd/${activeChild.masterFd}');
    final outputDone = masterPath.openRead().pipe(stdout).catchError((_) {});
    final input = masterPath.openWrite();
    Future<void>? inputClose;
    final inputSubscription = stdin.listen(
      input.add,
      onError: (Object _, StackTrace __) {},
      onDone: () => unawaited(inputClose ??= input.close()),
    );
    final subscriptions = <StreamSubscription<ProcessSignal>>[
      ProcessSignal.sigterm.watch().listen(
            (_) => activeNative.killProcessGroup(
              activeChild.pid,
              ProcessSignal.sigterm,
            ),
          ),
      ProcessSignal.sigint.watch().listen(
            (_) => activeNative.killProcessGroup(
              activeChild.pid,
              ProcessSignal.sigint,
            ),
          ),
    ];
    final status = await activeNative.wait(activeChild.pid);
    await outputDone;
    await inputSubscription.cancel();
    await (inputClose ??= input.close());
    activeNative.close(activeChild.masterFd);
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    exitCode = status;
  } on HostCapabilityException catch (error) {
    final spawnedChild = child;
    final pty = native;
    if (spawnedChild != null && pty != null) {
      pty.killProcessGroup(spawnedChild.pid, ProcessSignal.sigkill);
      await pty.wait(spawnedChild.pid);
      pty.close(spawnedChild.masterFd);
    }
    await RunnerControl.report('error', <String, Object?>{
      'code': error.code.name,
      'rule': error.rule,
    });
    exitCode = 70;
  }
}

_PtyWriteAhead _decodeWriteAhead(String encoded) {
  try {
    final value = jsonDecode(utf8.decode(base64Url.decode(encoded)));
    if (value is! Map<String, Object?>) {
      throw const FormatException('PTY write-ahead must be an object');
    }
    final ledgerPath = value['ledgerPath'];
    final sessionIdentity = value['sessionIdentity'];
    if (ledgerPath is! String ||
        !ledgerPath.startsWith('/') ||
        sessionIdentity is! String ||
        sessionIdentity.isEmpty ||
        sessionIdentity.contains('\u0000')) {
      throw const FormatException('Invalid PTY write-ahead identity');
    }
    return _PtyWriteAhead(
      ledgerPath: ledgerPath,
      sessionIdentity: sessionIdentity,
    );
  } on Object {
    throw const HostCapabilityException(
      HostCapabilityError.processCleanupFailed,
      'pty-parent-write-ahead-config-invalid',
    );
  }
}

Future<void> _runChildGate(String encodedCommand) async {
  try {
    _NativePty.establishControllingTerminal();
    final command = jsonDecode(utf8.decode(base64Url.decode(encodedCommand)))
        as Map<String, Object?>;
    final executable = command['executable']! as String;
    final targetArguments =
        (command['arguments']! as List<Object?>).cast<String>();
    _NativePty(executable, targetArguments).execTarget();
  } on HostCapabilityException catch (error) {
    await RunnerControl.report('error', <String, Object?>{
      'code': error.code.name,
      'rule': error.rule,
    });
    exitCode = 70;
  } on Object {
    await RunnerControl.report('error', const <String, Object?>{
      'code': 'ptyUnavailable',
      'rule': 'pty-child-gate-unexpected-failure',
    });
    exitCode = 70;
  }
}

Future<String?> _captureIdentity(int processId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (true) {
    final identity = ProcessGroup.captureIdentity(processId);
    if (identity != null) return identity;
    if (DateTime.now().isAfter(deadline)) return null;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final class _PtyWriteAhead {
  const _PtyWriteAhead({
    required this.ledgerPath,
    required this.sessionIdentity,
  });

  final String ledgerPath;
  final String sessionIdentity;
}

final class _PtyChild {
  const _PtyChild({
    required this.pid,
    required this.masterFd,
  });

  final int pid;
  final int masterFd;
}

final class _NativePty {
  _NativePty(String executable, List<String> arguments)
      : _executable = _nativeString(executable),
        _argv = _nativeArguments(executable, arguments),
        _environment = _nativeEnvironment();

  static final DynamicLibrary _library = DynamicLibrary.process();
  // Xcode 16.4 SDK: sys/spawn.h POSIX_SPAWN_SETSID.
  static const _darwinPosixSpawnSetsid = 0x0400;
  // Xcode 16.4 SDK: sys/spawn.h POSIX_SPAWN_START_SUSPENDED.
  static const _darwinPosixSpawnStartSuspended = 0x0080;
  // Xcode 16.4 SDK: sys/ttycom.h _IO('t', 97), derived using sys/ioccom.h.
  static const _darwinTiocsctty = 0x20007461;
  // Xcode 16.4 SDK: sys/signal.h SIGCONT.
  static const _darwinSigcont = 19;
  final int Function(Pointer<Uint8>, Pointer<Pointer<Uint8>>) _nativeExec =
      _library.lookupFunction<
          Int32 Function(Pointer<Uint8>, Pointer<Pointer<Uint8>>),
          int Function(Pointer<Uint8>, Pointer<Pointer<Uint8>>)>(
    'execvp',
  );
  final void Function(int) _immediateExit = _library
      .lookupFunction<Void Function(Int32), void Function(int)>('_exit');
  final Pointer<Uint8> _executable;
  final Pointer<Pointer<Uint8>> _argv;
  final Pointer<Pointer<Uint8>> _environment;

  _PtyChild spawn() {
    final master = _calloc(sizeOf<Int32>()).cast<Int32>();
    final slave = _calloc(sizeOf<Int32>()).cast<Int32>();
    final childPid = _calloc(sizeOf<Int32>()).cast<Int32>();
    // Darwin typedefs both spawn handles as void*. Libc initializes the
    // opaque allocations referenced by these pointer-sized slots.
    final fileActions = _calloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    final attributes = _calloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    var fileActionsInitialized = false;
    var attributesInitialized = false;
    var ptyOpened = false;
    var spawned = false;
    try {
      _requireMacOs();
      final openPty = _library.lookupFunction<
          Int32 Function(
            Pointer<Int32>,
            Pointer<Int32>,
            Pointer<Uint8>,
            Pointer<Void>,
            Pointer<Void>,
          ),
          int Function(
            Pointer<Int32>,
            Pointer<Int32>,
            Pointer<Uint8>,
            Pointer<Void>,
            Pointer<Void>,
          )>('openpty');
      if (openPty(master, slave, nullptr, nullptr, nullptr) != 0) {
        throw const HostCapabilityException(
          HostCapabilityError.ptyUnavailable,
          'pty-open-failed',
        );
      }
      ptyOpened = true;

      final fileActionsInit = _library.lookupFunction<
          Int32 Function(Pointer<Pointer<Void>>),
          int Function(Pointer<Pointer<Void>>)>(
        'posix_spawn_file_actions_init',
      );
      if (fileActionsInit(fileActions) != 0) {
        throw const HostCapabilityException(
          HostCapabilityError.ptyUnavailable,
          'pty-spawn-file-actions-init-failed',
        );
      }
      fileActionsInitialized = true;
      for (var targetFd = 0; targetFd <= 2; targetFd += 1) {
        _requireSpawnResult(
          _addDup2(fileActions, slave.value, targetFd),
          'pty-spawn-dup-failed',
        );
      }
      _requireSpawnResult(
        _addClose(fileActions, master.value),
        'pty-spawn-master-close-action-failed',
      );
      _requireSpawnResult(
        _addClose(fileActions, slave.value),
        'pty-spawn-slave-close-action-failed',
      );

      final attrInit = _library.lookupFunction<
          Int32 Function(Pointer<Pointer<Void>>),
          int Function(Pointer<Pointer<Void>>)>(
        'posix_spawnattr_init',
      );
      if (attrInit(attributes) != 0) {
        throw const HostCapabilityException(
          HostCapabilityError.ptyUnavailable,
          'pty-spawn-attributes-init-failed',
        );
      }
      attributesInitialized = true;
      final setFlags = _library.lookupFunction<
          Int32 Function(Pointer<Pointer<Void>>, Int16),
          int Function(Pointer<Pointer<Void>>, int)>(
        'posix_spawnattr_setflags',
      );
      _requireSpawnResult(
        setFlags(
          attributes,
          _darwinPosixSpawnSetsid | _darwinPosixSpawnStartSuspended,
        ),
        'pty-spawn-session-attribute-failed',
      );

      final posixSpawn = _library.lookupFunction<
          Int32 Function(
            Pointer<Int32>,
            Pointer<Uint8>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Uint8>>,
            Pointer<Pointer<Uint8>>,
          ),
          int Function(
            Pointer<Int32>,
            Pointer<Uint8>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Uint8>>,
            Pointer<Pointer<Uint8>>,
          )>('posix_spawn');
      _requireSpawnResult(
        posixSpawn(
          childPid,
          _executable,
          fileActions,
          attributes,
          _argv,
          _environment,
        ),
        'pty-posix-spawn-failed',
      );
      spawned = true;
      return _PtyChild(pid: childPid.value, masterFd: master.value);
    } finally {
      if (attributesInitialized) {
        final destroy = _library.lookupFunction<
            Int32 Function(Pointer<Pointer<Void>>),
            int Function(Pointer<Pointer<Void>>)>(
          'posix_spawnattr_destroy',
        );
        destroy(attributes);
      }
      if (fileActionsInitialized) {
        final destroy = _library.lookupFunction<
            Int32 Function(Pointer<Pointer<Void>>),
            int Function(Pointer<Pointer<Void>>)>(
          'posix_spawn_file_actions_destroy',
        );
        destroy(fileActions);
      }
      if (ptyOpened) {
        close(slave.value);
        if (!spawned) close(master.value);
      }
      _free(attributes);
      _free(fileActions);
      _free(childPid);
      _free(slave);
      _free(master);
      if (!spawned) releaseArguments();
    }
  }

  Never execTarget() {
    _nativeExec(_executable, _argv);
    _immediateExit(126);
    throw StateError('unreachable');
  }

  Future<int> wait(int pid) async {
    final status = _calloc(sizeOf<Int32>()).cast<Int32>();
    try {
      final waitPid = _library.lookupFunction<
          Int32 Function(Int32, Pointer<Int32>, Int32),
          int Function(int, Pointer<Int32>, int)>('waitpid');
      while (true) {
        final result = waitPid(pid, status, 1);
        if (result == pid) {
          final value = status.value;
          final signal = value & 0x7f;
          if (value == 0xffff || signal == 0x7f) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            continue;
          }
          return signal == 0 ? (value >> 8) & 0xff : 128 + signal;
        }
        if (result < 0) return 71;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      _free(status);
    }
  }

  void killProcessGroup(int pid, ProcessSignal signal) {
    final kill = _library.lookupFunction<Int32 Function(Int32, Int32),
        int Function(int, int)>('kill');
    kill(-pid, signal.signalNumber);
  }

  void continueChild(int pid) {
    final kill = _library.lookupFunction<Int32 Function(Int32, Int32),
        int Function(int, int)>('kill');
    if (kill(pid, _darwinSigcont) != 0) {
      throw const HostCapabilityException(
        HostCapabilityError.ptyUnavailable,
        'pty-child-release-failed',
      );
    }
  }

  void validateSpawnedGroup(int pid) {
    final getProcessGroup = _library
        .lookupFunction<Int32 Function(Int32), int Function(int)>('getpgid');
    final getSession = _library
        .lookupFunction<Int32 Function(Int32), int Function(int)>('getsid');
    if (getProcessGroup(pid) != pid || getSession(pid) != pid) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'pty-spawned-group-invariant-failed',
      );
    }
  }

  void close(int fd) {
    final close = _library
        .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
    close(fd);
  }

  void releaseArguments() {
    _freeNativeStrings(_argv);
    _freeNativeStrings(_environment);
    _free(_executable);
  }

  int _addDup2(
    Pointer<Pointer<Void>> fileActions,
    int sourceFd,
    int targetFd,
  ) {
    final addDup2 = _library.lookupFunction<
        Int32 Function(Pointer<Pointer<Void>>, Int32, Int32),
        int Function(Pointer<Pointer<Void>>, int, int)>(
      'posix_spawn_file_actions_adddup2',
    );
    return addDup2(fileActions, sourceFd, targetFd);
  }

  int _addClose(Pointer<Pointer<Void>> fileActions, int fd) {
    final addClose = _library.lookupFunction<
        Int32 Function(Pointer<Pointer<Void>>, Int32),
        int Function(Pointer<Pointer<Void>>, int)>(
      'posix_spawn_file_actions_addclose',
    );
    return addClose(fileActions, fd);
  }

  static void establishControllingTerminal() {
    _requireMacOs();
    final ioctl = _library.lookupFunction<Int32 Function(Int32, Uint64, Int32),
        int Function(int, int, int)>('ioctl');
    if (ioctl(0, _darwinTiocsctty, 0) != 0) {
      throw const HostCapabilityException(
        HostCapabilityError.ptyUnavailable,
        'pty-controlling-terminal-failed',
      );
    }
    final getPid =
        _library.lookupFunction<Int32 Function(), int Function()>('getpid');
    final getProcessGroup =
        _library.lookupFunction<Int32 Function(), int Function()>('getpgrp');
    final getSession = _library
        .lookupFunction<Int32 Function(Int32), int Function(int)>('getsid');
    final getForegroundProcessGroup = _library
        .lookupFunction<Int32 Function(Int32), int Function(int)>('tcgetpgrp');
    final processId = getPid();
    if (getProcessGroup() != processId ||
        getSession(0) != processId ||
        getForegroundProcessGroup(0) != processId) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'pty-session-invariant-failed',
      );
    }
  }

  static void _requireMacOs() {
    if (!Platform.isMacOS) {
      throw const HostCapabilityException(
        HostCapabilityError.ptyUnavailable,
        'pty-posix-spawn-platform-unsupported',
      );
    }
  }

  static void _requireSpawnResult(int result, String rule) {
    if (result != 0) {
      throw HostCapabilityException(
        HostCapabilityError.ptyUnavailable,
        rule,
      );
    }
  }

  static Pointer<Pointer<Uint8>> _nativeArguments(
    String executable,
    List<String> arguments,
  ) {
    final values = <String>[executable, ...arguments];
    return _nativeStrings(values);
  }

  static Pointer<Pointer<Uint8>> _nativeEnvironment() {
    final values = Platform.environment.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .toList(growable: false);
    return _nativeStrings(values);
  }

  static Pointer<Pointer<Uint8>> _nativeStrings(List<String> values) {
    final pointer = _calloc((values.length + 1) * sizeOf<Pointer<Void>>())
        .cast<Pointer<Uint8>>();
    for (var index = 0; index < values.length; index += 1) {
      pointer[index] = _nativeString(values[index]);
    }
    pointer[values.length] = nullptr;
    return pointer;
  }

  static void _freeNativeStrings(Pointer<Pointer<Uint8>> pointer) {
    var index = 0;
    while (pointer[index] != nullptr) {
      _free(pointer[index]);
      index += 1;
    }
    _free(pointer);
  }

  static Pointer<Uint8> _nativeString(String value) {
    final bytes = <int>[...utf8.encode(value), 0];
    final pointer = _calloc(bytes.length).cast<Uint8>();
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  static Pointer<Void> _calloc(int size) {
    final calloc = _library.lookupFunction<
        Pointer<Void> Function(Uint64, Uint64),
        Pointer<Void> Function(int, int)>('calloc');
    final pointer = calloc(size, 1);
    if (pointer == nullptr) exit(70);
    return pointer;
  }

  static void _free(Pointer<NativeType> pointer) {
    final free = _library.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('free');
    free(pointer.cast<Void>());
  }
}
