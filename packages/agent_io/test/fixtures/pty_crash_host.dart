import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_io/src/sandbox/sandbox_startup_handshake.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) exit(64);
  final launcher = SandboxedProcessLauncher(
    SeatbeltSandboxBackend(),
    hostDataDirectory: arguments[0],
    sessionIdentity: 'pty-crash-window',
    startupObserver: (phase, evidence) async {
      if (phase == SandboxStartupPhase.processGroupPersistedBeforeAck) {
        stdout.writeln(jsonEncode(<String, Object?>{
          'phase': phase.name,
          'pgid': evidence['pgid'],
        }));
        await stdout.flush();
        await Completer<void>().future;
      }
    },
  );
  await HostPtySession(launcher).start(
    SandboxPolicy(
      roots: <SandboxPathRule>[
        SandboxPathRule(
          path: arguments[1],
          access: SandboxPathAccess.readWrite,
        ),
      ],
      requiresPty: true,
    ),
    HostCommand(
      executable: '/usr/bin/touch',
      arguments: <String>['${arguments[1]}/released'],
      workingDirectory: arguments[1],
    ),
  );
}
