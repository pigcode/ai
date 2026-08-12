import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

void main(List<String> arguments) {
  final library = DynamicLibrary.process();
  final getParentPid =
      library.lookupFunction<Int32 Function(), int Function()>('getppid');
  final parentPid = getParentPid();
  stdout.writeln(jsonEncode(<String, Object?>{
    'pid': pid,
    'parentPid': parentPid,
    'parentExecutable': _processPath(library, parentPid),
    'arguments': arguments,
  }));
}

String _processPath(DynamicLibrary library, int processId) {
  final calloc = library.lookupFunction<Pointer<Void> Function(Uint64, Uint64),
      Pointer<Void> Function(int, int)>('calloc');
  final free = library.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('free');
  final procPidPath = library.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Uint32),
      int Function(int, Pointer<Uint8>, int)>('proc_pidpath');
  final buffer = calloc(1024, 1).cast<Uint8>();
  try {
    final length = procPidPath(processId, buffer, 1024);
    return length <= 0
        ? ''
        : utf8.decode(buffer.asTypedList(length), allowMalformed: true);
  } finally {
    free(buffer.cast<Void>());
  }
}
