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
  final getProcessGroup = DynamicLibrary.process()
      .lookupFunction<Int32 Function(), int Function()>('getpgrp');
  if (setProcessGroup(0, 0) != 0 && getProcessGroup() != pid) exit(70);
  stdout.writeln(
    'PIGCODE_CONTROL ${jsonEncode(<String, Object?>{
          'type': 'group-ready',
          'identity': mode == 'identity-mismatch'
              ? 'fixture-invalid-identity'
              : ProcessGroup.captureIdentity(pid),
          'pgid': pid,
        })}',
  );
  await stdout.flush();
  final lines = StreamIterator<String>(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  if (!await lines.moveNext().timeout(const Duration(seconds: 10)) ||
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
    await stdout.flush();
    exit(73);
  }
  stdout.writeln(
    'PIGCODE_CONTROL ${jsonEncode(<String, Object?>{
          'type': 'sandbox-ready',
        })}',
  );
  await stdout.flush();
  if (!await lines.moveNext().timeout(const Duration(seconds: 10)) ||
      lines.current != 'PIGCODE_ACK sandbox-ready') {
    exit(74);
  }
  if (mode == 'ack-consumed-no-exec') exit(75);
  stdout.writeln(
    'PIGCODE_CONTROL ${jsonEncode(<String, Object?>{
          'type': 'exec-ready',
          'pid': pid,
        })}',
  );
  await stdout.flush();
  await lines.cancel();
}
