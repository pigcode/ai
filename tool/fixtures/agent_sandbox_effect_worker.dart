import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    exitCode = 64;
    return;
  }
  final root = Directory(arguments.single);
  stdout.writeln('WORKER_READY');
  await stdout.flush();
  await for (final command
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (command == 'EXECUTE') {
      final counter = File('${root.path}/side-effect-count.txt');
      final current =
          counter.existsSync() ? int.parse(counter.readAsStringSync()) : 0;
      await counter.writeAsString('${current + 1}', flush: true);
      await File('${root.path}/worker-state.json').writeAsString(
        jsonEncode(<String, Object?>{'phase': 'started', 'workerPid': pid}),
        flush: true,
      );
      stdout.writeln('EFFECT_STARTED');
      await stdout.flush();
    } else if (command == 'FINISH') {
      await File('${root.path}/worker-state.json').writeAsString(
        jsonEncode(<String, Object?>{'phase': 'completed', 'workerPid': pid}),
        flush: true,
      );
      stdout.writeln('EFFECT_COMPLETED');
      await stdout.flush();
    }
  }
}
