import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../sandbox/runner_control.dart';
import '../sandbox/sandbox_errors.dart';
import 'process_group.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    exitCode = 64;
    return;
  }
  final command = jsonDecode(utf8.decode(base64Url.decode(arguments.single)))
      as Map<String, Object?>;
  final setProcessGroup = DynamicLibrary.process()
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
          'setpgid');
  if (setProcessGroup(0, 0) != 0) {
    exitCode = 70;
    return;
  }
  final handshake = command['handshake'] == true;
  try {
    if (handshake) {
      await RunnerControl.report('group-ready', <String, Object?>{
        'identity': ProcessGroup.captureIdentity(pid),
        'pgid': pid,
      });
      RunnerControl.waitForAck('group-ready');
    }
    final child = await Process.start(
      command['executable']! as String,
      (command['arguments']! as List<Object?>).cast<String>(),
      runInShell: false,
    );
    final output = child.stdout.pipe(stdout);
    final errors = child.stderr.pipe(stderr);
    unawaited(stdin.pipe(child.stdin).catchError((_) {}));
    final result = await child.exitCode;
    await Future.wait<void>(<Future<void>>[output, errors]);
    exitCode = result;
  } on HostCapabilityException catch (error) {
    if (handshake) {
      await RunnerControl.report('error', <String, Object?>{
        'code': error.code.name,
        'rule': error.rule,
      });
    }
    exitCode = 70;
  } on ProcessException {
    if (handshake) {
      await RunnerControl.report('error', const <String, Object?>{
        'code': 'sandboxUnavailable',
        'rule': 'sandbox-wrapper-start-failed',
      });
    }
    exitCode = 70;
  }
}
