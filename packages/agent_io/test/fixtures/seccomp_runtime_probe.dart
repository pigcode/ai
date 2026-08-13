import 'dart:ffi';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_io/src/sandbox/landlock/seccomp_policy.dart';

Future<void> main() async {
  final library = DynamicLibrary.process();
  final socket = library.lookupFunction<Int32 Function(Int32, Int32, Int32),
      int Function(int, int, int)>('socket');
  final socketPair = library.lookupFunction<
      Int32 Function(Int32, Int32, Int32, Pointer<Int32>),
      int Function(int, int, int, Pointer<Int32>)>('socketpair');
  final ptrace = library.lookupFunction<
      Int64 Function(Int32, Int32, Pointer<Void>, Pointer<Void>),
      int Function(int, int, Pointer<Void>, Pointer<Void>)>('ptrace');
  final close =
      library.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  final calloc = library.lookupFunction<Pointer<Void> Function(Uint64, Uint64),
      Pointer<Void> Function(int, int)>('calloc');
  final free = library.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('free');
  final errnoLocation = library.lookupFunction<Pointer<Int32> Function(),
      Pointer<Int32> Function()>('__errno_location');

  SeccompFfi().apply();

  final pair = calloc(2, sizeOf<Int32>()).cast<Int32>();
  if (pair == nullptr) exit(70);
  try {
    final pairResult = socketPair(
      SeccompPolicy.addressFamilyUnix,
      SeccompPolicy.socketStream | SeccompPolicy.socketCloexec,
      0,
      pair,
    );
    if (pairResult != 0) exit(71);
    close(pair[0]);
    close(pair[1]);

    final stream = socket(
      SeccompPolicy.addressFamilyInet,
      SeccompPolicy.socketStream |
          SeccompPolicy.socketNonblock |
          SeccompPolicy.socketCloexec,
      0,
    );
    if (stream < 0) exit(72);
    close(stream);

    _expectPermissionDenied(
      socket(
        SeccompPolicy.addressFamilyInet,
        SeccompPolicy.socketDatagram,
        0,
      ),
      errnoLocation,
      73,
    );
    _expectPermissionDenied(
      socket(
        SeccompPolicy.addressFamilyUnix,
        SeccompPolicy.socketStream,
        0,
      ),
      errnoLocation,
      74,
    );
    _expectPermissionDenied(
      ptrace(0, 0, nullptr, nullptr),
      errnoLocation,
      75,
    );

    await Future<void>.delayed(Duration.zero);
    stdout.writeln('SECCOMP_RUNTIME_IPC_REACHED');
    await stdout.flush();
  } finally {
    free(pair.cast<Void>());
  }
}

void _expectPermissionDenied(
  int result,
  Pointer<Int32> Function() errnoLocation,
  int failureExitCode,
) {
  if (result != -1 || errnoLocation().value != 1) {
    exit(failureExitCode);
  }
}
