import 'dart:io';

void main(List<String> arguments) {
  switch (arguments.single) {
    case 'exit':
      exit(17);
    case 'sigkill':
      Process.killPid(pid, ProcessSignal.sigkill);
    case 'flood':
      stderr.write(List<String>.filled(8192, 'bounded-stderr').join());
      exit(18);
  }
}
