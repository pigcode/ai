import 'dart:async';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    exitCode = 64;
    return;
  }
  final mode = arguments[0];
  final marker = File(arguments[1]);
  switch (mode) {
    case 'write':
      marker.writeAsStringSync('sandboxed\n');
    case 'fail':
      stderr.writeln('typed-tool-failure');
      exitCode = 17;
    case 'hang':
      marker.writeAsStringSync('$pid\n');
      stdout.writeln('READY');
      await Completer<void>().future;
    default:
      exitCode = 64;
  }
}
