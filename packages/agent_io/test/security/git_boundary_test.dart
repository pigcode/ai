import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late Directory workspace;
  late HostGitClient git;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pigcode_git_');
    workspace = Directory('${temp.path}/workspace')..createSync();
    try {
      final init = await _runBounded('/usr/bin/git', <String>[
        'init',
        workspace.path,
      ]);
      expect(init.exitCode, 0, reason: '${init.stderr}');
      git = HostGitClient(
        workspace: workspace,
        launcher: SandboxedProcessLauncher.unsafeDev(SeatbeltSandboxBackend()),
      );
    } on Object {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
      rethrow;
    }
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('P4-TM-GIT-01 .git metadata remains read-only', () async {
    final config = '${workspace.path}/.git/config';
    final control = await _runBounded('/usr/bin/git', <String>[
      'config',
      '--file',
      config,
      'pigcode.control',
      'value',
    ]);
    expect(control.exitCode, 0, reason: '${control.stderr}');
    await _runBounded('/usr/bin/git', <String>[
      'config',
      '--file',
      config,
      '--unset',
      'pigcode.control',
    ]);

    final result = await git.run(const <String>[
      'config',
      'pigcode.denied',
      'value',
    ]);
    _expectSeatbeltDenial(result.exitCode, result.stderr);
    expect(
      File('${workspace.path}/.git/config').readAsStringSync(),
      isNot(contains('pigcode')),
    );
  }, skip: _gitSkip);

  test('P4-TM-GIT-02 non-allowlisted remote is kernel-denied', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final serving = server.listen((request) async {
      requests += 1;
      final advertisement =
          ascii.encode('001e# service=git-upload-pack\n00000000');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType(
          'application',
          'x-git-upload-pack-advertisement',
        )
        ..contentLength = advertisement.length
        ..add(advertisement);
      await request.response.close();
    }).asFuture<void>();
    final uri = 'http://${InternetAddress.loopbackIPv4.address}:'
        '${server.port}/repo';
    try {
      final control = await _runBounded(
        '/usr/bin/git',
        <String>['ls-remote', uri],
      );
      expect(control.exitCode, 0, reason: '${control.stderr}');
      final requestsAfterControl = requests;
      final result = await git.run(<String>[
        'ls-remote',
        uri,
      ]);
      _expectSeatbeltDenial(result.exitCode, result.stderr);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(requests, requestsAfterControl);
    } finally {
      await server.close();
      await serving;
    }
  }, skip: _gitSkip);

  test('P4-TM-GIT-03 credential paths are unreadable to git', () async {
    final credential = File('${temp.path}/credential')
      ..writeAsStringSync('[credential]\nhelper = secret-marker\n');
    final control = await _runBounded('/usr/bin/git', <String>[
      'config',
      '--file',
      credential.path,
      '--list',
    ]);
    expect(control.exitCode, 0, reason: '${control.stderr}');
    expect(control.stdout, contains('secret-marker'));
    final result = await git.run(
      <String>['config', '--file', credential.path, '--list'],
      additionalDenyReadPaths: <String>[credential.path],
    );
    _expectSeatbeltDenial(result.exitCode, result.stderr);
    expect(result.stdout, isNot(contains('secret-marker')));
  }, skip: _gitSkip);

  test('P4-TM-GIT-04 git descendants join unified cleanup', () async {
    final process = await git.start(const <String>[
      '-c',
      'alias.linger=!sleep 30',
      'linger',
    ]);
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    final report = await git.launcher.cleanup(process);
    expect(report.confirmed, isTrue);
    await expectLater(
      process.exitCode.timeout(const Duration(seconds: 2)),
      completes,
    );
  }, skip: _gitSkip);
}

final Object _gitSkip = Platform.isMacOS
    ? false
    : 'SKIP-MANIFEST nested read-only Git policy requires Seatbelt';

void _expectSeatbeltDenial(int exitCode, String errors) {
  expect(exitCode, isNot(0));
  expect(errors, contains('Operation not permitted'));
}

Future<ProcessResult> _runBounded(
  String executable,
  List<String> arguments,
) async {
  final process = await Process.start(
    executable,
    arguments,
    runInShell: false,
  );
  final output = utf8.decoder.bind(process.stdout).join();
  final errors = utf8.decoder.bind(process.stderr).join();
  try {
    final exitCode = await process.exitCode.timeout(const Duration(seconds: 5));
    return ProcessResult(
      process.pid,
      exitCode,
      await output,
      await errors,
    );
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(const Duration(seconds: 2));
    throw StateError('Process deadline exceeded: $executable $arguments');
  }
}
