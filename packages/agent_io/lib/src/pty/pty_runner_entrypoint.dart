import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../exec/process_group.dart';
import '../sandbox/runner_control.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    exitCode = 64;
    return;
  }
  final command = jsonDecode(utf8.decode(base64Url.decode(arguments.single)))
      as Map<String, Object?>;
  final executable = command['executable']! as String;
  final targetArguments =
      (command['arguments']! as List<Object?>).cast<String>();
  final native = _NativePty(executable, targetArguments);
  final child = native.spawn();
  if (child.pid == 0) {
    native.stopBeforeExec();
  }
  await native.waitUntilStopped(child.pid);
  RunnerControl.report('group-ready', <String, Object?>{
    'identity': ProcessGroup.captureIdentity(child.pid),
    'pgid': child.pid,
  });
  RunnerControl.waitForAck('group-ready');
  native.continueChild(child.pid);
  native.releaseArguments();

  final masterPath = File('/dev/fd/${child.masterFd}');
  final outputDone = masterPath.openRead().pipe(stdout).catchError((_) {});
  final input = masterPath.openWrite();
  unawaited(stdin.pipe(input).catchError((_) {}));
  native.close(child.masterFd);

  final subscriptions = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigterm.watch().listen(
          (_) => native.killProcessGroup(child.pid, ProcessSignal.sigterm),
        ),
    ProcessSignal.sigint.watch().listen(
          (_) => native.killProcessGroup(child.pid, ProcessSignal.sigint),
        ),
  ];
  final status = await native.wait(child.pid);
  await outputDone;
  await input.close();
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
  exitCode = status;
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
        _argv = _nativeArguments(executable, arguments);

  static final DynamicLibrary _library = DynamicLibrary.process();
  final int Function(Pointer<Uint8>, Pointer<Pointer<Uint8>>) _nativeExec =
      _library.lookupFunction<
          Int32 Function(Pointer<Uint8>, Pointer<Pointer<Uint8>>),
          int Function(Pointer<Uint8>, Pointer<Pointer<Uint8>>)>(
    'execvp',
  );
  final void Function(int) _immediateExit = _library
      .lookupFunction<Void Function(Int32), void Function(int)>('_exit');
  final int Function(int) _raise = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('raise');
  final Pointer<Uint8> _executable;
  final Pointer<Pointer<Uint8>> _argv;

  _PtyChild spawn() {
    final master = _calloc(sizeOf<Int32>()).cast<Int32>();
    final forkPty = _library.lookupFunction<
        Int32 Function(
          Pointer<Int32>,
          Pointer<Uint8>,
          Pointer<Void>,
          Pointer<Void>,
        ),
        int Function(
          Pointer<Int32>,
          Pointer<Uint8>,
          Pointer<Void>,
          Pointer<Void>,
        )>('forkpty');
    final pid = forkPty(master, nullptr, nullptr, nullptr);
    if (pid < 0) {
      _free(master);
      releaseArguments();
      exitCode = 70;
      exit(70);
    }
    final masterFd = pid == 0 ? -1 : master.value;
    if (pid != 0) _free(master);
    return _PtyChild(pid: pid, masterFd: masterFd);
  }

  Never stopBeforeExec() {
    if (_raise(Platform.isMacOS ? 17 : 19) != 0) _immediateExit(126);
    _nativeExec(_executable, _argv);
    _immediateExit(127);
    throw StateError('unreachable');
  }

  void continueChild(int pid) {
    final kill = _library.lookupFunction<Int32 Function(Int32, Int32),
        int Function(int, int)>('kill');
    final signal = ProcessSignal.sigcont.signalNumber;
    stderr.writeln('DEBUG_CONT signal=$signal result=${kill(pid, signal)}');
  }

  Future<void> waitUntilStopped(int pid) async {
    final status = _calloc(sizeOf<Int32>()).cast<Int32>();
    final waitPid = _library.lookupFunction<
        Int32 Function(Int32, Pointer<Int32>, Int32),
        int Function(int, Pointer<Int32>, int)>('waitpid');
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    try {
      while (DateTime.now().isBefore(deadline)) {
        final result = waitPid(pid, status, 3);
        stderr.writeln('DEBUG_STOP result=$result status=${status.value}');
        if (result == pid && (status.value & 0xff) == 0x7f) return;
        if (result < 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      exit(70);
    } finally {
      _free(status);
    }
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

  void close(int fd) {
    final close = _library
        .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
    close(fd);
  }

  void releaseArguments() {
    var index = 0;
    while (_argv[index] != nullptr) {
      _free(_argv[index]);
      index += 1;
    }
    _free(_argv);
    _free(_executable);
  }

  static Pointer<Pointer<Uint8>> _nativeArguments(
    String executable,
    List<String> arguments,
  ) {
    final values = <String>[executable, ...arguments];
    final pointer = _calloc((values.length + 1) * sizeOf<Pointer<Void>>())
        .cast<Pointer<Uint8>>();
    for (var index = 0; index < values.length; index += 1) {
      pointer[index] = _nativeString(values[index]);
    }
    pointer[values.length] = nullptr;
    return pointer;
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
