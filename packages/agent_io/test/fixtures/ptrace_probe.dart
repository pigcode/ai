import 'dart:ffi';
import 'dart:io';

void main() {
  final ptrace = DynamicLibrary.process().lookupFunction<
      Int64 Function(Int32, Int32, Pointer<Void>, Pointer<Void>),
      int Function(int, int, Pointer<Void>, Pointer<Void>)>('ptrace');
  final result = ptrace(0, 0, nullptr, nullptr);
  exit(result == -1 ? 77 : 0);
}
