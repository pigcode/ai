import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

const _deadline = Duration(seconds: 8);

void main() {
  final skip = !Platform.isMacOS || !File('/usr/bin/sandbox-exec').existsSync();

  test(
    'P4-TM-PATH-01 Seatbelt rejects a real read outside declared roots',
    () async {
      await _withRoots((roots) async {
        final outsideFile = File('${roots.outside.path}/secret.txt')
          ..writeAsStringSync('kernel-denied-marker');
        final result = await _run(
          roots,
          HostCommand(
            executable: '/bin/cat',
            arguments: <String>[outsideFile.path],
          ),
        );

        expect(result.exitCode, isNot(0));
        expect(result.stdout, isNot(contains('kernel-denied-marker')));
        expect(result.stderr, contains('Operation not permitted'));
      });
    },
    skip: skip,
  );

  test(
    'P4-TM-PATH-04 Seatbelt rejects a real write to a read-only root',
    () async {
      await _withRoots((roots) async {
        final target = '${roots.readOnly.path}/forbidden.txt';
        final result = await _run(
          roots,
          HostCommand(
            executable: '/bin/sh',
            arguments: <String>[
              '-c',
              'printf denied > "\$1"',
              'pigcode-seatbelt-test',
              target,
            ],
          ),
        );

        expect(result.exitCode, isNot(0));
        expect(File(target).existsSync(), isFalse);
        expect(result.stderr, contains('Operation not permitted'));
      });
    },
    skip: skip,
  );

  test(
    'P4-TM-DLP-01 Seatbelt rejects a real non-allowlisted TCP connection',
    () async {
      await _withRoots((roots) async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        try {
          final acceptedDenied = expectLater(
            server.first.timeout(const Duration(milliseconds: 750)),
            throwsA(isA<TimeoutException>()),
          );
          final result = await _run(
            roots,
            HostCommand(
              executable: '/usr/bin/nc',
              arguments: <String>[
                '-G',
                '1',
                '-z',
                InternetAddress.loopbackIPv4.address,
                '${server.port}',
              ],
            ),
          );

          expect(result.exitCode, isNot(0));
          await acceptedDenied;
        } finally {
          await server.close();
        }
      });
    },
    skip: skip,
  );
}

Future<_ProcessResult> _run(_Roots roots, HostCommand command) async {
  final process = await SeatbeltSandboxBackend(
    unsafeStandaloneStart: true,
  ).start(
    SandboxPolicy(
      roots: <SandboxPathRule>[
        SandboxPathRule(
          path: roots.readOnly.path,
          access: SandboxPathAccess.readOnly,
        ),
        SandboxPathRule(
          path: roots.readWrite.path,
          access: SandboxPathAccess.readWrite,
        ),
      ],
    ),
    command,
  );
  final stdoutFuture = utf8.decoder.bind(process.stdout).join();
  final stderrFuture = utf8.decoder.bind(process.stderr).join();
  try {
    final exitCode = await process.exitCode.timeout(_deadline);
    return (
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
    );
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(const Duration(seconds: 2));
    rethrow;
  }
}

Future<void> _withRoots(Future<void> Function(_Roots roots) body) async {
  final temp = Directory.systemTemp.createTempSync('pigcode_seatbelt_');
  final roots = (
    readOnly: Directory('${temp.path}/read-only')..createSync(),
    readWrite: Directory('${temp.path}/read-write')..createSync(),
    outside: Directory('${temp.path}/outside')..createSync(),
  );
  try {
    await body(roots).timeout(_deadline);
  } finally {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  }
}

typedef _Roots = ({
  Directory readOnly,
  Directory readWrite,
  Directory outside,
});
typedef _ProcessResult = ({int exitCode, String stdout, String stderr});
