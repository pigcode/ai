import 'dart:ffi';
import 'dart:io';

void main() {
  const rndGetEntropyCount = 0x80045200;
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
  final pathBytes = '/dev/urandom\u0000'.codeUnits;
  final path = calloc(pathBytes.length, 1).cast<Uint8>();
  path.asTypedList(pathBytes.length).setAll(0, pathBytes);
  final fd = open(path, 0);
  free(path.cast<Void>());
  if (fd < 0) {
    exitCode = 79;
    return;
  }
  final output = calloc(1, sizeOf<Int32>());
  final result = ioctl(fd, rndGetEntropyCount, output);
  final errno = errnoLocation().value;
  free(output);
  close(fd);
  if (result == -1 && errno == 1) {
    stdout.writeln('LANDLOCK_IOCTL_DENIED');
    exitCode = 0;
  } else if (result == 0) {
    stdout.writeln('CONTROL_IOCTL_ALLOWED');
    exitCode = 78;
  } else {
    stderr.writeln('UNEXPECTED_IOCTL_RESULT result=$result errno=$errno');
    exitCode = 79;
  }
}
