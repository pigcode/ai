import 'dart:ffi';
import 'dart:io';

void main() {
  final ptrace = DynamicLibrary.process().lookupFunction<
      Int64 Function(Int32, Int32, Pointer<Void>, Pointer<Void>),
      int Function(int, int, Pointer<Void>, Pointer<Void>)>('ptrace');
  final result = ptrace(0, 0, nullptr, nullptr);
  final errno = DynamicLibrary.process()
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
          '__errno_location')()
      .value;
  stdout.writeln('PTRACE_RESULT=$result ERRNO=$errno');
  exit(result == -1 && errno == 1 ? 77 : 78);
}
