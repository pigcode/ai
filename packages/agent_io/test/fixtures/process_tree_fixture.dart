import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--linger')) {
    if (arguments.contains('--detached')) {
      final setsid = DynamicLibrary.process()
          .lookupFunction<Int32 Function(), int Function()>('setsid');
      if (setsid() < 0) exit(70);
      stdout.writeln('DETACHED_READY $pid');
    }
    await Future<void>.delayed(const Duration(hours: 1));
  }
  stdout.writeln('READY $pid');
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (line == 'spawn') {
      final child = await Process.start(
        Platform.resolvedExecutable,
        <String>[Platform.script.toFilePath(), '--linger'],
      );
      child.stdout.drain<void>();
      child.stderr.drain<void>();
      stdout.writeln('CHILD ${child.pid}');
    } else if (line == 'spawn-exit') {
      final child = await Process.start(
        Platform.resolvedExecutable,
        <String>[Platform.script.toFilePath(), '--linger'],
      );
      child.stdout.drain<void>();
      child.stderr.drain<void>();
      stdout.writeln('CHILD ${child.pid}');
      await stdout.flush();
      // Leave the lingering child inside the inherited process group while
      // the fixture (and therefore the group leader chain) exits normally.
      exit(0);
    } else if (line == 'spawn-detached') {
      final child = await Process.start(
        Platform.resolvedExecutable,
        <String>[
          Platform.script.toFilePath(),
          '--linger',
          '--detached',
        ],
      );
      final ready = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5));
      child.stderr.drain<void>();
      if (ready == 'DETACHED_READY ${child.pid}') {
        stdout.writeln('DETACHED ${child.pid}');
      }
    }
  }
}
