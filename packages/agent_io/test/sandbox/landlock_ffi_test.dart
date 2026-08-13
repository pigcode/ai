import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

void main() {
  test('Landlock ABI maps exactly to capability switches', () {
    for (var abi = 1; abi <= 6; abi += 1) {
      final features = LandlockFeatures.fromAbi(abi);
      expect(features.fileSystem, isTrue);
      expect(features.tcpNetwork, abi >= 4);
      expect(features.deviceIoctl, abi >= 5);
    }
  });

  test('Landlock errno maps to a typed safe error', () {
    final error = LandlockFailure.fromErrno(95, operation: 'create-ruleset');

    expect(error.code, HostCapabilityError.sandboxUnavailable);
    expect(error.rule, 'landlock-create-ruleset-errno-95');
    expect(error.toString(), isNot(contains('secret')));
    final missingRuntime = LandlockFailure.fromErrno(
      2,
      operation: 'open-runtime-dependency',
    );
    expect(missingRuntime.code, HostCapabilityError.sandboxUnavailable);
    expect(
      missingRuntime.rule,
      'landlock-open-runtime-dependency-errno-2',
    );
    for (final category in const <String>[
      'directory',
      'file',
      'runtime-dependency',
    ]) {
      final categorized = LandlockFailure.fromErrno(
        22,
        operation: 'add-$category-rule',
      );
      expect(categorized.rule, 'landlock-add-$category-rule-errno-22');
      expect(categorized.rule, isNot(contains('/')));
    }
  });

  test('Linux statx ABI layout stays at exactly 256 bytes', () {
    final actualSize = LandlockFfi.linuxStatxStructSize;
    if (actualSize == LandlockFfi.linuxStatxExpectedSize) {
      expect(LandlockFfi.validateLinuxStatxLayout, returnsNormally);
    } else {
      expect(
        LandlockFfi.validateLinuxStatxLayout,
        throwsA(
          isA<HostCapabilityException>()
              .having(
                (error) => error.code,
                'code',
                HostCapabilityError.pathDenied,
              )
              .having(
                (error) => error.rule,
                'rule',
                'landlock-statx-layout-invalid',
              ),
        ),
      );
    }

    expect(actualSize, 256);
    expect(LandlockFfi.linuxStatxTailOffset, 144);
    expect(LandlockFfi.linuxStatxTailWordCount, 14);
    expect(LandlockFfi.linuxStatxTailEnd, 256);
  });

  test('native Landlock ABI probe is absent off Linux', () {
    final abi = LandlockFfi().probeAbi();
    if (SandboxPlatform.current == SandboxPlatform.linuxX64 ||
        SandboxPlatform.current == SandboxPlatform.linuxArm64) {
      print('LANDLOCK_ABI=${abi ?? 'missing'}');
      return;
    }
    expect(abi, isNull);
  });

  test('native paths use UTF-8 without UTF-16 low-byte truncation', () {
    const path = '/tmp/\u0100\u012f/root';
    final encoded = LandlockFfi.encodeNativePath(path);

    expect(encoded.sublist(0, encoded.length - 1), utf8.encode(path));
    expect(encoded.last, 0);
    expect(encoded.take(encoded.length - 1), isNot(contains(0)));
  });

  test('native path encoding rejects embedded NUL', () {
    expect(
      () => LandlockFfi.encodeNativePath('/tmp/a\u0000/root'),
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.code,
          'code',
          HostCapabilityError.pathDenied,
        ),
      ),
    );
  });

  test('Landlock rejects nested read-only and deny-read policy', () async {
    final root = await Directory.systemTemp.createTemp('landlock-overlap-');
    final git = await Directory('${root.path}/.git').create();
    final ssh = await Directory('${root.path}/.ssh').create();
    try {
      final nested = SandboxPolicy(
        roots: <SandboxPathRule>[
          SandboxPathRule(
            path: root.path,
            access: SandboxPathAccess.readWrite,
          ),
          SandboxPathRule(
            path: git.path,
            access: SandboxPathAccess.readOnly,
          ),
        ],
      );
      final denied = SandboxPolicy(
        roots: <SandboxPathRule>[
          SandboxPathRule(
            path: root.path,
            access: SandboxPathAccess.readWrite,
          ),
        ],
        denyReadPaths: <String>[ssh.path],
      );

      expect(
        () => LandlockFfi.validatePolicyExpressibility(nested),
        throwsA(isA<HostCapabilityException>()),
      );
      expect(
        () => LandlockFfi.validatePolicyExpressibility(denied),
        throwsA(isA<HostCapabilityException>()),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('Landlock rejects relative, dot, dot-dot, and symlink aliases',
      () async {
    final root = await Directory.systemTemp.createTemp('landlock-alias-');
    final child = await Directory('${root.path}/child').create();
    final alias = Link('${root.path}-alias');
    await alias.create(root.path);
    try {
      for (final paths in <List<String>>[
        <String>['relative/path'],
        <String>[root.path, '${root.path}/.'],
        <String>[root.path, '${child.path}/..'],
        <String>[root.path, alias.path],
      ]) {
        expect(
          () => LandlockFfi.validatePolicyExpressibility(
            SandboxPolicy(
              roots: <SandboxPathRule>[
                for (final candidate in paths)
                  SandboxPathRule(
                    path: candidate,
                    access: SandboxPathAccess.readOnly,
                  ),
              ],
            ),
          ),
          throwsA(isA<HostCapabilityException>()),
          reason: 'paths=$paths',
        );
      }
    } finally {
      if (await alias.exists()) await alias.delete();
      await root.delete(recursive: true);
    }
  });

  test('Landlock rejects host-specific network allowlists', () {
    final policy = SandboxPolicy(
      roots: <SandboxPathRule>[
        SandboxPathRule(
          path: Directory.current.absolute.path,
          access: SandboxPathAccess.readOnly,
        ),
      ],
      networkAllowlist: <SandboxNetworkEndpoint>[
        SandboxNetworkEndpoint(host: '127.0.0.1', port: 443),
      ],
    );

    expect(
      () => LandlockFfi.validatePolicyExpressibility(policy),
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.code,
          'code',
          HostCapabilityError.networkDenied,
        ),
      ),
    );
  });

  test('seccomp inventory blocks session escape and non-TCP channels', () {
    expect(
      SeccompFfi.blockedCapabilityNames,
      containsAll(<String>{
        'setsid',
        'setpgid',
        'unshare',
        'socket',
        'socketpair',
        'connect',
        'bind',
      }),
    );
  });

  test('ABI below 4 fails closed before spawning a runner', () async {
    final backend = LandlockSeccompSandboxBackend(
      capabilityProbe: SandboxCapabilityProbe(
        platform: SandboxPlatform.linuxX64,
        landlockAbi: () => 3,
        seccompSupported: () => true,
      ),
    );

    await expectLater(
      backend.start(
        SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: '/tmp',
              access: SandboxPathAccess.readOnly,
            ),
          ],
        ),
        HostCommand(executable: '/usr/bin/false'),
      ),
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.code,
          'code',
          HostCapabilityError.capabilityBelowMinimum,
        ),
      ),
    );
  });
}
