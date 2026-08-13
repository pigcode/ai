import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/workspace_path.dart';

late File _probeExecutable;
late Directory _probeDirectory;

final String _fixtureSecret =
    <String>['pigcode-fixture-', 'credential-', '8472'].join();
const _binding = CredentialGrantBinding(
  principalId: 'principal-current',
  policyVersion: 2,
);
final Object _seatbeltSkip = Platform.isMacOS
    ? false
    : 'SKIP-MANIFEST credential boundary platform='
        '${Platform.operatingSystem} backend=seatbelt-required';

void main() {
  setUpAll(() async {
    _probeDirectory = Directory.systemTemp.createTempSync('pigcode_dlp_probe_');
    _probeExecutable = File('${_probeDirectory.path}/probe');
    try {
      final dart = '${File(Platform.resolvedExecutable).parent.path}/dart';
      final compile = await Process.start(
        dart,
        <String>[
          'compile',
          'exe',
          resolveTestWorkspacePath(
            packageRelative: 'test/fixtures/dlp_probe.dart',
            workspaceRelative: 'packages/agent_io/test/fixtures/dlp_probe.dart',
          ),
          '-o',
          _probeExecutable.path,
        ],
        runInShell: false,
      );
      final output = utf8.decoder.bind(compile.stdout).join();
      final errors = utf8.decoder.bind(compile.stderr).join();
      late int exitCode;
      try {
        exitCode = await compile.exitCode.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        compile.kill(ProcessSignal.sigkill);
        await compile.exitCode.timeout(const Duration(seconds: 2));
        throw StateError('DLP probe compile deadline exceeded');
      }
      if (exitCode != 0) {
        throw StateError(
          'DLP probe compile failed: ${await output} ${await errors}',
        );
      }
    } on Object {
      if (_probeDirectory.existsSync()) {
        _probeDirectory.deleteSync(recursive: true);
      }
      rethrow;
    }
  });
  tearDownAll(() {
    if (_probeDirectory.existsSync()) {
      _probeDirectory.deleteSync(recursive: true);
    }
  });

  test('P4-TM-CRED-01 sandbox child cannot observe injected secret', () async {
    final root = await Directory.systemTemp.createTemp('pigcode_cred_scan_');
    final secret = _fixtureSecret;
    final vault = CredentialVault();
    final handle = vault.issue(
      utf8.encode(secret),
      scope: const CredentialScope(host: 'localhost', port: 443),
      binding: _binding,
    );
    try {
      await vault.redeem(
        handle,
        const CredentialScope(host: 'localhost', port: 443),
        _binding,
        (bytes) async {
          expect(utf8.decode(bytes), secret);
          final process = await _launchProbe(
            const <SandboxNetworkEndpoint>[],
            const <String>['scan-secret'],
            roots: <SandboxPathRule>[
              SandboxPathRule(
                path: root.path,
                access: SandboxPathAccess.readWrite,
              ),
              SandboxPathRule(
                path: _probeExecutable.parent.path,
                access: SandboxPathAccess.readOnly,
              ),
            ],
            workingDirectory: root.path,
          );
          final output = utf8.decoder.bind(process.stdout).join();
          final errors = utf8.decoder.bind(process.stderr).join();
          expect(await _boundedExit(process), 0, reason: await errors);
          expect(await output, 'SECRET_ABSENT\n');
        },
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('P4-TM-CRED-02 crash before outcome persists no secret', () async {
    final temp = Directory.systemTemp.createTempSync('pigcode_cred_');
    Process? host;
    try {
      host = await Process.start(
        Platform.resolvedExecutable,
        <String>[
          resolveTestWorkspacePath(
            packageRelative: 'test/fixtures/credential_crash_fixture.dart',
            workspaceRelative:
                'packages/agent_io/test/fixtures/credential_crash_fixture.dart',
          ),
          temp.path,
        ],
        runInShell: false,
      );
      final errors = utf8.decoder.bind(host.stderr).join();
      host.stdin.writeln(_fixtureSecret);
      await host.stdin.flush();
      final boundary = await host.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      expect(boundary, startsWith('BOUNDARY credential-injected '));
      final evidence = jsonDecode(
        File('${temp.path}/boundary-evidence.json').readAsStringSync(),
      ) as Map<String, Object?>;
      expect(evidence['phase'], 'credential-injected-before-outcome');
      host.kill(ProcessSignal.sigkill);
      await host.exitCode.timeout(const Duration(seconds: 2));
      expect(await errors, isEmpty);

      final persisted = temp
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.readAsStringSync())
          .join('\n');
      expect(persisted, isNot(contains(_fixtureSecret)));
      expect(persisted, contains('"outcome":"unknown"'));
    } finally {
      host?.kill(ProcessSignal.sigkill);
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    }
  });

  test('P4-TM-CRED-03 non-allowlisted secret exfil is kernel-denied', () async {
    final control = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final accepted = control.first;
      final process = await Process.start(
        _probeExecutable.path,
        <String>[
          'tcp-secret',
          InternetAddress.loopbackIPv4.address,
          '${control.port}',
          _fixtureSecret,
        ],
      );
      final socket = await accepted.timeout(const Duration(seconds: 2));
      expect(await utf8.decoder.bind(socket).join(), _fixtureSecret);
      expect(
        await process.exitCode.timeout(const Duration(seconds: 2)),
        0,
      );
      await socket.close();
    } finally {
      await control.close();
    }

    final denied = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final process = await _launchProbe(
        const <SandboxNetworkEndpoint>[],
        <String>[
          'tcp-secret',
          InternetAddress.loopbackIPv4.address,
          '${denied.port}',
          _fixtureSecret,
        ],
      );
      final errors = utf8.decoder.bind(process.stderr).join();
      process.stdout.drain<void>();
      expect(await _boundedExit(process), 77);
      expect(await errors, contains('Operation not permitted'));
      await expectLater(
        denied.first.timeout(const Duration(milliseconds: 500)),
        throwsA(isA<TimeoutException>()),
      );
    } finally {
      await denied.close();
    }
  }, skip: _seatbeltSkip);

  test('P4-TM-CRED-04 restart requires principal/policy reintersection',
      () async {
    const scope = CredentialScope(host: 'localhost', port: 443);
    final beforeRestart = CredentialVault();
    final oldHandle = beforeRestart.issue(
      utf8.encode(_fixtureSecret),
      scope: scope,
      binding: const CredentialGrantBinding(
        principalId: 'principal-before',
        policyVersion: 1,
      ),
    );

    final restarted = CredentialVault();
    await expectLater(
      restarted.redeem(oldHandle, scope, _binding, (_) async => null),
      throwsA(isA<HostCapabilityException>()),
    );
    await expectLater(
      () => restarted.rebindAfterRestart(
        utf8.encode(_fixtureSecret),
        requestedScope: scope,
        binding: _binding,
        allowedScopes: const <CredentialScope>[
          CredentialScope(host: 'localhost', port: 8443),
        ],
      ),
      throwsA(isA<HostCapabilityException>()),
    );
    final rebound = restarted.rebindAfterRestart(
      utf8.encode(_fixtureSecret),
      requestedScope: scope,
      binding: _binding,
      allowedScopes: const <CredentialScope>[scope],
    );
    expect(
      await restarted.redeem(
        rebound,
        scope,
        _binding,
        (bytes) async => utf8.decode(bytes),
      ),
      _fixtureSecret,
    );
  });

  test(
    'P4-TM-DLP-01 non-allowlisted TCP connect is kernel-denied',
    () async {
      final control = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      try {
        final accepted = control.first;
        final process = await Process.start(
          _probeExecutable.path,
          <String>[
            'tcp',
            InternetAddress.loopbackIPv4.address,
            '${control.port}',
          ],
          runInShell: false,
        );
        final socket = await accepted.timeout(const Duration(seconds: 2));
        await socket.close();
        expect(
          await process.exitCode.timeout(const Duration(seconds: 2)),
          0,
        );
      } finally {
        await control.close();
      }

      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      try {
        final process = await _launchProbe(
          const <SandboxNetworkEndpoint>[],
          <String>['tcp', 'localhost', '${server.port}'],
        );
        process.stdout.drain<void>();
        final errors = utf8.decoder.bind(process.stderr).join();
        expect(await _boundedExit(process), 77);
        expect(await errors, contains('Operation not permitted'));
        await expectLater(
          server.first.timeout(const Duration(milliseconds: 500)),
          throwsA(isA<TimeoutException>()),
        );
      } finally {
        await server.close();
      }
    },
    skip: Platform.isMacOS
        ? false
        : 'SKIP-MANIFEST DLP-01 platform=${Platform.operatingSystem} '
            'backend=seatbelt-required',
  );

  test('P4-TM-DLP-02 exact host and port allowlist permits TCP', () async {
    final adjacentAddress = await _nonLoopbackIpv4();
    final allowed = await _SocketObserver.bind(InternetAddress.loopbackIPv6);
    final adjacentPort =
        await _SocketObserver.bind(InternetAddress.loopbackIPv6);
    final adjacentIp = await _SocketObserver.bind(adjacentAddress);
    try {
      await _expectUnsandboxedTcpSucceeds(allowed, 'localhost');
      await _expectUnsandboxedTcpSucceeds(adjacentPort, 'localhost');
      await _expectUnsandboxedTcpSucceeds(adjacentIp, adjacentAddress.address);

      final allowedProcess = await _launchProbe(
        <SandboxNetworkEndpoint>[
          SandboxNetworkEndpoint(host: 'localhost', port: allowed.port),
        ],
        <String>['tcp', 'localhost', '${allowed.port}'],
      );
      final allowedErrors = utf8.decoder.bind(allowedProcess.stderr).join();
      allowedProcess.stdout.drain<void>();
      expect(await _boundedExit(allowedProcess), 0);
      expect(await allowedErrors, isNot(contains('Operation not permitted')));
      await allowed.waitForConnections(2);

      await _expectSandboxTcpDenied(
        <SandboxNetworkEndpoint>[
          SandboxNetworkEndpoint(host: 'localhost', port: allowed.port),
        ],
        'localhost',
        adjacentPort,
      );
      await _expectSandboxTcpDenied(
        <SandboxNetworkEndpoint>[
          SandboxNetworkEndpoint(host: 'localhost', port: allowed.port),
        ],
        adjacentAddress.address,
        adjacentIp,
      );
    } finally {
      await Future.wait<void>(<Future<void>>[
        allowed.close(),
        adjacentPort.close(),
        adjacentIp.close(),
      ]);
    }
  },
      skip: Platform.isMacOS
          ? false
          : 'SKIP-MANIFEST DLP-02 platform=${Platform.operatingSystem} '
              'backend=seatbelt-required');

  test('P4-TM-DLP-03 UDP DNS and unix bypasses are denied on Seatbelt',
      () async {
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final process = await _launchProbe(
        const <SandboxNetworkEndpoint>[],
        <String>['udp', 'localhost', '${udp.port}'],
      );
      process.stdout.drain<void>();
      final errors = utf8.decoder.bind(process.stderr).join();
      expect(await _boundedExit(process), 77);
      expect(await errors, contains('Operation not permitted'));
    } finally {
      udp.close();
    }
    final dnsControl = await Process.start(
      _probeExecutable.path,
      const <String>['dns', 'example.com'],
      runInShell: false,
    );
    dnsControl.stdout.drain<void>();
    final dnsControlErrors = utf8.decoder.bind(dnsControl.stderr).join();
    expect(
      await dnsControl.exitCode.timeout(const Duration(seconds: 3)),
      0,
      reason: await dnsControlErrors,
    );
    final dns = await _launchProbe(
      const <SandboxNetworkEndpoint>[],
      const <String>['dns', 'example.com'],
    );
    dns.stdout.drain<void>();
    final dnsErrors = utf8.decoder.bind(dns.stderr).join();
    expect(await _boundedExit(dns), 77);
    expect(await dnsErrors, contains('Failed host lookup'));
    expect(await dnsErrors, contains('errno = 8'));

    final unixRoot = Directory.systemTemp.createTempSync('pigcode_dlp_unix_');
    final socketPath = '${unixRoot.path}/boundary.sock';
    final unix = await _SocketObserver.bindUnix(socketPath);
    try {
      final control = await Process.start(
        _probeExecutable.path,
        <String>['unix', socketPath],
        runInShell: false,
      );
      control.stdout.drain<void>();
      control.stderr.drain<void>();
      expect(
        await control.exitCode.timeout(const Duration(seconds: 2)),
        0,
      );
      await unix.waitForConnections(1);

      final denied = await _launchProbe(
        const <SandboxNetworkEndpoint>[],
        <String>['unix', socketPath],
      );
      denied.stdout.drain<void>();
      final deniedErrors = utf8.decoder.bind(denied.stderr).join();
      expect(await _boundedExit(denied), 77);
      expect(await deniedErrors, contains('Operation not permitted'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(unix.connections, 1);
    } finally {
      await unix.close();
      unixRoot.deleteSync(recursive: true);
    }
  },
      skip: Platform.isMacOS
          ? false
          : 'SKIP-MANIFEST DLP-03 platform=${Platform.operatingSystem} '
              'backend=seatbelt-required');

  final linuxCapability = LandlockSeccompSandboxBackend().probe();
  final linuxCapabilityAvailable =
      Platform.isLinux && linuxCapability.productionReady;
  test('P4-TM-DLP-03 Linux runtime probe declares UDP/DNS/unix gaps', () {
    final manifest = DlpCapabilityManifest.forSandbox(
      linuxCapability,
    );
    expect(manifest.udp, DlpEnforcement.unsupported);
    expect(manifest.dns, DlpEnforcement.unsupported);
    expect(manifest.abstractUnixSocket, DlpEnforcement.unsupported);
  },
      skip: linuxCapabilityAvailable
          ? false
          : 'SKIP-MANIFEST DLP-03 runtime-probe '
              'platform=${Platform.operatingSystem} '
              'backend=${linuxCapability.backend} '
              'abi=${linuxCapability.landlockAbi ?? 'missing'}');

  test('P4-TM-DLP-04 roots-outside file sink is denied by Host', () {
    final root = Directory.systemTemp.createTempSync('pigcode_dlp_');
    try {
      final fs = HostWorkspaceFileSystem(<HostWorkspaceRoot>[
        HostWorkspaceRoot(
          name: 'workspace',
          path: root.path,
          access: SandboxPathAccess.readWrite,
        ),
      ]);
      expect(
        () => fs.writeText('workspace', '../sink', 'denied'),
        throwsA(isA<HostCapabilityException>()),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('P4-TM-DLP-05 sandbox output is redacted before persistence', () async {
    final root = Directory.systemTemp.createTempSync('pigcode_dlp_frame_');
    final persisted = File('${root.path}/diagnostic.frame');
    final secret = <String>['Bearer', ' boundary-sensitive-value'].join();
    try {
      final process = await _launchProbe(
        const <SandboxNetworkEndpoint>[],
        const <String>['frame'],
      );
      final raw = await process.stdout.expand((chunk) => chunk).toList();
      final errors = utf8.decoder.bind(process.stderr).join();
      expect(await _boundedExit(process), 0, reason: await errors);
      expect(utf8.decode(raw), contains(secret));

      final redacted = redactContentLengthFrame(raw);
      await persisted.writeAsBytes(redacted, flush: true);
      final durable = await persisted.readAsBytes();
      final separator = _indexOf(durable, const <int>[13, 10, 13, 10]);
      final header = ascii.decode(durable.sublist(0, separator));
      final outputBody = durable.sublist(separator + 4);
      expect(header, 'Content-Length: ${outputBody.length}');
      expect(utf8.decode(outputBody), isNot(contains(secret)));
      validateSafePersistedJson(
        jsonDecode(utf8.decode(outputBody)) as Map<String, Object?>,
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}

Future<SandboxedProcess> _launchProbe(
  List<SandboxNetworkEndpoint> endpoints,
  List<String> arguments, {
  List<SandboxPathRule>? roots,
  String? workingDirectory,
}) {
  return SeatbeltSandboxBackend(unsafeStandaloneStart: true).start(
    SandboxPolicy(
      roots: roots ??
          <SandboxPathRule>[
            SandboxPathRule(
              path: '/',
              access: SandboxPathAccess.readOnly,
            ),
          ],
      networkAllowlist: endpoints,
    ),
    HostCommand(
      executable: _probeExecutable.path,
      arguments: arguments,
      workingDirectory: workingDirectory,
    ),
  );
}

// The package-level test budget guards hangs without replacing target status.
Future<int> _boundedExit(SandboxedProcess process) => process.exitCode;

Future<InternetAddress> _nonLoopbackIpv4() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (!address.isLoopback) return address;
    }
  }
  throw StateError('DLP-02 requires a non-loopback IPv4 control target');
}

Future<void> _expectUnsandboxedTcpSucceeds(
  _SocketObserver observer,
  String host,
) async {
  final before = observer.connections;
  final process = await Process.start(
    _probeExecutable.path,
    <String>['tcp', host, '${observer.port}'],
    runInShell: false,
  );
  process.stdout.drain<void>();
  final errors = utf8.decoder.bind(process.stderr).join();
  expect(
    await process.exitCode.timeout(const Duration(seconds: 2)),
    0,
    reason: await errors,
  );
  await observer.waitForConnections(before + 1);
}

Future<void> _expectSandboxTcpDenied(
  List<SandboxNetworkEndpoint> allowlist,
  String host,
  _SocketObserver observer,
) async {
  final before = observer.connections;
  final process = await _launchProbe(
    allowlist,
    <String>['tcp', host, '${observer.port}'],
  );
  process.stdout.drain<void>();
  final errors = utf8.decoder.bind(process.stderr).join();
  expect(await _boundedExit(process), 77);
  expect(await errors, contains('Operation not permitted'));
  await Future<void>.delayed(const Duration(milliseconds: 200));
  expect(observer.connections, before);
}

final class _SocketObserver {
  _SocketObserver._(this.server) {
    _subscription = server.listen((socket) {
      connections += 1;
      socket.destroy();
    });
  }

  static Future<_SocketObserver> bind(InternetAddress address) async =>
      _SocketObserver._(await ServerSocket.bind(address, 0));

  static Future<_SocketObserver> bindUnix(String path) async =>
      _SocketObserver._(
        await ServerSocket.bind(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
        ),
      );

  final ServerSocket server;
  late final StreamSubscription<Socket> _subscription;
  int connections = 0;

  int get port => server.port;

  Future<void> waitForConnections(int expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (connections < expected && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(connections, expected);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await server.close();
  }
}

int _indexOf(List<int> bytes, List<int> pattern) {
  for (var index = 0; index <= bytes.length - pattern.length; index += 1) {
    var matches = true;
    for (var offset = 0; offset < pattern.length; offset += 1) {
      if (bytes[index + offset] != pattern[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return index;
  }
  throw StateError('separator missing');
}
