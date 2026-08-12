import 'dart:ffi';
import 'dart:io';

void main() {
  final library = DynamicLibrary.process();
  final open = library.lookupFunction<Int32 Function(Pointer<Uint8>, Int32),
      int Function(Pointer<Uint8>, int)>('open');
  final ioctl = library.lookupFunction<
      Int32 Function(Int32, Uint64, Pointer<Void>),
      int Function(int, int, Pointer<Void>)>('ioctl');
  final errnoLocation = library.lookupFunction<Pointer<Int32> Function(),
      Pointer<Int32> Function()>('__errno_location');
  final calloc = library.lookupFunction<Pointer<Void> Function(Uint64, Uint64),
      Pointer<Void> Function(int, int)>('calloc');
  final free = library.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('free');
  final close =
      library.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  final path = calloc(10, 1).cast<Uint8>();
  path.asTypedList(10).setAll(0, '/dev/null\u0000'.codeUnits);
  final fd = open(path, 0);
  free(path.cast<Void>());
  if (fd < 0) {
    exitCode = 79;
    return;
  }
  final output = calloc(32, 1);
  final result = ioctl(fd, 0x5413, output);
  final errno = errnoLocation().value;
  free(output);
  close(fd);
  exitCode = result == -1 && errno == 1 ? 0 : 78;
}
