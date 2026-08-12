import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

void main() {
  test('P4-TM-PATH-01 Host rejects traversal, encoded, and absolute paths', () {
    final root = Directory.systemTemp.createTempSync('pigcode_path_');
    try {
      final fs = HostWorkspaceFileSystem(<HostWorkspaceRoot>[
        HostWorkspaceRoot(
          name: 'workspace',
          path: root.path,
          access: SandboxPathAccess.readWrite,
        ),
      ]);
      for (final path in <String>[
        '../outside',
        '%2e%2e/outside',
        '/tmp/outside',
      ]) {
        expect(
          () => fs.readText('workspace', path),
          throwsA(isA<HostCapabilityException>()),
        );
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('P4-TM-PATH-04 Host rejects writes to a read-only root', () {
    final root = Directory.systemTemp.createTempSync('pigcode_path_');
    try {
      final fs = HostWorkspaceFileSystem(<HostWorkspaceRoot>[
        HostWorkspaceRoot(
          name: 'workspace',
          path: root.path,
          access: SandboxPathAccess.readOnly,
        ),
      ]);
      expect(
        () => fs.writeText('workspace', 'denied.txt', 'denied'),
        throwsA(
          isA<HostCapabilityException>().having(
            (error) => error.code,
            'code',
            HostCapabilityError.pathDenied,
          ),
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('P4-TM-PATH-05 unknown root fails closed', () {
    final fs = HostWorkspaceFileSystem(const <HostWorkspaceRoot>[]);
    expect(
      () => fs.readText('missing', 'file.txt'),
      throwsA(isA<HostCapabilityException>()),
    );
  });

  test(
    'P4-TM-DLP-04 Seatbelt kernel rejects roots-outside write with Host bypassed',
    () async {
      final temp = Directory.systemTemp.createTempSync('pigcode_dlp_');
      try {
        final root = Directory('${temp.path}/root')..createSync();
        final outside = '${temp.path}/outside';
        final process = await SeatbeltSandboxBackend(
          unsafeStandaloneStart: true,
        ).start(
          SandboxPolicy(
            roots: <SandboxPathRule>[
              SandboxPathRule(
                path: root.path,
                access: SandboxPathAccess.readWrite,
              ),
            ],
          ),
          HostCommand(
            executable: '/bin/sh',
            arguments: <String>[
              '-c',
              'printf denied > "\$1"',
              'fixture',
              outside,
            ],
          ),
        );
        process.stdout.drain<void>();
        final errors = utf8.decoder.bind(process.stderr).join();
        expect(
          await process.exitCode.timeout(const Duration(seconds: 5)),
          isNot(0),
        );
        expect(await errors, contains('Operation not permitted'));
        expect(File(outside).existsSync(), isFalse);
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
    skip: Platform.isMacOS
        ? false
        : 'SKIP-MANIFEST PATH-05 platform=${Platform.operatingSystem} '
            'backend=seatbelt-required',
  );
}
