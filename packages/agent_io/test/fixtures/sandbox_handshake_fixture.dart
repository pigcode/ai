import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';

Future<void> main(List<String> arguments) async {
  final mode = arguments.single;
  final setProcessGroup = DynamicLibrary.process()
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
    'setpgid',
  );
  if (setProcessGroup(0, 0) != 0) exit(70);
  stdout.writeln(
    'PIGCODE_CONTROL ${jsonEncode(<String, Object?>{
          'type': 'group-ready',
          'identity': ProcessGroup.captureIdentity(pid),
          'pgid': pid,
        })}',
  );
  final lines = StreamIterator<String>(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  if (!await lines.moveNext().timeout(const Duration(seconds: 3)) ||
      lines.current != 'PIGCODE_ACK group-ready') {
    exit(71);
  }
  if (mode == 'crash-before-ready') exit(72);
  if (mode == 'setup-error') {
    stdout.writeln(
      'PIGCODE_CONTROL ${jsonEncode(<String, Object?>{
            'type': 'error',
            'code': 'capabilityBelowMinimum',
            'rule': 'fixture-sandbox-apply-failed',
          })}',
    );
    exit(73);
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  stdout.writeln(
    'PIGCODE_CONTROL ${jsonEncode(<String, Object?>{
          'type': 'sandbox-ready',
        })}',
  );
  if (!await lines.moveNext().timeout(const Duration(seconds: 3)) ||
      lines.current != 'PIGCODE_ACK sandbox-ready') {
    exit(74);
  }
  if (mode == 'ack-consumed-no-exec') {
    await Future<void>.delayed(const Duration(seconds: 5));
    exit(75);
  }
  stdout.writeln(
    'PIGCODE_CONTROL ${jsonEncode(<String, Object?>{
          'type': 'exec-ready',
          'pid': pid,
        })}',
  );
  await lines.cancel();
}
